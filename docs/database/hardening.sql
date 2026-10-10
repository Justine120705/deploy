-- ==========================================
-- RLS HARDENING (GitHub issue #50)
-- ==========================================
-- Purpose: fix the policy findings recorded at the end of
-- docs/issue-12-testing-guide.md ("Policy observations from the live export").
--   1. "Who did it" columns can no longer be saved as NULL
--      (clearance_items_dept_update, holds_dept_lift, clearances_registrar_approve).
--   2. Columns that identify a row (student, term, owner, ...) cannot be changed by
--      API users: BEFORE UPDATE triggers, because RLS cannot restrict columns.
--   3. clearance_items_dept_update checks the role in WITH CHECK as well.
--   4. private.my_department_id() is deterministic (ORDER BY ... LIMIT 1).
--   5. holds_dept_place requires the student to be linked to the caller's department.
--   6. Grants are NOT changed here; diagnostic queries are at the end (commented).
--
-- How to run: AFTER rls.sql (and private_functions.sql), in the Supabase SQL editor,
-- as the whole file at once (never a selection). It is wrapped in BEGIN / COMMIT, so
-- any error rolls everything back. It is re-runnable: DROP ... IF EXISTS /
-- CREATE OR REPLACE.
-- Test afterwards: run Part C of docs/issue-12-testing-guide.md (TC-12 to TC-17 must
-- still pass) and the new Part F (TC-18 to TC-23).
-- Undo: see the ROLLBACK section at the bottom of this file.
--
-- Out of scope: audit triggers (REQ-ADM-03), views / generated types (issue #49), grants.

BEGIN;

-- ------------------------------------------
-- 4. private.my_department_id(): deterministic
-- ------------------------------------------
-- Before: Cashier branch used LIMIT 1 without ORDER BY (any Financial department could
-- come back if there is more than one); Department branch was a bare scalar subquery.
-- department_staff.profile_id is the primary key (schema.sql), so the Department branch
-- cannot return 2 rows today; ORDER BY ... LIMIT 1 only makes it safe if that key ever
-- changes. CREATE OR REPLACE keeps the owner and the existing grants (same signature).
CREATE OR REPLACE FUNCTION private.my_department_id()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT CASE private.current_role_name()
    WHEN 'Department' THEN (SELECT ds.department_id FROM public.department_staff ds
                            WHERE ds.profile_id = auth.uid()
                            ORDER BY ds.department_id LIMIT 1)
    WHEN 'Cashier'    THEN (SELECT d.department_id FROM public.departments d
                            WHERE d.department_type = 'Financial'
                            ORDER BY d.department_id LIMIT 1)
  END
$function$;

-- ------------------------------------------
-- 1 + 3. clearance_items_dept_update
-- ------------------------------------------
-- USING unchanged. WITH CHECK now also tests the role (finding 3) and requires
-- cleared_by = the caller (finding 1, no IS NULL escape).
-- Flow affected: "un-clearing" an item (setting cleared_at and cleared_by back to NULL)
-- through the API is now rejected; so is editing only `remarks` on a pending item
-- unless the update also sets cleared_by = the caller (the item stays "Pending" in
-- v_clearance_items because that status is derived from cleared_at).
DROP POLICY IF EXISTS clearance_items_dept_update ON public.clearance_items;
CREATE POLICY clearance_items_dept_update ON public.clearance_items
  FOR UPDATE TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND (department_id = private.my_department_id())))
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND (department_id = private.my_department_id()) AND (cleared_by = ( SELECT private.active_uid() AS active_uid))));

-- ------------------------------------------
-- 1. holds_dept_lift
-- ------------------------------------------
-- USING unchanged. WITH CHECK requires lifted_by = the caller.
-- Flow affected: "un-lifting" a hold (lifted_by / lifted_at back to NULL) through the
-- API is now rejected; place a new hold instead (INSERT, holds_dept_place).
DROP POLICY IF EXISTS holds_dept_lift ON public.academic_holds;
CREATE POLICY holds_dept_lift ON public.academic_holds
  FOR UPDATE TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id())))
  WITH CHECK (((department_id = private.my_department_id()) AND (lifted_by = ( SELECT private.active_uid() AS active_uid))));

-- ------------------------------------------
-- 1. clearances_registrar_approve
-- ------------------------------------------
-- USING unchanged. WITH CHECK requires approved_by = the caller.
-- Flow affected: "un-approving" a clearance (approved_by / approved_at back to NULL)
-- through the API is now rejected.
DROP POLICY IF EXISTS clearances_registrar_approve ON public.clearances;
CREATE POLICY clearances_registrar_approve ON public.clearances
  FOR UPDATE TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text))
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (approved_by = ( SELECT private.active_uid() AS active_uid))));

-- ------------------------------------------
-- 5. holds_dept_place
-- ------------------------------------------
-- Adds private.student_in_my_department(student_id).
-- LIMITATION: that helper does not read the student's program/department. It returns
-- true when the student has ANY clearance (any term) with a clearance_items row for the
-- caller's department. The clearances trigger (private.create_clearance_items) creates
-- one item per department for every clearance, so in practice this means "the student
-- has requested at least one clearance". Consequence: a Department user cannot place a
-- hold on a student who has never requested a clearance (possible flow break, see the
-- report). A stricter rule (students.program_id -> programs.department_id) would need a
-- new helper and a product decision, so it is not done here.
DROP POLICY IF EXISTS holds_dept_place ON public.academic_holds;
CREATE POLICY holds_dept_place ON public.academic_holds
  FOR INSERT TO authenticated
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()) AND private.student_in_my_department(student_id) AND (placed_by = ( SELECT private.active_uid() AS active_uid)) AND (lifted_by IS NULL) AND (lifted_at IS NULL)));

-- ------------------------------------------
-- 2. Immutable columns (BEFORE UPDATE triggers)
-- ------------------------------------------
-- One generic trigger function; the protected columns are passed as trigger arguments.
-- It only restricts API users (current_user = authenticated or anon), i.e. the same
-- users RLS restricts. postgres (SQL editor), the Supabase service role and SECURITY DEFINER
-- functions owned by postgres can still correct data, so administrative fixes are not
-- blocked. No Admin UPDATE policy exists on these 7 tables, so no Admin API flow is
-- affected either.
-- A misspelt column name raises an error instead of silently passing.
CREATE OR REPLACE FUNCTION private.guard_immutable_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_col text;
BEGIN
  IF TG_OP <> 'UPDATE' OR TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW' OR TG_NARGS = 0 THEN
    RAISE EXCEPTION 'private.guard_immutable_columns must be a BEFORE UPDATE FOR EACH ROW trigger with column names as arguments';
  END IF;

  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  v_old := to_jsonb(OLD);
  v_new := to_jsonb(NEW);
  FOREACH v_col IN ARRAY TG_ARGV LOOP
    IF NOT (v_old ? v_col) THEN
      RAISE EXCEPTION 'guard_immutable_columns: table % has no column %', TG_TABLE_NAME, v_col;
    END IF;
    IF (v_old -> v_col) IS DISTINCT FROM (v_new -> v_col) THEN
      RAISE EXCEPTION 'column %.% cannot be changed', TG_TABLE_NAME, v_col
        USING ERRCODE = '42501';
    END IF;
  END LOOP;
  RETURN NEW;
END
$function$;

-- Safety: stop if a trigger with the same name already exists and calls a different
-- function (this file must not replace a trigger it did not create).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname = 'guard_immutable_columns' AND NOT t.tgisinternal
               AND t.tgfoid <> 'private.guard_immutable_columns()'::pg_catalog.regprocedure) THEN
    RAISE EXCEPTION 'A different trigger named guard_immutable_columns already exists; stop and review';
  END IF;
END
$$;

-- charges: student_id, term_id, fee_type_id identify what the charge is and who owes
-- it. status must stay changeable (Unpaid -> Cleared / Waived). amount and due_date are
-- left changeable on purpose: a Cashier may need to correct a mistyped amount or extend
-- a due date, and payments are separate rows. To lock amount too, add 'amount' below.
DROP TRIGGER IF EXISTS guard_immutable_columns ON public.charges;
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.charges
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'term_id', 'fee_type_id');

-- grades: which enrollment item the grade belongs to. grade_code / encoded_* stay
-- changeable (grade corrections; grades_registrar_update already forces encoded_by).
DROP TRIGGER IF EXISTS guard_immutable_columns ON public.grades;
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('enrollment_item_id');

-- enrollments: the student and the term. status / review fields / remarks / year_level
-- stay changeable for the Registrar review.
DROP TRIGGER IF EXISTS guard_immutable_columns ON public.enrollments;
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'term_id');

-- document_requests: the student and the ticket number. status / processed_* /
-- remarks stay changeable for the Registrar.
DROP TRIGGER IF EXISTS guard_immutable_columns ON public.document_requests;
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.document_requests
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'ticket_number');

-- clearances: the student and the term. approved_* stay changeable.
DROP TRIGGER IF EXISTS guard_immutable_columns ON public.clearances;
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.clearances
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'term_id');

-- clearance_items: which clearance and which office. cleared_* / remarks stay changeable.
DROP TRIGGER IF EXISTS guard_immutable_columns ON public.clearance_items;
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.clearance_items
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('clearance_id', 'department_id');

-- academic_holds: everything set when the hold is placed. Only lifted_by / lifted_at
-- stay changeable.
DROP TRIGGER IF EXISTS guard_immutable_columns ON public.academic_holds;
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.academic_holds
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'department_id', 'placed_by', 'placed_at', 'reason');

COMMIT;


-- ==========================================
-- ROLLBACK (restores the behaviour before this file)
-- ==========================================
-- Uncomment and run as one block. The policy and function texts below are verbatim
-- copies of the originals in rls.sql (policies clearance_items_dept_update,
-- holds_dept_lift, clearances_registrar_approve, holds_dept_place) and
-- private_functions.sql (private.my_department_id). If those files changed after this
-- one was written, use the versions in those files instead.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS guard_immutable_columns ON public.charges;
-- DROP TRIGGER IF EXISTS guard_immutable_columns ON public.grades;
-- DROP TRIGGER IF EXISTS guard_immutable_columns ON public.enrollments;
-- DROP TRIGGER IF EXISTS guard_immutable_columns ON public.document_requests;
-- DROP TRIGGER IF EXISTS guard_immutable_columns ON public.clearances;
-- DROP TRIGGER IF EXISTS guard_immutable_columns ON public.clearance_items;
-- DROP TRIGGER IF EXISTS guard_immutable_columns ON public.academic_holds;
-- DROP FUNCTION IF EXISTS private.guard_immutable_columns();
--
-- DROP POLICY IF EXISTS clearance_items_dept_update ON public.clearance_items;
-- CREATE POLICY clearance_items_dept_update ON public.clearance_items
--   FOR UPDATE TO authenticated
--   USING (((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND (department_id = private.my_department_id())))
--   WITH CHECK (((department_id = private.my_department_id()) AND ((cleared_by IS NULL) OR (cleared_by = ( SELECT private.active_uid() AS active_uid)))));
--
-- DROP POLICY IF EXISTS holds_dept_lift ON public.academic_holds;
-- CREATE POLICY holds_dept_lift ON public.academic_holds
--   FOR UPDATE TO authenticated
--   USING (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id())))
--   WITH CHECK (((department_id = private.my_department_id()) AND ((lifted_by IS NULL) OR (lifted_by = ( SELECT private.active_uid() AS active_uid)))));
--
-- DROP POLICY IF EXISTS holds_dept_place ON public.academic_holds;
-- CREATE POLICY holds_dept_place ON public.academic_holds
--   FOR INSERT TO authenticated
--   WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()) AND (placed_by = ( SELECT private.active_uid() AS active_uid)) AND (lifted_by IS NULL) AND (lifted_at IS NULL)));
--
-- DROP POLICY IF EXISTS clearances_registrar_approve ON public.clearances;
-- CREATE POLICY clearances_registrar_approve ON public.clearances
--   FOR UPDATE TO authenticated
--   USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text))
--   WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND ((approved_by IS NULL) OR (approved_by = ( SELECT private.active_uid() AS active_uid)))));
--
-- CREATE OR REPLACE FUNCTION private.my_department_id()
--  RETURNS bigint
--  LANGUAGE sql
--  STABLE SECURITY DEFINER
--  SET search_path TO ''
-- AS $function$
--   SELECT CASE private.current_role_name()
--     WHEN 'Department' THEN (SELECT ds.department_id FROM public.department_staff ds WHERE ds.profile_id = auth.uid())
--     WHEN 'Cashier'    THEN (SELECT d.department_id FROM public.departments d WHERE d.department_type = 'Financial' LIMIT 1)
--   END
-- $function$;
--
-- COMMIT;


-- ==========================================
-- 6. DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database. Grants are deliberately NOT changed in this file.
--
-- a) Who can use schema private (ACL and effective privilege for anon / authenticated):
-- select n.nspname, n.nspacl,
--        has_schema_privilege('anon', n.oid, 'USAGE')          as anon_usage,
--        has_schema_privilege('authenticated', n.oid, 'USAGE') as authenticated_usage
-- from pg_namespace n where n.nspname = 'private';
--
-- b) Grants on every function in schema private (all 6 live ones, plus
--    guard_immutable_columns once this file has run):
-- select p.oid::regprocedure as function, p.prosecdef as security_definer, p.proacl,
--        has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'private' order by 1;
--
-- c) The same from information_schema (explicit grants only):
-- select routine_name, grantee, privilege_type, grantor
-- from information_schema.routine_privileges
-- where routine_schema = 'private' order by routine_name, grantee;
--
-- d) Is schema private exposed through the Data API? (Also check Dashboard ->
--    Project Settings -> Data API -> Exposed schemas; it should not list private.)
-- select rolname, rolconfig from pg_roles where rolname = 'authenticator';
--
-- e) All non-internal triggers outside the system schemas, with their full definition:
-- select n.nspname as schema, c.relname as table_name, t.tgname, t.tgenabled,
--        t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t
-- join pg_class c on c.oid = t.tgrelid
-- join pg_namespace n on n.oid = c.relnamespace
-- where not t.tgisinternal
--   and n.nspname not in ('pg_catalog', 'information_schema')
-- order by 1, 2, 3;
