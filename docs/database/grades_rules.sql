-- ==========================================
-- GRADES PATH: DATA API GRANTS AND RULES (GitHub issue #92, issue 36)
-- ==========================================
-- REQ-REG-01 (grades only for a subject the student is enrolled in), REQ-STU-02 (the
-- student reads own grades), SEC-02 (least privilege). Pattern: grants_clearance.sql.
-- Runs AFTER hardening.sql, hardening2.sql (A, B, C), views_extend.sql,
-- grants_clearance.sql and the three trigger_*.sql files (all live since 2026-10-11).
--
-- WHAT IT DOES
--   1. Grants on public.grades and public.v_grades (to the role authenticated only):
--        grades    SELECT, INSERT (enrollment_item_id, grade_code, encoded_by),
--                  UPDATE (grade_code, encoded_by)
--        v_grades  SELECT
--      Nothing else: no DELETE, no TRUNCATE / REFERENCES / TRIGGER / MAINTAIN, no
--      table-level INSERT / UPDATE, NOTHING for anon (and nothing for PUBLIC).
--   2. Trigger require_approved_enrollment (BEFORE INSERT OR UPDATE OF enrollment_item_id):
--      a grade can only be created for an enrollment item whose enrollment has status
--      'Approved'. Otherwise SQLSTATE P0001, message prefix "not approved:".
--   3. Trigger stamp_encoded_at (BEFORE INSERT OR UPDATE): encoded_at is always set by
--      the database (now(), the transaction time, as DEFAULT now() does); a value sent by
--      the client is ignored.
--   Already in place and NOT changed here (checked in section 1):
--     - RLS policies on grades (rls.sql): grades_read (Registrar, or the owner student
--       through enrollment_items -> enrollments), grades_registrar_insert and
--       grades_registrar_update (Registrar only, WITH CHECK encoded_by = the caller).
--     - grade_code must exist in grade_scale: foreign key fk_grades_grade_code
--       (schema.sql); a wrong code fails with SQLSTATE 23503.
--     - guard_immutable_columns on grades (hardening.sql): API users cannot change
--       enrollment_item_id.
--     - audit_log on grades (hardening2.sql B): every INSERT / UPDATE / DELETE is logged.
--
-- DESIGN DECISIONS
--   1. "Registrar only" = grants to authenticated + RLS. All signed-in users share the
--      database role authenticated, so the column grants open the columns to every
--      signed-in user and the existing policies decide who may write: only an active
--      Registrar, and only with encoded_by = own id (WITH CHECK, no IS NULL escape).
--      A Student or any other role gets "new row violates row-level security policy"
--      on INSERT and changes 0 rows on UPDATE (USING is Registrar only). Same approach
--      as grants_clearance.sql.
--   2. encoded_at is NOT granted. Issue #92 lists UPDATE (encoded_at) but also says
--      "encoded_at comes from the database"; granting the column would let the client
--      write any date (the trigger would overwrite it anyway). Not granting it makes an
--      UPDATE or INSERT that names encoded_at fail with "permission denied", so the app
--      must send only enrollment_item_id, grade_code, encoded_by (INSERT) and
--      grade_code, encoded_by (UPDATE).
--      stamp_encoded_at rule: every INSERT and every UPDATE sets encoded_at = now(), so
--      encoded_at is "the time of the last write" (a re-save of the same grade also
--      moves it, and audit_log then logs that write, exactly as before this file:
--      regression TC-24 re-saves a grade with encoded_at = now() and expects an audit
--      row). It applies to EVERY role, postgres and the SQL editor included (a
--      historical import with old dates needs a reviewed change that disables the
--      trigger for that run).
--   3. Approved rule, when it is checked: on INSERT, and on UPDATE only when
--      enrollment_item_id really changes (API users cannot change it at all, the guard
--      rejects that first; the owner can, and is checked). It is NOT re-checked when
--      only grade_code / encoded_by change, so a grade correction keeps working even if
--      the enrollment was later set back to Pending or Rejected. Rows that exist before
--      this file runs are not checked (diagnostic (d) lists any that break the rule).
--      Applies to every role, like the other business-rule triggers.
--   4. SECURITY INVOKER for both functions (no SECURITY DEFINER needed): the Registrar
--      reads every enrollment_items / enrollments row (enrollment_items_read,
--      enrollments_read; checked in section 1) and postgres bypasses RLS. A Student
--      sees only own rows: for another student's item the lookup finds nothing, the
--      trigger lets the row through and RLS WITH CHECK rejects it. So the trigger never
--      tells a user anything about an enrollment that user cannot already read. When
--      the item does not exist at all, the foreign key fk_grades_enrollment_item_id
--      rejects the row (23503).
--   5. Error: SQLSTATE 'P0001' with the stable prefix "not approved:" (same style as
--      "active hold:" and "pending items:"); PostgREST returns HTTP 400 with code
--      P0001. DETAIL carries enrollment_id and status, HINT says what to do.
--   6. Names and firing order on grades (BEFORE triggers by name, then RLS WITH CHECK
--      and constraints, then the write, then AFTER triggers):
--        INSERT: require_approved_enrollment -> stamp_encoded_at -> RLS WITH CHECK
--                -> write (unique, foreign keys) -> audit_log
--        UPDATE: guard_immutable_columns -> require_approved_enrollment (only when
--                enrollment_item_id is in the SET list) -> stamp_encoded_at
--                -> RLS WITH CHECK -> write -> audit_log
--      'g' < 'r' < 's', so the guard rejects an API user's attempt to move a grade to
--      another item before the approved check runs. Side effect of BEFORE triggers
--      running before RLS WITH CHECK: a Student inserting a grade for an item of their
--      OWN pending enrollment gets "not approved:" instead of the RLS error; both
--      reject the row.
--   7. Function grants like the other trigger functions (hardening2.sql section C): no
--      PUBLIC, no anon EXECUTE, explicit EXECUTE for authenticated.
--   8. Sequence: grade_id is GENERATED ALWAYS AS IDENTITY; inserting into an identity
--      column needs no grant on its sequence (as for payments and academic_holds).
--
-- KNOWN LIMITS (not done here, on purpose)
--   - Race: an enrollment set back from Approved in another, uncommitted transaction is
--     not seen (READ COMMITTED). Not worth a lock for this data and UI.
--   - No check that the grade is encoded during the item's term, or by a Registrar of a
--     particular department (no such rule in the SRS).
--   - Changing an enrollment from Approved to Rejected does not remove its grades.
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (REVOKE ALL then GRANT, CREATE OR REPLACE, DROP TRIGGER IF
-- EXISTS). GRANT / REVOKE / CREATE TRIGGER take a short lock on grades; well under a second.
--   - Before running: run diagnostics (a), (b) and (d) at the bottom and SAVE the output.
--   - Requires PostgreSQL 17 or later (MAINTAIN in the checks); the live project is 17.
--   - Check the output for "WARNING: no privileges could be revoked/granted"; the checks
--     in section 5 then stop the run.
--   - Rehearse first: docs/database/grades_rules_rehearsal.sql runs this change and all
--     tests (TC-83 to TC-93) in ONE rolled-back transaction with one result row.
-- Test AFTER: docs/database/grades_rules_test.sql (TC-83 to TC-93, one result row, rolled
-- back), then docs/database/regression_after_grants.sql (TC-12 to TC-33) again: same
-- results expected (TC-19 and TC-24 update a grade with encoded_at = now(); under the
-- temporary grant of that script this still works and the trigger stores now()).
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: NOT RUN YET (written without a local PostgreSQL; rehearse first).


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad    text;
  v_fn_req regprocedure := pg_catalog.to_regprocedure('private.require_approved_enrollment()');
  v_fn_st  regprocedure := pg_catalog.to_regprocedure('private.stamp_grade_encoded_at()');
BEGIN
  IF current_setting('server_version_num')::int < 170000 THEN
    RAISE EXCEPTION 'grades_rules: PostgreSQL 17+ required (MAINTAIN); found %', current_setting('server_version');
  END IF;

  -- a) The objects exist with the expected kind.
  SELECT string_agg(e.name, ', ') INTO v_bad
  FROM (VALUES ('grades', 'r'), ('enrollment_items', 'r'), ('enrollments', 'r'),
               ('grade_scale', 'r'), ('audit_logs', 'r'), ('v_grades', 'v')) AS e(name, kind)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                    WHERE c.relnamespace = 'public'::regnamespace
                      AND c.relname = e.name AND c.relkind::text = e.kind);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: missing or wrong kind: %; stop', v_bad;
  END IF;

  -- b) The columns the triggers and grants use exist with the expected types
  --    (format_type without typmod, so character varying matches any length).
  SELECT string_agg(e.t || '.' || e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('grades', 'grade_id', 'bigint'),
    ('grades', 'enrollment_item_id', 'bigint'),
    ('grades', 'grade_code', 'character varying'),
    ('grades', 'encoded_by', 'uuid'),
    ('grades', 'encoded_at', 'timestamp with time zone'),
    ('enrollment_items', 'enrollment_item_id', 'bigint'),
    ('enrollment_items', 'enrollment_id', 'bigint'),
    ('enrollments', 'enrollment_id', 'bigint'),
    ('enrollments', 'status', 'character varying')) AS e(t, col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.t)
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: missing column or other type: %; stop', v_bad;
  END IF;

  -- c) The status value 'Approved' is one of the allowed enrollment statuses.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                 WHERE k.conrelid = 'public.enrollments'::pg_catalog.regclass AND k.contype = 'c'
                   AND position('''Approved''' IN pg_catalog.pg_get_constraintdef(k.oid)) > 0) THEN
    RAISE EXCEPTION 'grades_rules: no CHECK on enrollments.status mentions ''Approved''; stop and review';
  END IF;

  -- d) RLS is enabled on the three tables, and v_grades is security_invoker.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace
    AND c.relname IN ('grades', 'enrollment_items', 'enrollments')
    AND NOT c.relrowsecurity;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: RLS is not enabled on %; stop', v_bad;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                 WHERE c.oid = 'public.v_grades'::pg_catalog.regclass
                   AND coalesce(c.reloptions @> ARRAY['security_invoker=true'], false)) THEN
    RAISE EXCEPTION 'grades_rules: v_grades is not security_invoker; stop';
  END IF;

  -- e) The policies on grades are exactly the live set (rls.sql): all PERMISSIVE, all TO
  --    authenticated, nothing more, nothing less.
  WITH expected(policyname, cmd) AS (VALUES
    ('grades_read', 'SELECT'),
    ('grades_registrar_insert', 'INSERT'),
    ('grades_registrar_update', 'UPDATE')),
  live AS (
    SELECT p.policyname::text, p.cmd::text
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = 'grades'
      AND p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[]),
  diff AS (
    (SELECT 'missing ' || policyname || ' ' || cmd AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || policyname || ' ' || cmd FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x)
    UNION ALL
    (SELECT 'not permissive / not TO authenticated: ' || p.policyname
     FROM pg_catalog.pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'grades'
       AND NOT (p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[])))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: policies on grades differ from the reviewed set: %; stop', v_bad;
  END IF;

  --    The two write policies are Registrar only and force encoded_by = the caller, with
  --    no "IS NULL" escape; the update policy's USING is Registrar only.
  SELECT string_agg(p.policyname, ', ') INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = 'grades'
    AND p.policyname IN ('grades_registrar_insert', 'grades_registrar_update')
    AND (p.with_check IS NULL
         OR position('''Registrar''' IN p.with_check) = 0
         OR position('encoded_by = ' IN p.with_check) = 0
         OR position('active_uid' IN p.with_check) = 0
         OR position('IS NULL' IN upper(p.with_check)) > 0
         OR (p.policyname = 'grades_registrar_update'
             AND (p.qual IS NULL OR position('''Registrar''' IN p.qual) = 0)));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: write policy text on grades is not the reviewed one: %; stop', v_bad;
  END IF;

  -- f) The Registrar can read every enrollment item and enrollment (the approved check
  --    runs as the caller, design decision 4).
  SELECT string_agg(e.t || '.' || e.p, ', ') INTO v_bad
  FROM (VALUES ('enrollment_items', 'enrollment_items_read'), ('enrollments', 'enrollments_read')) AS e(t, p)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
                    WHERE p.schemaname = 'public' AND p.tablename = e.t AND p.policyname = e.p
                      AND p.cmd = 'SELECT' AND p.permissive = 'PERMISSIVE'
                      AND position('''Registrar''' IN coalesce(p.qual, '')) > 0);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: read policy missing or not Registrar-wide: %; stop', v_bad;
  END IF;
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('enrollment_items'), ('enrollments'), ('grade_scale')) AS e(t)
  WHERE NOT pg_catalog.has_table_privilege('authenticated', pg_catalog.to_regclass('public.' || e.t), 'SELECT');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: authenticated has no SELECT on %; stop', v_bad;
  END IF;

  -- g) The foreign keys grade_code -> grade_scale and enrollment_item_id ->
  --    enrollment_items exist and are validated.
  SELECT string_agg(e.col, ', ') INTO v_bad
  FROM (VALUES ('grade_code', 'public.grade_scale'), ('enrollment_item_id', 'public.enrollment_items')) AS e(col, ref)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint k
    WHERE k.conrelid = 'public.grades'::pg_catalog.regclass AND k.contype = 'f' AND k.convalidated
      AND k.confrelid = pg_catalog.to_regclass(e.ref)
      AND k.conkey = ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a
                            WHERE a.attrelid = 'public.grades'::pg_catalog.regclass AND a.attname = e.col)]);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: foreign key missing or not validated on grades(%); stop', v_bad;
  END IF;

  -- h) The functions are absent (first run) or are this file's trigger functions (re-run).
  IF (v_fn_req IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn_req)
                               <> 'pg_catalog.trigger'::pg_catalog.regtype)
     OR (v_fn_st IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn_st)
                                 <> 'pg_catalog.trigger'::pg_catalog.regtype) THEN
    RAISE EXCEPTION 'grades_rules: private.require_approved_enrollment() or private.stamp_grade_encoded_at() exists and is not a trigger function; stop and review';
  END IF;

  -- i) No trigger with one of this file's names calls a different function.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE NOT t.tgisinternal
               AND ((t.tgname = 'require_approved_enrollment' AND (v_fn_req IS NULL OR t.tgfoid <> v_fn_req))
                 OR (t.tgname = 'stamp_encoded_at' AND (v_fn_st IS NULL OR t.tgfoid <> v_fn_st)))) THEN
    RAISE EXCEPTION 'grades_rules: a different trigger named require_approved_enrollment or stamp_encoded_at already exists; stop and review';
  END IF;

  -- j) The triggers on grades are exactly guard_immutable_columns (hardening.sql) and
  --    audit_log (hardening2.sql B), both enabled, plus this file's two on a re-run.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.grades'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'audit_log'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'require_approved_enrollment' AND v_fn_req IS NOT NULL AND t.tgfoid = v_fn_req)
          OR (t.tgname = 'stamp_encoded_at' AND v_fn_st IS NOT NULL AND t.tgfoid = v_fn_st));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: unexpected trigger(s) on grades: %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('audit_log')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.grades'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: trigger(s) missing or disabled on grades: %; stop', v_bad;
  END IF;

  -- k) audit_logs is append-only (hardening2.sql B).
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.audit_logs'::pg_catalog.regclass AND t.tgname = 'audit_logs_readonly'
                   AND t.tgenabled = 'A') THEN
    RAISE EXCEPTION 'grades_rules: audit_logs_readonly trigger missing or not ENABLE ALWAYS; stop';
  END IF;
END
$$;

-- ------------------------------------------
-- 2. The trigger functions
-- ------------------------------------------
-- a) Approved enrollment only (design decisions 3 to 5).
CREATE OR REPLACE FUNCTION private.require_approved_enrollment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
DECLARE
  v_enrollment bigint;
  v_status     text;
BEGIN
  IF TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW' OR TG_OP NOT IN ('INSERT', 'UPDATE')
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'grades' THEN
    RAISE EXCEPTION 'private.require_approved_enrollment must be a BEFORE INSERT OR UPDATE FOR EACH ROW trigger on public.grades';
  END IF;

  -- UPDATE: only when the grade moves to another enrollment item. (Nested IF, so OLD is
  -- never read in an INSERT.)
  IF TG_OP = 'UPDATE' THEN
    IF NEW.enrollment_item_id IS NOT DISTINCT FROM OLD.enrollment_item_id THEN
      RETURN NEW;
    END IF;
  END IF;

  SELECT e.enrollment_id, e.status::text INTO v_enrollment, v_status
  FROM public.enrollment_items ei
  JOIN public.enrollments e ON e.enrollment_id = ei.enrollment_id
  WHERE ei.enrollment_item_id = NEW.enrollment_item_id;

  -- Not found: the item does not exist (the foreign key rejects the row) or the caller
  -- cannot read it (only possible for a non-Registrar; RLS WITH CHECK rejects the row).
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_status IS DISTINCT FROM 'Approved' THEN
    RAISE EXCEPTION 'not approved: a grade can only be encoded for enrollment item % after its enrollment is Approved', NEW.enrollment_item_id
      USING ERRCODE = 'P0001',
            DETAIL = pg_catalog.format('enrollment_id %s, status %s', v_enrollment, v_status),
            HINT = 'Approve the enrollment first (enrollments.status = Approved), then encode the grade.';
  END IF;

  RETURN NEW;
END
$function$;

-- b) encoded_at always from the database (design decision 2).
CREATE OR REPLACE FUNCTION private.stamp_grade_encoded_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW' OR TG_OP NOT IN ('INSERT', 'UPDATE')
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'grades' THEN
    RAISE EXCEPTION 'private.stamp_grade_encoded_at must be a BEFORE INSERT OR UPDATE FOR EACH ROW trigger on public.grades';
  END IF;

  -- Every INSERT and every UPDATE: the time of the last write, whatever the client sent.
  NEW.encoded_at := pg_catalog.now();
  RETURN NEW;
END
$function$;

-- Same grant style as the other trigger functions (hardening2.sql section C).
REVOKE EXECUTE ON FUNCTION private.require_approved_enrollment() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.require_approved_enrollment() TO authenticated;
REVOKE EXECUTE ON FUNCTION private.stamp_grade_encoded_at() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.stamp_grade_encoded_at() TO authenticated;

-- ------------------------------------------
-- 3. The triggers (firing order in design decision 6)
-- ------------------------------------------
DROP TRIGGER IF EXISTS require_approved_enrollment ON public.grades;
CREATE TRIGGER require_approved_enrollment BEFORE INSERT OR UPDATE OF enrollment_item_id ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.require_approved_enrollment();

DROP TRIGGER IF EXISTS stamp_encoded_at ON public.grades;
CREATE TRIGGER stamp_encoded_at BEFORE INSERT OR UPDATE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.stamp_grade_encoded_at();

-- ------------------------------------------
-- 4. Grants on grades and v_grades (authenticated only)
-- ------------------------------------------
-- Start from nothing on these 2 objects (REVOKE on a table also removes its column
-- grants), so the result does not depend on what was there (for example a dashboard
-- toggle). Then authenticated gets back the SELECT it had (hardening2.sql section C)
-- plus the column writes below. RLS decides the rows (design decision 1).
REVOKE ALL ON public.grades, public.v_grades FROM PUBLIC, anon, authenticated;

-- Reads: grades_read (Registrar: all; Student: own, through enrollment_items ->
-- enrollments). v_grades is security_invoker, so it shows the same rows.
GRANT SELECT ON public.grades, public.v_grades TO authenticated;

-- INSERT (enrollment_item_id, grade_code, encoded_by). grade_id is an identity column;
-- encoded_at is left out (stamp_encoded_at sets it).
GRANT INSERT (enrollment_item_id, grade_code, encoded_by) ON public.grades TO authenticated;

-- UPDATE (grade_code, encoded_by): a grade correction; the policy forces encoded_by =
-- the caller. enrollment_item_id stays locked (guard_immutable_columns as well), and
-- encoded_at is not granted (design decision 2).
GRANT UPDATE (grade_code, encoded_by) ON public.grades TO authenticated;

-- ------------------------------------------
-- 5. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_fn_req regprocedure := pg_catalog.to_regprocedure('private.require_approved_enrollment()');
  v_fn_st  regprocedure := pg_catalog.to_regprocedure('private.stamp_grade_encoded_at()');
  v_bad    text;
BEGIN
  IF v_fn_req IS NULL OR v_fn_st IS NULL THEN
    RAISE EXCEPTION 'grades_rules: function(s) not created; rolled back';
  END IF;

  -- a) Functions: SECURITY INVOKER, empty search_path.
  IF (SELECT count(*) FROM pg_catalog.pg_proc p
      WHERE p.oid IN (v_fn_req, v_fn_st) AND NOT p.prosecdef
        AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']) <> 2 THEN
    RAISE EXCEPTION 'grades_rules: functions are not SECURITY INVOKER with an empty search_path; rolled back';
  END IF;

  -- b) Function grants: no PUBLIC entry in the ACL, anon cannot execute, authenticated can.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
             WHERE p.oid IN (v_fn_req, v_fn_st)
               AND (p.proacl IS NULL
                    OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
                    OR pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                    OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION 'grades_rules: function grants are not PUBLIC none / anon none / authenticated EXECUTE; rolled back';
  END IF;

  -- c) Triggers: both BEFORE INSERT OR UPDATE FOR EACH ROW (tgtype 1 ROW + 2 BEFORE +
  --    4 INSERT + 16 UPDATE = 23), enabled (origin), calling the right function;
  --    require_approved_enrollment only for UPDATE OF enrollment_item_id.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.grades'::pg_catalog.regclass
                   AND t.tgname = 'require_approved_enrollment' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn_req AND t.tgtype = 23 AND t.tgenabled = 'O'
                   AND position('UPDATE OF enrollment_item_id ON' IN pg_catalog.pg_get_triggerdef(t.oid)) > 0)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.grades'::pg_catalog.regclass
                      AND t.tgname = 'stamp_encoded_at' AND NOT t.tgisinternal
                      AND t.tgfoid = v_fn_st AND t.tgtype = 23 AND t.tgenabled = 'O') THEN
    RAISE EXCEPTION 'grades_rules: trigger require_approved_enrollment or stamp_encoded_at missing or not as intended; rolled back';
  END IF;

  -- d) Exactly the 4 expected triggers on grades now.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.grades'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, guard_immutable_columns, require_approved_enrollment, stamp_encoded_at' THEN
    RAISE EXCEPTION 'grades_rules: triggers on grades are [%]; rolled back', v_bad;
  END IF;

  -- e) anon (and PUBLIC): no privilege of any kind on grades or v_grades.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.grades'::pg_catalog.regclass, 'public.v_grades'::pg_catalog.regclass)
    AND (pg_catalog.has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
         OR pg_catalog.has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
         OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(c.relacl) a WHERE a.grantee = 0));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: anon or PUBLIC still has a privilege on %; rolled back', v_bad;
  END IF;

  -- f) authenticated: SELECT on both; on neither any table-level INSERT, UPDATE, DELETE,
  --    TRUNCATE, REFERENCES, TRIGGER or MAINTAIN.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.grades'::pg_catalog.regclass, 'public.v_grades'::pg_catalog.regclass)
    AND (NOT pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT')
         OR pg_catalog.has_table_privilege('authenticated', c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: wrong table-level grants for authenticated on %; rolled back', v_bad;
  END IF;

  -- g) The column grants of authenticated on grades and v_grades are exactly the 5 above.
  WITH expected(t, col, priv) AS (VALUES
    ('grades', 'enrollment_item_id', 'INSERT'), ('grades', 'grade_code', 'INSERT'),
    ('grades', 'encoded_by', 'INSERT'),
    ('grades', 'grade_code', 'UPDATE'), ('grades', 'encoded_by', 'UPDATE')),
  live AS (
    SELECT c.relname::text AS t, a.attname::text AS col, x.privilege_type::text AS priv
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
    WHERE c.oid IN ('public.grades'::pg_catalog.regclass, 'public.v_grades'::pg_catalog.regclass)
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
      AND x.grantee = 'authenticated'::regrole),
  diff AS (
    (SELECT 'missing ' || t || '.' || col || ' ' || priv AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || t || '.' || col || ' ' || priv FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: column grants differ: %; rolled back', v_bad;
  END IF;

  -- h) Nothing else lost: authenticated still reads every table and view in public
  --    (TC-27 auth_select_all).
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'p', 'f')
    AND NOT pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grades_rules: authenticated lost SELECT on %; rolled back', v_bad;
  END IF;
END
$$;

-- Ask PostgREST to reload its schema cache (sent when the transaction commits).
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state after grants_clearance.sql and the trigger_*.sql files)
-- ------------------------------------------
-- Before this file grades and v_grades had: authenticated SELECT only, nothing for anon
-- (hardening2.sql section C, views_extend.sql). Compare with the saved output of
-- diagnostic (a) afterwards. Grades written while this file was live stay, with their
-- audit rows.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS require_approved_enrollment ON public.grades;
-- DROP TRIGGER IF EXISTS stamp_encoded_at ON public.grades;
-- DROP FUNCTION IF EXISTS private.require_approved_enrollment();
-- DROP FUNCTION IF EXISTS private.stamp_grade_encoded_at();
--
-- REVOKE ALL ON public.grades, public.v_grades FROM PUBLIC, anon, authenticated;
-- GRANT SELECT ON public.grades, public.v_grades TO authenticated;
-- NOTIFY pgrst, 'reload schema';
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: exact ACLs of grades and v_grades (table and columns). Save the
--    "before" output; the ROLLBACK must return to it.
-- select c.relname, c.relkind::text, c.relacl::text as acl,
--        (select string_agg(a.attname || '=' || a.attacl::text, '; ' order by a.attnum)
--           from pg_attribute a
--          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attacl is not null) as column_acls
-- from pg_class c
-- where c.relnamespace = 'public'::regnamespace and c.relname in ('grades', 'v_grades')
-- order by 1;
--
-- b) BEFORE and AFTER: triggers on grades in firing order (BEFORE by name, then AFTER by
--    name). After: guard_immutable_columns, require_approved_enrollment,
--    stamp_encoded_at, audit_log.
-- select t.tgname,
--        case when (t.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
--        t.tgenabled, t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t
-- where t.tgrelid = 'public.grades'::regclass and not t.tgisinternal
-- order by case when (t.tgtype::int & 2) = 2 then 0 else 1 end, t.tgname;
--
-- c) AFTER: the functions' properties and grants.
-- select p.oid::regprocedure as function, pg_get_userbyid(p.proowner) as owner,
--        p.prosecdef as security_definer, p.proconfig, p.proacl::text as acl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
-- from pg_proc p
-- where p.oid in (to_regprocedure('private.require_approved_enrollment()'),
--                 to_regprocedure('private.stamp_grade_encoded_at()'));
--
-- d) BEFORE: existing grades whose enrollment is NOT Approved (the trigger does not touch
--    existing rows; the Registrar decides what to do with them). Expected: no rows.
-- select g.grade_id, g.enrollment_item_id, e.enrollment_id, e.student_id, e.status, g.grade_code
-- from public.grades g
-- join public.enrollment_items ei on ei.enrollment_item_id = g.enrollment_item_id
-- join public.enrollments e on e.enrollment_id = ei.enrollment_id
-- where e.status <> 'Approved'
-- order by 1;
--
-- e) AFTER: effective privileges per role (true = allowed; INSERT / UPDATE here are
--    table-level, column-level writes show in (f)).
-- select c.relname, r.rolname,
--        has_table_privilege(r.rolname, c.oid, 'SELECT') as sel,
--        has_table_privilege(r.rolname, c.oid, 'INSERT') as ins_table,
--        has_table_privilege(r.rolname, c.oid, 'UPDATE') as upd_table,
--        has_table_privilege(r.rolname, c.oid, 'DELETE') as del,
--        has_any_column_privilege(r.rolname, c.oid, 'INSERT') as ins_any_column,
--        has_any_column_privilege(r.rolname, c.oid, 'UPDATE') as upd_any_column
-- from pg_class c cross join (values ('anon'::name), ('authenticated'::name)) as r(rolname)
-- where c.relnamespace = 'public'::regnamespace and c.relname in ('grades', 'v_grades')
-- order by 1, 2;
--
-- f) AFTER: column grants (expect the 5 rows of section 4, all for authenticated):
-- select table_name, column_name, privilege_type, grantee
-- from information_schema.column_privileges
-- where table_schema = 'public' and grantee in ('anon', 'authenticated')
--   and privilege_type in ('INSERT', 'UPDATE') and table_name in ('grades', 'v_grades')
-- order by 1, 3, 2;


-- ==========================================
-- NOTES FOR THE PM (not done here, on purpose)
-- ==========================================
-- - The app's Registrar grade screen (issue #98) must send only enrollment_item_id,
--   grade_code and encoded_by = the signed-in user's id on INSERT, and only grade_code
--   and encoded_by on UPDATE. Sending encoded_at fails with "permission denied"; a grade
--   for a non-Approved enrollment fails with code P0001 and a message starting with
--   "not approved:"; an unknown grade code fails with code 23503.
-- - The server role is not touched (it has no INSERT / UPDATE on grades).
-- - Supabase default privileges still give new tables anon rights; exposing grades in
--   the dashboard's Data API settings would restore anon and DELETE rights: run this
--   file again afterwards (it is re-runnable).
