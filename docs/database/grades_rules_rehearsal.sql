-- ==========================================
-- REHEARSAL: grades_rules.sql + TC-83 to TC-93 in ONE rolled-back transaction
-- ==========================================
-- GitHub issue #92 (issue 36). One paste, one run, ONE result row, nothing committed.
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file (from
-- "begin;" to "rollback;") and click Run on the whole tab, never a selection. If the
-- script stops with an error, run "rollback;" as its own query and send the error back.
--
-- What it does:
--   1. begin;
--   2. the body of docs/database/grades_rules.sql (everything between its "BEGIN;" and
--      "COMMIT;" lines, copied verbatim: safety checks, functions, triggers, grants,
--      checks after the change, NOTIFY). A "grades_rules: ..." error here means the live
--      state is not what the file assumes: do NOT run the file live. (The NOTIFY is
--      only delivered on COMMIT, so the rollback drops it.)
--   3. TC-83 to TC-93: docs/database/grades_rules_test.sql from its "begin;" line,
--      verbatim. It creates its own data as postgres (a throwaway term, sections,
--      enrollments, items and two grades). Each result is stored with
--      set_config('app.rNN', ...).
--   4. One final row: one cell per case, each ending in "-> OK" or "-> FAIL", plus
--      "all_ok". (Booleans inside the cells may print as t / f.)
--   5. rollback; (the triggers, the functions, the grants and all test data disappear)
--
-- RUNNING ONLY THE TESTS (after the change is live): the test part starts at the line
-- "-- TESTS START HERE" (line 456 of this file; its "begin;" is line 463) and is
-- self-contained: copy from the "begin;" line right below that marker to the end of the
-- file into a new tab and run it (or run grades_rules_test.sql, which is the same). It
-- ends in rollback, so it changes nothing.
--
-- Every statement that is expected to fail runs inside a do block with an exception
-- handler, so the transaction is never aborted by an expected error.
--
-- Status: NOT RUN YET.


begin;

-- ==========================================
-- 1. The change (body of grades_rules.sql, verbatim)
-- ==========================================

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



-- ==========================================
-- TESTS START HERE (TC-83 to TC-93)
-- ==========================================
-- To run ONLY the tests once grades_rules.sql is live: copy from the next line
-- ("begin;") to the end of this file into a new tab and run that tab as a whole.
-- In the full rehearsal the next line is a second BEGIN inside the open transaction;
-- PostgreSQL only answers "WARNING: there is already a transaction in progress" and
-- carries on (nothing is committed either way; the file ends in rollback).
begin;

-- ==========================================
-- Setup (as postgres, no user JWT; undone by the rollback)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',  coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',  coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.s3',  coalesce((select id::text from auth.users where email = 'student3@pnc.test'), ''), true);
select set_config('app.reg', coalesce((select id::text from auth.users where email = 'registrar@pnc.test'), ''), true);
select set_config('app.subj', coalesce((select min(subject_id)::text from public.subjects), ''), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.s3'),
            current_setting('app.reg'), current_setting('app.subj'))
     or (select count(*) from public.students
          where student_id::text in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.s3'))) <> 3
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                     where p.profile_id::text = current_setting('app.reg') and p.is_active and r.role_name = 'Registrar')
     or exists (select 1 from public.grade_scale where grade_code = 'X.XX')
     or not exists (select 1 from public.grade_scale where grade_code = '1.00')
     or not exists (select 1 from public.grade_scale where grade_code = '1.50')
     or not exists (select 1 from public.grade_scale where grade_code = '1.75')
     or not exists (select 1 from public.grade_scale where grade_code = '2.00') then
    raise exception 'TC setup: seed account, student, active Registrar, subject or grade_scale row missing (s1 [%], s2 [%], s3 [%], reg [%], subject [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.s3'),
      current_setting('app.reg'), current_setting('app.subj');
  end if;
end $$;

-- a throwaway term with three sections
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2093-2094', '1st', '2093-08-01', '2094-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
select current_setting('app.subj')::bigint, current_setting('app.term')::bigint, v.code, 'TC-83 test', 40
from (values ('TC-A'), ('TC-B'), ('TC-C')) as v(code);
select set_config('app.sec_a', (select min(section_id)::text from public.sections
  where term_id = current_setting('app.term')::bigint and section_code = 'TC-A'), true);
select set_config('app.sec_b', (select min(section_id)::text from public.sections
  where term_id = current_setting('app.term')::bigint and section_code = 'TC-B'), true);
select set_config('app.sec_c', (select min(section_id)::text from public.sections
  where term_id = current_setting('app.term')::bigint and section_code = 'TC-C'), true);

-- enrollments: submitted as Pending, then Student 1's and Student 3's approved by postgres
insert into public.enrollments (student_id, term_id, year_level)
values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint, 1),
       (current_setting('app.s2')::uuid, current_setting('app.term')::bigint, 1),
       (current_setting('app.s3')::uuid, current_setting('app.term')::bigint, 1);
select set_config('app.enr_a', (select min(enrollment_id)::text from public.enrollments
  where term_id = current_setting('app.term')::bigint and student_id = current_setting('app.s1')::uuid), true);
select set_config('app.enr_p', (select min(enrollment_id)::text from public.enrollments
  where term_id = current_setting('app.term')::bigint and student_id = current_setting('app.s2')::uuid), true);
select set_config('app.enr_o', (select min(enrollment_id)::text from public.enrollments
  where term_id = current_setting('app.term')::bigint and student_id = current_setting('app.s3')::uuid), true);
update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid, reviewed_at = now()
where enrollment_id in (current_setting('app.enr_a')::bigint, current_setting('app.enr_o')::bigint);

-- enrollment items: A1, A2, A3 (Student 1, Approved), P1 (Student 2, Pending), O1 (Student 3, Approved)
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.enr_a')::bigint, current_setting('app.sec_a')::bigint),
       (current_setting('app.enr_a')::bigint, current_setting('app.sec_b')::bigint),
       (current_setting('app.enr_a')::bigint, current_setting('app.sec_c')::bigint),
       (current_setting('app.enr_p')::bigint, current_setting('app.sec_a')::bigint),
       (current_setting('app.enr_o')::bigint, current_setting('app.sec_a')::bigint);
select set_config('app.item_a1', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_a')::bigint and section_id = current_setting('app.sec_a')::bigint), true);
select set_config('app.item_a2', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_a')::bigint and section_id = current_setting('app.sec_b')::bigint), true);
select set_config('app.item_a3', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_a')::bigint and section_id = current_setting('app.sec_c')::bigint), true);
select set_config('app.item_p1', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_p')::bigint), true);
select set_config('app.item_o1', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_o')::bigint), true);

-- grades encoded by postgres: A3 (Student 1's own) and O1 (another student's)
insert into public.grades (enrollment_item_id, grade_code, encoded_by)
values (current_setting('app.item_a3')::bigint, '1.50', current_setting('app.reg')::uuid),
       (current_setting('app.item_o1')::bigint, '2.00', current_setting('app.reg')::uuid);

-- ==========================================
-- TC-83: installed as intended (catalog, as postgres)
-- ==========================================
select set_config('app.r83', (select format('triggers [%s], functions_invoker_empty_path %s, function_grants_ok %s, anon_any_privilege %s, auth_select %s, auth_table_level_writes %s, auth_columns [%s] -> %s',
    x.trig, x.fn_ok, x.acl_ok, x.anon_any, x.auth_select, x.auth_table_writes, x.cols,
    case when x.trig = 'guard_immutable_columns (BEFORE) > require_approved_enrollment (BEFORE) > stamp_encoded_at (BEFORE) > audit_log (AFTER)'
          and x.fn_ok and x.acl_ok and not x.anon_any and x.auth_select and not x.auth_table_writes
          and x.cols = 'INSERT(encoded_by), INSERT(enrollment_item_id), INSERT(grade_code), UPDATE(encoded_by), UPDATE(grade_code)'
         then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(tg.tgname::text || ' (' || case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end || ')', ' > '
                       order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.grades'::regclass and not tg.tgisinternal) as trig,
    (select count(*) = 2 from pg_proc p
      where p.oid in (to_regprocedure('private.require_approved_enrollment()'), to_regprocedure('private.stamp_grade_encoded_at()'))
        and not p.prosecdef and p.proconfig && array['search_path=""', 'search_path='''''] ) as fn_ok,
    (select count(*) = 2 from pg_proc p
      where p.oid in (to_regprocedure('private.require_approved_enrollment()'), to_regprocedure('private.stamp_grade_encoded_at()'))
        and p.proacl is not null
        and not exists (select 1 from aclexplode(p.proacl) ac where ac.grantee = 0)
        and not has_function_privilege('anon', p.oid, 'EXECUTE')
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')) as acl_ok,
    (select bool_or(has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
                    or has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES'))
       from pg_class c where c.oid in ('public.grades'::regclass, 'public.v_grades'::regclass)) as anon_any,
    (has_table_privilege('authenticated', 'public.grades', 'SELECT')
     and has_table_privilege('authenticated', 'public.v_grades', 'SELECT')) as auth_select,
    has_table_privilege('authenticated', 'public.grades', 'INSERT, UPDATE, DELETE, TRUNCATE') as auth_table_writes,
    (select string_agg(ac.privilege_type || '(' || a.attname::text || ')', ', ' order by ac.privilege_type, a.attname)
       from pg_attribute a cross join lateral aclexplode(a.attacl) ac
      where a.attrelid = 'public.grades'::regclass and a.attnum > 0 and not a.attisdropped and a.attacl is not null
        and ac.grantee = 'authenticated'::regrole) as cols) x), true);

-- ==========================================
-- TC-84: Student 1 reads only own grades (grades and v_grades)
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare a bigint; b bigint; c bigint; d bigint; e bigint; f bigint;
begin
  select count(*) into a from public.grades;
  select count(*) into b from public.grades g
    join public.enrollment_items ei on ei.enrollment_item_id = g.enrollment_item_id
    join public.enrollments en on en.enrollment_id = ei.enrollment_id
    where en.student_id = auth.uid();
  select count(*) into c from public.v_grades where student_id is distinct from auth.uid();
  select count(*) into d from public.v_grades where enrollment_item_id = current_setting('app.item_a3')::bigint;
  select count(*) into e from public.grades where enrollment_item_id = current_setting('app.item_o1')::bigint;
  select count(*) into f from public.v_grades where enrollment_item_id = current_setting('app.item_o1')::bigint;
  perform set_config('app.t84', format('visible %s, own %s, v_grades_not_own %s, own_test_grade_in_v_grades %s, other_student_grade_in_grades %s, in_v_grades %s',
    a, b, c, d, e, f), true);
  perform set_config('app.t84_ok', (a = b and c = 0 and d = 1 and e = 0 and f = 0)::text, true);
exception when others then
  perform set_config('app.t84', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
  perform set_config('app.t84_ok', 'false', true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r84', format('student1 [%s], other_student_grade_exists_for_postgres %s -> %s',
  current_setting('app.t84'),
  (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_o1')::bigint),
  case when current_setting('app.t84_ok') = 'true'
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_o1')::bigint) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-85: Student 1 cannot write grades
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't85_insert', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                         values (current_setting('app.item_a2')::bigint, '1.00', auth.uid())$q$),
    (2, 't85_update', $q$update public.grades set grade_code = '1.00', encoded_by = auth.uid()
                         where enrollment_item_id = current_setting('app.item_a3')::bigint$q$),
    (3, 't85_delete', $q$delete from public.grades
                         where enrollment_item_id = current_setting('app.item_a3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r85', format('insert [%s], update_own [%s], delete_own [%s], a2_grades %s, a3_grade %s -> %s',
  current_setting('app.t85_insert'), current_setting('app.t85_update'), current_setting('app.t85_delete'),
  (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint),
  (select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a3')::bigint),
  case when current_setting('app.t85_insert') like 'rls: %'
        and current_setting('app.t85_update') = 'rows 0'
        and current_setting('app.t85_delete') like 'denied: %'
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint) = 0
        and (select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a3')::bigint) = '1.50'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-86: the Registrar inserts and updates a grade (A1)
-- ==========================================
-- mark the audit log first (read again in TC-93)
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't86_insert', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                         values (current_setting('app.item_a1')::bigint, '1.75', auth.uid())$q$),
    (2, 't86_update', $q$update public.grades set grade_code = '2.00', encoded_by = auth.uid()
                         where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.gid_a1', coalesce((select grade_id::text from public.grades
  where enrollment_item_id = current_setting('app.item_a1')::bigint), ''), true);
select set_config('app.r86', format('insert [%s], update [%s], stored_grade %s, encoded_by_is_registrar %s -> %s',
  current_setting('app.t86_insert'), current_setting('app.t86_update'),
  coalesce((select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  coalesce((select (encoded_by = current_setting('app.reg')::uuid)::text from public.grades
             where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  case when current_setting('app.t86_insert') = 'rows 1' and current_setting('app.t86_update') = 'rows 1'
        and exists (select 1 from public.grades
                     where enrollment_item_id = current_setting('app.item_a1')::bigint
                       and grade_code = '2.00' and encoded_by = current_setting('app.reg')::uuid)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-87: the Registrar cannot set encoded_by to someone else
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't87_insert_other', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                               values (current_setting('app.item_a2')::bigint, '1.00', current_setting('app.s1')::uuid)$q$),
    (2, 't87_update_other', $q$update public.grades set encoded_by = current_setting('app.s1')::uuid
                               where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r87', format('insert_with_other_encoded_by [%s], update_to_other_encoded_by [%s] -> %s',
  current_setting('app.t87_insert_other'), current_setting('app.t87_update_other'),
  case when current_setting('app.t87_insert_other') like 'rls: %'
        and current_setting('app.t87_update_other') like 'rls: %'
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint) = 0
        and exists (select 1 from public.grades
                     where enrollment_item_id = current_setting('app.item_a1')::bigint
                       and encoded_by = current_setting('app.reg')::uuid)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-88: anon is denied everything
-- ==========================================
set local role anon;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't88_select_grades',   $q$select count(*) from public.grades$q$),
    (2, 't88_select_v_grades', $q$select count(*) from public.v_grades$q$),
    (3, 't88_insert',          $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                  values (current_setting('app.item_a2')::bigint, '1.00', current_setting('app.reg')::uuid)$q$),
    (4, 't88_update',          $q$update public.grades set grade_code = '1.00'
                                  where enrollment_item_id = current_setting('app.item_a1')::bigint$q$),
    (5, 't88_delete',          $q$delete from public.grades
                                  where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'NOT DENIED, rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'permission denied%' then 'denied: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r88', format('select_grades [%s], select_v_grades [%s], insert [%s], update [%s], delete [%s] -> %s',
  current_setting('app.t88_select_grades'), current_setting('app.t88_select_v_grades'),
  current_setting('app.t88_insert'), current_setting('app.t88_update'), current_setting('app.t88_delete'),
  case when current_setting('app.t88_select_grades') like 'denied: %'
        and current_setting('app.t88_select_v_grades') like 'denied: %'
        and current_setting('app.t88_insert') like 'denied: %'
        and current_setting('app.t88_update') like 'denied: %'
        and current_setting('app.t88_delete') like 'denied: %'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-89: no DELETE for anyone through the API
-- ==========================================
-- The Student's and anon's DELETE are in TC-85 and TC-88; here the Registrar's.
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  delete from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t89_reg_delete', 'NOT DENIED, rows ' || n, true);
exception when others then
  perform set_config('app.t89_reg_delete',
    case when sqlerrm like 'permission denied%' then 'denied: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r89', format('registrar_delete [%s], student_delete [%s], anon_delete [%s], delete_grant_authenticated %s, delete_grant_anon %s, grade_still_there %s -> %s',
  current_setting('app.t89_reg_delete'), current_setting('app.t85_delete'), current_setting('app.t88_delete'),
  has_table_privilege('authenticated', 'public.grades', 'DELETE'), has_table_privilege('anon', 'public.grades', 'DELETE'),
  (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint),
  case when current_setting('app.t89_reg_delete') like 'denied: %'
        and current_setting('app.t85_delete') like 'denied: %'
        and current_setting('app.t88_delete') like 'denied: %'
        and not has_table_privilege('authenticated', 'public.grades', 'DELETE')
        and not has_table_privilege('anon', 'public.grades', 'DELETE')
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-90: a grade for a Pending enrollment is refused; accepted once Approved
-- ==========================================
-- step 1: the Registrar (insert for P1; moving A1's grade to P1)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't90_reg_insert_pending', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                     values (current_setting('app.item_p1')::bigint, '1.00', auth.uid())$q$),
    (2, 't90_reg_move_to_pending', $q$update public.grades set enrollment_item_id = current_setting('app.item_p1')::bigint
                                      where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- step 2: postgres (the rule applies to every role)
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't90_pg_insert_pending', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                    values (current_setting('app.item_p1')::bigint, '1.00', current_setting('app.reg')::uuid)$q$),
    (2, 't90_pg_move_to_pending', $q$update public.grades set enrollment_item_id = current_setting('app.item_p1')::bigint
                                     where enrollment_item_id = current_setting('app.item_a3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
select set_config('app.t90_p1_before', (select count(*)::text from public.grades
  where enrollment_item_id = current_setting('app.item_p1')::bigint), true);
-- step 3: postgres approves Student 2's enrollment; the Registrar tries again
update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid, reviewed_at = now()
where enrollment_id = current_setting('app.enr_p')::bigint;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  insert into public.grades (enrollment_item_id, grade_code, encoded_by)
  values (current_setting('app.item_p1')::bigint, '1.00', auth.uid());
  get diagnostics n = row_count;
  perform set_config('app.t90_reg_insert_approved', 'rows ' || n, true);
exception when others then
  perform set_config('app.t90_reg_insert_approved',
    case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         when sqlstate = '23503' then 'fk [23503]: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r90', format('registrar_insert_pending [%s], registrar_move_to_pending [%s], postgres_insert_pending [%s], postgres_move_to_pending [%s], p1_grades_while_pending %s, registrar_insert_after_approval [%s] -> %s',
  current_setting('app.t90_reg_insert_pending'), current_setting('app.t90_reg_move_to_pending'),
  current_setting('app.t90_pg_insert_pending'), current_setting('app.t90_pg_move_to_pending'),
  current_setting('app.t90_p1_before'), current_setting('app.t90_reg_insert_approved'),
  case when current_setting('app.t90_reg_insert_pending') like 'blocked [P0001]: not approved:%'
        and current_setting('app.t90_reg_move_to_pending') like 'denied: %'
        and current_setting('app.t90_pg_insert_pending') like 'blocked [P0001]: not approved:%'
        and current_setting('app.t90_pg_move_to_pending') like 'blocked [P0001]: not approved:%'
        and current_setting('app.t90_p1_before') = '0'
        and current_setting('app.t90_reg_insert_approved') = 'rows 1'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-91: an unknown grade_code is refused (foreign key to grade_scale)
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't91_insert_unknown', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                 values (current_setting('app.item_a2')::bigint, 'X.XX', auth.uid())$q$),
    (2, 't91_update_unknown', $q$update public.grades set grade_code = 'X.XX', encoded_by = auth.uid()
                                 where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r91', format('insert_unknown [%s], update_unknown [%s], a1_grade %s -> %s',
  current_setting('app.t91_insert_unknown'), current_setting('app.t91_update_unknown'),
  coalesce((select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  case when current_setting('app.t91_insert_unknown') like 'fk [23503]: %'
        and current_setting('app.t91_update_unknown') like 'fk [23503]: %'
        and (select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint) = '2.00'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-92: encoded_at comes from the database
-- ==========================================
-- step 1: the Registrar cannot name encoded_at at all (column not granted)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't92_reg_insert_encoded_at', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by, encoded_at)
                                        values (current_setting('app.item_a2')::bigint, '1.00', auth.uid(), '2000-01-01 00:00:00+00')$q$),
    (2, 't92_reg_update_encoded_at', $q$update public.grades set encoded_at = '2000-01-01 00:00:00+00'
                                        where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- step 2: postgres sends an old encoded_at on INSERT (A2) and on UPDATE (A3); the
-- trigger overwrites it with now() (the transaction time)
insert into public.grades (enrollment_item_id, grade_code, encoded_by, encoded_at)
values (current_setting('app.item_a2')::bigint, '1.00', current_setting('app.reg')::uuid, '2000-01-01 00:00:00+00');
update public.grades set encoded_at = '2000-01-01 00:00:00+00'
where enrollment_item_id = current_setting('app.item_a3')::bigint;
select set_config('app.r92', format('registrar_insert_with_encoded_at [%s], registrar_update_encoded_at [%s], postgres_insert_stored_now %s, postgres_update_stored_now %s, registrar_write_stored_now %s -> %s',
  current_setting('app.t92_reg_insert_encoded_at'), current_setting('app.t92_reg_update_encoded_at'),
  coalesce((select (encoded_at = now())::text from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint), '-'),
  coalesce((select (encoded_at = now())::text from public.grades where enrollment_item_id = current_setting('app.item_a3')::bigint), '-'),
  coalesce((select (encoded_at = now())::text from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  case when current_setting('app.t92_reg_insert_encoded_at') like 'denied: %'
        and current_setting('app.t92_reg_update_encoded_at') like 'denied: %'
        and (select count(*) from public.grades
              where enrollment_item_id in (current_setting('app.item_a1')::bigint, current_setting('app.item_a2')::bigint,
                                           current_setting('app.item_a3')::bigint)
                and encoded_at = now()) = 3
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-93: the Registrar's insert and update of A1 (TC-86) are in the audit log
-- ==========================================
-- Only those two writes of A1 succeeded after the mark; every other attempt on A1 failed.
select set_config('app.r93', (select format('grade_id %s, audit_rows %s, actions %s, actor_is_registrar %s, insert_grade %s, update_old_new %s/%s, new_encoded_by_is_registrar %s -> %s',
    current_setting('app.gid_a1'), a.audit_rows, coalesce(a.actions, '-'), a.actor_is_reg,
    coalesce(a.insert_grade, '-'), coalesce(a.update_old, '-'), coalesce(a.update_new, '-'), a.new_by_reg,
    case when a.audit_rows = 2 and a.actions = 'INSERT,UPDATE' and a.actor_is_reg
          and a.insert_grade = '1.75' and a.update_old = '1.75' and a.update_new = '2.00' and a.new_by_reg
         then 'OK' else 'FAIL' end)
  from (select count(*) as audit_rows,
               string_agg(l.action::text, ',' order by l.log_id) as actions,
               coalesce(bool_and(l.actor_id = current_setting('app.reg')::uuid), false) as actor_is_reg,
               max(case when l.action = 'INSERT' then l.new_data ->> 'grade_code' end) as insert_grade,
               max(case when l.action = 'UPDATE' then l.old_data ->> 'grade_code' end) as update_old,
               max(case when l.action = 'UPDATE' then l.new_data ->> 'grade_code' end) as update_new,
               coalesce(bool_and(l.new_data ->> 'encoded_by' = current_setting('app.reg')), false) as new_by_reg
        from public.audit_logs l
        where l.log_id > current_setting('app.log_mark')::bigint
          and l.table_name = 'grades'
          and l.record_id = current_setting('app.gid_a1')) a), true);

-- ==========================================
-- Result: ONE row. Every cell must end in "-> OK"; all_ok must be true.
-- ==========================================
select (current_setting('app.r83') like '%-> OK' and current_setting('app.r84') like '%-> OK'
        and current_setting('app.r85') like '%-> OK' and current_setting('app.r86') like '%-> OK'
        and current_setting('app.r87') like '%-> OK' and current_setting('app.r88') like '%-> OK'
        and current_setting('app.r89') like '%-> OK' and current_setting('app.r90') like '%-> OK'
        and current_setting('app.r91') like '%-> OK' and current_setting('app.r92') like '%-> OK'
        and current_setting('app.r93') like '%-> OK') as all_ok,
  current_setting('app.r83') as tc83, current_setting('app.r84') as tc84, current_setting('app.r85') as tc85,
  current_setting('app.r86') as tc86, current_setting('app.r87') as tc87, current_setting('app.r88') as tc88,
  current_setting('app.r89') as tc89, current_setting('app.r90') as tc90, current_setting('app.r91') as tc91,
  current_setting('app.r92') as tc92, current_setting('app.r93') as tc93;

rollback;
