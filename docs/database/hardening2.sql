-- ==========================================
-- RLS HARDENING, PART 2 (GitHub issue #50)
-- ==========================================
-- Follows docs/database/hardening.sql (findings 1 to 4, already live). This file has
-- THREE independent sections, each in its own BEGIN / COMMIT:
--
--   A. Finding 5: holds_dept_place also checks that the student's PROGRAM belongs to
--      the Department user's department (new helper
--      private.student_in_my_program_department).
--   B. Audit log (REQ-ADM-03): AFTER INSERT/UPDATE/DELETE triggers on 12 tables write
--      to public.audit_logs; audit_logs becomes append-only for every role.
--   C. Grants cleanup (least privilege): revoke TRUNCATE/REFERENCES/TRIGGER, all anon
--      table access, and PUBLIC execute on the 4 trigger functions.
--
-- How to run: in the Supabase SQL editor, ONE SECTION AT A TIME, in this order:
--   A, then B, then C.
-- Copy one section, from its "BEGIN;" line to its "COMMIT;" line inclusive, into a new
-- SQL editor tab and run that tab as a whole (never a partial selection inside a
-- section: without its BEGIN the statements would commit one by one). Each section is
-- a transaction: any error rolls that section back completely. Every
-- section is re-runnable (CREATE OR REPLACE / DROP ... IF EXISTS / idempotent
-- GRANT and REVOKE).
--   - C depends on B (it changes the grants of the two functions B creates). Do not
--     run C before B.
--   - Before running C, run diagnostic query (a) at the bottom and SAVE the output:
--     it is the exact grant state the ROLLBACK of C must return to.
--   - B creates/drops triggers on 13 tables (short exclusive locks). Run it at a quiet
--     time; it takes well under a second on this data size.
-- Test afterwards: Part G of docs/issue-12-testing-guide.md (TC-24 to TC-28), then
-- Part C and Part F again (TC-12 to TC-23 must still pass; TC-16 may now say
-- "permission denied", which is an accepted result).
-- Undo: each section has its own ROLLBACK block right after it. Undo in reverse order
-- (C, then B, then A).
--
-- Not done here (decisions for the PM, see the end of the file):
--   - No INSERT / UPDATE / DELETE grants to authenticated (app write access is a
--     separate decision).
--   - ALTER DEFAULT PRIVILEGES is not changed: tables created later in schema public
--     will again get Supabase's default grants (including anon SELECT) until that is
--     decided.
--   - The 5 existing RLS helper functions keep their grants.


-- ==========================================
-- SECTION A. Finding 5: holds_dept_place checks the student's department
-- ==========================================
-- The dropped idea: private.student_in_my_department(sid) (private_functions.sql) is
-- true when the student has a clearance with an item for my department. Every
-- clearance gets one item per department (private.create_clearance_items inserts a
-- row for EVERY department), so it really means "this student has requested any
-- clearance". It would let any department hold any student who requested a clearance
-- and would block holds on students who have not requested one yet.
--
-- The new helper uses the real link instead: students.program_id ->
-- programs.department_id. A Department user may only place a hold on a student whose
-- program belongs to that user's department (private.my_department_id()).
-- SECURITY DEFINER because Department users cannot read public.students for students
-- outside their clearance scope (students_read); search_path is empty, every name is
-- schema-qualified. Returns false (never NULL) when the caller has no department.
--
-- Flows affected:
--   - A department that teaches a student without owning the student's program (for
--     example a service subject) can no longer place a hold on that student.
--   - A Department user of a department with no programs (for example CAS in the seed)
--     can place no holds at all.
--   - Lifting a hold (holds_dept_lift) and reading holds are unchanged.
-- Every other condition of the live policy is kept verbatim (rls.sql).

BEGIN;

CREATE OR REPLACE FUNCTION private.student_in_my_program_department(sid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.students s JOIN public.programs pr ON pr.program_id = s.program_id
    WHERE s.student_id = sid AND pr.department_id = private.my_department_id())
$function$;

-- Same effective grants as the 5 existing helpers (anon cannot execute, authenticated
-- can; see "Grants on schema private and Data API exposure" in the testing guide).
REVOKE EXECUTE ON FUNCTION private.student_in_my_program_department(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.student_in_my_program_department(uuid) TO authenticated;

DROP POLICY IF EXISTS holds_dept_place ON public.academic_holds;
CREATE POLICY holds_dept_place ON public.academic_holds
  FOR INSERT TO authenticated
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()) AND (placed_by = ( SELECT private.active_uid() AS active_uid)) AND (lifted_by IS NULL) AND (lifted_at IS NULL) AND private.student_in_my_program_department(student_id)));

COMMIT;

-- ------------------------------------------
-- ROLLBACK of SECTION A (policy text verbatim from rls.sql)
-- ------------------------------------------
-- BEGIN;
--
-- DROP POLICY IF EXISTS holds_dept_place ON public.academic_holds;
-- CREATE POLICY holds_dept_place ON public.academic_holds
--   FOR INSERT TO authenticated
--   WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()) AND (placed_by = ( SELECT private.active_uid() AS active_uid)) AND (lifted_by IS NULL) AND (lifted_at IS NULL)));
--
-- DROP FUNCTION IF EXISTS private.student_in_my_program_department(uuid);
--
-- COMMIT;


-- ==========================================
-- SECTION B. Audit log (REQ-ADM-03)
-- ==========================================
-- REQ-ADM-03: "read-only audit log of all critical data changes, written by database
-- triggers. No role, including Admin, may update or delete audit entries".
--
-- 1. private.audit_log(): one generic AFTER ... FOR EACH ROW trigger function. The
--    primary-key column name is the only trigger argument; record_id is
--    to_jsonb(NEW or OLD) ->> that column.
--      actor_id   = auth.uid() if that id exists in public.profiles, else NULL
--                   (NULL from the SQL editor, seed scripts or a service-role call
--                   without a user; also NULL when the actor's own profile is the row
--                   being deleted). So the FK on actor_id can never make the original
--                   statement fail.
--      action     = TG_OP ('INSERT' / 'UPDATE' / 'DELETE', matches the CHECK)
--      table_name = TG_TABLE_NAME
--      old_data   = whole old row (UPDATE, DELETE), new_data = whole new row
--                   (INSERT, UPDATE).
--    An UPDATE that changes no column writes no audit row (it is not a data change).
--    SECURITY DEFINER (owner postgres) so it can insert into audit_logs although API
--    roles have no INSERT on it; search_path is empty, every name is schema-qualified.
--    A wrong argument (not a column) raises an error instead of silently logging
--    nothing; the install check below makes sure that cannot happen for these tables.
--
-- 2. Trigger order and recursion:
--    - Triggers of the same kind fire in alphabetical order of their names; BEFORE
--      triggers always fire before AFTER triggers.
--    - guard_immutable_columns (BEFORE UPDATE, hardening.sql) runs first. If it rejects
--      the change, the statement fails and no audit row is written. The same holds for
--      RLS WITH CHECK failures. Rows filtered out by RLS USING are not changed and not
--      logged.
--    - clearances has two AFTER INSERT triggers: audit_log fires before
--      trg_clearances_create_items ("a" < "t"). create_clearance_items then inserts the
--      clearance_items rows, which fire clearance_items' own audit_log trigger. The
--      actor stays the requesting student (auth.uid() reads the request claims, which a
--      SECURITY DEFINER function does not change). No recursion: audit_logs itself has
--      no audit trigger.
--    - TRUNCATE does not fire row triggers, so a TRUNCATE of an audited table would not
--      be logged; section C revokes TRUNCATE from the API roles.
--
-- 3. audit_logs is append-only: BEFORE UPDATE OR DELETE (per row) and BEFORE TRUNCATE
--    (per statement) triggers raise an exception for EVERY role, including postgres
--    and the Supabase service role. They are ENABLE ALWAYS, so they also fire when
--    session_replication_role = replica. INSERT, UPDATE, DELETE and TRUNCATE are
--    revoked from anon and authenticated; SELECT stays and the existing policy
--    audit_admin_read (Admin only) is unchanged.
--    Intentional purge (e.g. a retention rule): only the table owner can do it, in a
--    controlled, reviewed change, for example:
--      BEGIN;
--      ALTER TABLE public.audit_logs DISABLE TRIGGER audit_logs_readonly;
--      DELETE FROM public.audit_logs WHERE created_at < '<cut-off>';
--      ALTER TABLE public.audit_logs ENABLE ALWAYS TRIGGER audit_logs_readonly;
--      COMMIT;
--    This protects the log from the API and from mistakes; it is not protection against
--    the database owner, who can always drop a trigger.
--
-- Flows affected:
--   - A profile that appears as actor_id in audit_logs can no longer be hard-deleted
--     (FK fk_audit_logs_actor_id, no ON DELETE action, and audit rows cannot be changed).
--     Deactivate accounts (profiles.is_active = false) instead. Most profiles are already
--     referenced by other FKs (placed_by, encoded_by, ...), so this is rarely new.
--   - "Recreate the schema" resets (README) still work with DROP TABLE; TRUNCATE of
--     audit_logs does not.
--   - Rows that existed before this section runs are not back-filled.
--   - the Supabase service role (server-side key) can still INSERT audit rows directly; not revoked
--     here (see the notes at the end).

BEGIN;

CREATE OR REPLACE FUNCTION private.audit_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_old    jsonb;
  v_new    jsonb;
  v_record text;
  v_actor  uuid;
BEGIN
  IF TG_WHEN <> 'AFTER' OR TG_LEVEL <> 'ROW' OR TG_NARGS <> 1 THEN
    RAISE EXCEPTION 'private.audit_log must be an AFTER ... FOR EACH ROW trigger with the primary-key column name as its only argument';
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_old := to_jsonb(OLD);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_new := to_jsonb(NEW);
  END IF;

  -- An UPDATE that changes nothing is not a data change.
  IF TG_OP = 'UPDATE' AND v_old = v_new THEN
    RETURN NULL;
  END IF;

  v_record := COALESCE(v_new, v_old) ->> TG_ARGV[0];
  IF v_record IS NULL THEN
    RAISE EXCEPTION 'audit_log: table % has no column % (or it is NULL)', TG_TABLE_NAME, TG_ARGV[0];
  END IF;

  -- Only an actor that exists in profiles; otherwise NULL, so the FK cannot fail.
  SELECT p.profile_id INTO v_actor
  FROM public.profiles p
  WHERE p.profile_id = auth.uid();

  INSERT INTO public.audit_logs (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (v_actor, TG_OP, TG_TABLE_NAME, v_record, v_old, v_new);

  RETURN NULL;
END
$function$;

CREATE OR REPLACE FUNCTION private.audit_logs_readonly()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'audit_logs is append-only: % is not allowed', TG_OP
    USING ERRCODE = '42501',
          HINT = 'Audit entries can only be removed by the table owner in a controlled change (see docs/database/hardening2.sql, section B).';
END
$function$;

-- Safety checks (stop instead of guessing):
--  - a trigger with one of our names already exists and calls a different function;
--  - audit_logs has FORCE ROW LEVEL SECURITY (the owner's INSERT would then need a
--    policy and every audited write would fail);
--  - a trigger argument below is not the single-column primary key of its table.
DO $$
DECLARE
  v_table text;
  v_col   text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname = 'audit_log' AND NOT t.tgisinternal
               AND t.tgfoid <> 'private.audit_log()'::pg_catalog.regprocedure) THEN
    RAISE EXCEPTION 'A different trigger named audit_log already exists; stop and review';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname IN ('audit_logs_readonly', 'audit_logs_readonly_truncate') AND NOT t.tgisinternal
               AND t.tgfoid <> 'private.audit_logs_readonly()'::pg_catalog.regprocedure) THEN
    RAISE EXCEPTION 'A different trigger named audit_logs_readonly(_truncate) already exists; stop and review';
  END IF;

  IF (SELECT c.relforcerowsecurity FROM pg_catalog.pg_class c
      WHERE c.oid = 'public.audit_logs'::pg_catalog.regclass) THEN
    RAISE EXCEPTION 'public.audit_logs has FORCE ROW LEVEL SECURITY; private.audit_log() would need an INSERT policy; stop and review';
  END IF;

  FOR v_table, v_col IN
    SELECT v.t, v.c FROM (VALUES
      ('profiles', 'profile_id'), ('students', 'student_id'),
      ('department_staff', 'profile_id'), ('enrollments', 'enrollment_id'),
      ('enrollment_items', 'enrollment_item_id'), ('grades', 'grade_id'),
      ('charges', 'charge_id'), ('payments', 'payment_id'),
      ('clearances', 'clearance_id'), ('clearance_items', 'clearance_item_id'),
      ('academic_holds', 'hold_id'), ('document_requests', 'request_id')
    ) AS v(t, c)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
      WHERE i.indrelid = pg_catalog.to_regclass('public.' || v_table)
        AND i.indisprimary AND i.indnatts = 1 AND a.attname = v_col) THEN
      RAISE EXCEPTION 'audit_log: % is not the single-column primary key of public.%; stop and review', v_col, v_table;
    END IF;
  END LOOP;
END
$$;

-- audit_logs: append-only for everyone.
DROP TRIGGER IF EXISTS audit_logs_readonly ON public.audit_logs;
CREATE TRIGGER audit_logs_readonly BEFORE UPDATE OR DELETE ON public.audit_logs
  FOR EACH ROW EXECUTE FUNCTION private.audit_logs_readonly();
ALTER TABLE public.audit_logs ENABLE ALWAYS TRIGGER audit_logs_readonly;

DROP TRIGGER IF EXISTS audit_logs_readonly_truncate ON public.audit_logs;
CREATE TRIGGER audit_logs_readonly_truncate BEFORE TRUNCATE ON public.audit_logs
  FOR EACH STATEMENT EXECUTE FUNCTION private.audit_logs_readonly();
ALTER TABLE public.audit_logs ENABLE ALWAYS TRIGGER audit_logs_readonly_truncate;

-- API roles keep SELECT only (RLS policy audit_admin_read limits it to Admin).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.audit_logs FROM anon, authenticated;

-- Audit triggers (argument = primary-key column, checked above).
-- Not audited: audit_logs (itself), login_attempts (high volume, SEC-03) and the
-- catalog tables (departments, programs, subjects, sections, terms, roles,
-- grade_scale, fee_types, document_types).
DROP TRIGGER IF EXISTS audit_log ON public.profiles;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('profile_id');

DROP TRIGGER IF EXISTS audit_log ON public.students;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.students
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('student_id');

DROP TRIGGER IF EXISTS audit_log ON public.department_staff;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.department_staff
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('profile_id');

DROP TRIGGER IF EXISTS audit_log ON public.enrollments;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('enrollment_id');

DROP TRIGGER IF EXISTS audit_log ON public.enrollment_items;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.enrollment_items
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('enrollment_item_id');

DROP TRIGGER IF EXISTS audit_log ON public.grades;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('grade_id');

DROP TRIGGER IF EXISTS audit_log ON public.charges;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.charges
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('charge_id');

DROP TRIGGER IF EXISTS audit_log ON public.payments;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('payment_id');

DROP TRIGGER IF EXISTS audit_log ON public.clearances;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.clearances
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('clearance_id');

DROP TRIGGER IF EXISTS audit_log ON public.clearance_items;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.clearance_items
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('clearance_item_id');

DROP TRIGGER IF EXISTS audit_log ON public.academic_holds;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.academic_holds
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('hold_id');

DROP TRIGGER IF EXISTS audit_log ON public.document_requests;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.document_requests
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('request_id');

COMMIT;

-- ------------------------------------------
-- ROLLBACK of SECTION B
-- ------------------------------------------
-- Undo C first if C has been run. Audit rows written while B was active are KEPT
-- (dropping the triggers does not delete them). Before B, anon and authenticated had
-- TRUNCATE on audit_logs but no INSERT, UPDATE or DELETE (see "Grants found in the
-- live database" in the testing guide), so only TRUNCATE is granted back. If the
-- saved output of diagnostic (a) shows otherwise, grant what it shows instead.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS audit_log ON public.profiles;
-- DROP TRIGGER IF EXISTS audit_log ON public.students;
-- DROP TRIGGER IF EXISTS audit_log ON public.department_staff;
-- DROP TRIGGER IF EXISTS audit_log ON public.enrollments;
-- DROP TRIGGER IF EXISTS audit_log ON public.enrollment_items;
-- DROP TRIGGER IF EXISTS audit_log ON public.grades;
-- DROP TRIGGER IF EXISTS audit_log ON public.charges;
-- DROP TRIGGER IF EXISTS audit_log ON public.payments;
-- DROP TRIGGER IF EXISTS audit_log ON public.clearances;
-- DROP TRIGGER IF EXISTS audit_log ON public.clearance_items;
-- DROP TRIGGER IF EXISTS audit_log ON public.academic_holds;
-- DROP TRIGGER IF EXISTS audit_log ON public.document_requests;
-- DROP TRIGGER IF EXISTS audit_logs_readonly ON public.audit_logs;
-- DROP TRIGGER IF EXISTS audit_logs_readonly_truncate ON public.audit_logs;
-- DROP FUNCTION IF EXISTS private.audit_log();
-- DROP FUNCTION IF EXISTS private.audit_logs_readonly();
--
-- GRANT TRUNCATE ON public.audit_logs TO anon, authenticated;
--
-- COMMIT;


-- ==========================================
-- SECTION C. Grants cleanup (least privilege)
-- ==========================================
-- Requires section B (it changes the grants of private.audit_log() and
-- private.audit_logs_readonly()). Run diagnostic (a) first and save its output.
--
-- 1. TRUNCATE, REFERENCES, TRIGGER (and MAINTAIN) on every table and view in schema
--    public, from anon and authenticated. TRUNCATE ignores RLS and row triggers; nobody needs
--    REFERENCES (create FKs) or TRIGGER (create triggers).
-- 2. INSERT, UPDATE, DELETE on public.profiles from anon (RLS was the only thing
--    stopping anon; all profiles policies are TO authenticated).
-- 3. SELECT on every table and view in schema public from anon. RLS already returns 0
--    rows to anon (TC-16), this turns it into "permission denied". The app never reads
--    tables signed out: login uses Supabase Auth (signInWithPassword), and the proxy
--    and pages read profiles only with a signed-in (authenticated) session. Easy to
--    restore with the ROLLBACK below if a signed-out page ever needs a table.
--    Note: the future SEC-03 lockout check on login_attempts must use the service role
--    key server-side (as the TODO in app/(auth)/login/actions.ts already says), not anon.
-- 4. The 4 trigger functions lose the default PUBLIC execute (so anon cannot execute
--    them) and get an explicit EXECUTE for authenticated. PostgreSQL documents the
--    EXECUTE check on a trigger function at CREATE TRIGGER time, not when it fires; the
--    explicit grant makes sure signed-in users' writes keep working whatever is checked
--    at fire time. Other roles that write to these tables (the Supabase service role,
--    any auth hook) also lose the PUBLIC execute; they are not granted it here (the
--    repo's scrub forbids that role name in SQL files) and, per the documentation
--    above, do not need it. The 5 RLS helper functions are not touched.
--
-- Not done: no INSERT / UPDATE / DELETE is granted to authenticated on anything; the
-- Supabase default privileges for future tables are not changed.
-- Check the output: a "WARNING: no privileges could be revoked" means a grant was made
-- by another role (for example supabase_admin) and is still there; TC-27 will show it.

BEGIN;

REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM authenticated, anon;

-- MAINTAIN (PostgreSQL 17: VACUUM, ANALYZE, REINDEX, CLUSTER, LOCK) is not shown by
-- information_schema but is in the live ACLs (letter m, see grants_snapshot_2026-10-10.txt).
REVOKE MAINTAIN ON ALL TABLES IN SCHEMA public FROM authenticated, anon;

REVOKE INSERT, UPDATE, DELETE ON public.profiles FROM anon;

REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM anon;

REVOKE EXECUTE ON FUNCTION private.create_clearance_items() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.create_clearance_items() TO authenticated;

REVOKE EXECUTE ON FUNCTION private.guard_immutable_columns() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.guard_immutable_columns() TO authenticated;

REVOKE EXECUTE ON FUNCTION private.audit_log() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.audit_log() TO authenticated;

REVOKE EXECUTE ON FUNCTION private.audit_logs_readonly() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.audit_logs_readonly() TO authenticated;

COMMIT;

-- ------------------------------------------
-- ROLLBACK of SECTION C
-- ------------------------------------------
-- Restores the state recorded on 2026-10-10: anon SELECT on all public tables and
-- views, anon and authenticated TRUNCATE / REFERENCES / TRIGGER, anon INSERT / UPDATE /
-- DELETE on profiles, PUBLIC execute on the 4 trigger functions. Compare with the saved
-- output of diagnostic (a) afterwards; if it differs (for example a view had no
-- TRUNCATE before), adjust with a targeted REVOKE.
-- The explicit EXECUTE for authenticated is left in place: with PUBLIC
-- restored it changes nothing (authenticated is a member of PUBLIC), and the old draft
-- grants (private_functions.sql) suggest authenticated may have had it explicitly.
--
-- BEGIN;
--
-- GRANT TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public TO authenticated, anon;
-- GRANT MAINTAIN ON ALL TABLES IN SCHEMA public TO authenticated, anon;
-- -- Keep section B's protection while B is still in place (B revoked this):
-- REVOKE TRUNCATE ON public.audit_logs FROM authenticated, anon;
--
-- GRANT INSERT, UPDATE, DELETE ON public.profiles TO anon;
--
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
--
-- GRANT EXECUTE ON FUNCTION private.create_clearance_items() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION private.guard_immutable_columns() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION private.audit_log() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION private.audit_logs_readonly() TO PUBLIC;
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE section C, save this output (exact ACLs of every table / view in public and
--    every function in private; it is what the ROLLBACK of C must return to):
-- select 'table' as kind, c.relname as name, c.relkind::text as relkind, c.relacl::text as acl
-- from pg_class c
-- where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')
-- union all
-- select 'function', p.oid::regprocedure::text, null, p.proacl::text
-- from pg_proc p where p.pronamespace = 'private'::regnamespace
-- order by 1, 2;
--
-- b) Default privileges that will apply to tables / functions created LATER (not changed
--    by this file; a decision for the PM):
-- select pg_get_userbyid(d.defaclrole) as owner, d.defaclnamespace::regnamespace as schema,
--        d.defaclobjtype, d.defaclacl
-- from pg_default_acl d order by 1, 2, 3;
--
-- c) After section B: all non-internal triggers on public tables, in firing order
--    (use the trg_clearances_create_items line to fill in docs/database/triggers.sql):
-- select c.relname as table_name, t.tgname, t.tgenabled,
--        t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t join pg_class c on c.oid = t.tgrelid
-- where c.relnamespace = 'public'::regnamespace and not t.tgisinternal
-- order by 1, 2;
--
-- d) After section B: the latest audit rows:
-- select log_id, actor_id, action, table_name, record_id, created_at
-- from public.audit_logs order by log_id desc limit 20;


-- ==========================================
-- NOTES FOR THE PM (not done here, on purpose)
-- ==========================================
-- - the Supabase service role keeps INSERT on audit_logs, so server code with the service key could
--   write a fake audit row (it cannot change or delete one). To close that too:
--   REVOKE INSERT ON public.audit_logs FROM <the service role>; (the trigger runs as the
--   owner and does not need it).
-- - profiles_read / students_read still use private.student_in_my_department (the
--   clearance-based check) for Department and Cashier users. Switching reads to the
--   program-based helper is a separate decision (it changes what those users see).
-- - Supabase default privileges (diagnostic b) will grant anon SELECT and TRUNCATE etc.
--   again on new tables in public; either change them (ALTER DEFAULT PRIVILEGES, a
--   persistent setting) or repeat section C after adding tables.
- Exposing a table in the Supabase dashboard (Integrations, Data API, Settings) restores
  full default rights on it for anon, authenticated and the server role (this is how
  profiles got anon INSERT/UPDATE/DELETE). Whenever tables are exposed for the app,
  repeat the anon part of section C right afterwards.
- The server role currently has no SELECT/INSERT/UPDATE/DELETE on the 26 tables that are
  not exposed (snapshot: Dxtm only). Server-side code with the server key (for example
  the SEC-03 lockout) will need those tables exposed first.

