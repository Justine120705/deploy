-- ==========================================
-- TABLE TRIGGERS (schema public) - RECORD ONLY, DO NOT RUN
-- ==========================================
-- A record of the app's triggers as they should exist after hardening.sql,
-- hardening2.sql (section B), trigger_dept_approval.sql (section 5, run live 2026-10-11),
-- trigger_finance_autoclear.sql (section 6, run live 2026-10-11) and
-- trigger_final_clearance.sql (section 7, run live 2026-10-11), grades_rules.sql
-- (section 8) and documents_rules.sql (section 9), both run live 2026-10-12.
-- The real source of these triggers is those files; this file only lists them in one
-- place so the repo shows the full picture.
-- Supabase's own triggers (schemas realtime, storage, auth) are not listed.
--
-- Verify against the live database with diagnostic (c) in hardening2.sql.
--
-- Firing order on one table: all BEFORE triggers, then the row change, then all AFTER
-- triggers; triggers of the same timing and event fire in alphabetical order of name.
--
-- The block below is wrapped in a transaction that is stopped by the first statement
-- and then rolled back, so running this file by mistake changes nothing.

BEGIN;
DO $$ BEGIN RAISE EXCEPTION 'docs/database/triggers.sql is a record, not a script; use hardening.sql / hardening2.sql / trigger_dept_approval.sql / trigger_finance_autoclear.sql / trigger_final_clearance.sql / grades_rules.sql / documents_rules.sql'; END $$;

-- ------------------------------------------
-- 1. Clearance items (pre-existing, not created by this repo's SQL)
-- ------------------------------------------
-- Table: public.clearances. Function: private.create_clearance_items()
-- (private_functions.sql): inserts one clearance_items row per department for the new
-- clearance.
-- trg_clearances_create_items
-- definition (pg_get_triggerdef, live, 2026-10-10):
--   CREATE TRIGGER trg_clearances_create_items AFTER INSERT ON public.clearances
--     FOR EACH ROW EXECUTE FUNCTION private.create_clearance_items()

-- ------------------------------------------
-- 2. Immutable columns (hardening.sql): BEFORE UPDATE, function
--    private.guard_immutable_columns(), protected columns as arguments
-- ------------------------------------------
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.charges
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'term_id', 'fee_type_id');
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('enrollment_item_id');
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'term_id');
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.document_requests
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'ticket_number');
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.clearances
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'term_id');
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.clearance_items
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('clearance_id', 'department_id');
CREATE TRIGGER guard_immutable_columns BEFORE UPDATE ON public.academic_holds
  FOR EACH ROW EXECUTE FUNCTION private.guard_immutable_columns('student_id', 'department_id', 'placed_by', 'placed_at', 'reason');

-- ------------------------------------------
-- 3. Audit log (hardening2.sql section B): AFTER INSERT OR UPDATE OR DELETE, function
--    private.audit_log(), primary-key column as the argument
-- ------------------------------------------
-- On clearances, audit_log fires before trg_clearances_create_items (alphabetical);
-- the clearance_items rows that trigger inserts are audited by their own trigger.
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('profile_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.students
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('student_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.department_staff
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('profile_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('enrollment_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.enrollment_items
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('enrollment_item_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('grade_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.charges
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('charge_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('payment_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.clearances
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('clearance_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.clearance_items
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('clearance_item_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.academic_holds
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('hold_id');
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.document_requests
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('request_id');

-- ------------------------------------------
-- 4. audit_logs is append-only (hardening2.sql section B): function
--    private.audit_logs_readonly() raises for every role; both are ENABLE ALWAYS
--    (they also fire with session_replication_role = replica)
-- ------------------------------------------
CREATE TRIGGER audit_logs_readonly BEFORE UPDATE OR DELETE ON public.audit_logs
  FOR EACH ROW EXECUTE FUNCTION private.audit_logs_readonly();
ALTER TABLE public.audit_logs ENABLE ALWAYS TRIGGER audit_logs_readonly;
CREATE TRIGGER audit_logs_readonly_truncate BEFORE TRUNCATE ON public.audit_logs
  FOR EACH STATEMENT EXECUTE FUNCTION private.audit_logs_readonly();
ALTER TABLE public.audit_logs ENABLE ALWAYS TRIGGER audit_logs_readonly_truncate;

-- ------------------------------------------
-- 5. Department approval requires no active hold (trigger_dept_approval.sql, issue #61,
--    REQ-DPT-03). Status: live since 2026-10-11. Function private.require_no_active_hold()
--    (SECURITY DEFINER, search_path ''): rejects cleared_at NULL -> NOT NULL while the
--    student has an active hold (lifted_at IS NULL) of the item's department; SQLSTATE
--    P0001, message "active hold: ...". Applies to every role.
-- ------------------------------------------
-- Firing order on clearance_items (BEFORE by name, then the write, then AFTER):
--   guard_immutable_columns (BEFORE) -> require_no_active_hold (BEFORE)
--   -> RLS WITH CHECK -> write -> audit_log (AFTER)
CREATE TRIGGER require_no_active_hold BEFORE UPDATE ON public.clearance_items
  FOR EACH ROW
  WHEN (NEW.cleared_at IS NOT NULL AND OLD.cleared_at IS NULL)
  EXECUTE FUNCTION private.require_no_active_hold();

-- ------------------------------------------
-- 6. Finance item clears automatically (trigger_finance_autoclear.sql, issue #62,
--    REQ-CSH-03). Status: live since 2026-10-11. One function private.finance_autoclear()
--    (SECURITY DEFINER, search_path ''), two triggers. When every charge of a student for
--    a term is Cleared or Waived (at least one charge), the pending Financial item of that
--    student's clearance for that term gets cleared_at = now(), cleared_by = the Cashier
--    who tagged the last charge. Skipped (item stays pending, nothing fails) when the
--    student has an active hold of the Financial department or no active Cashier can be
--    recorded (postgres / SQL editor). Never overwrites a cleared item, never un-clears.
-- ------------------------------------------
-- Firing order on charges (Cashier's UPDATE):
--   guard_immutable_columns (BEFORE) -> RLS WITH CHECK -> write
--   -> audit_log (AFTER) -> finance_autoclear (AFTER)
--      -> nested UPDATE of the Financial clearance_items row (as postgres, inside the
--         definer): guard_immutable_columns (BEFORE, lets the owner through)
--         -> require_no_active_hold (BEFORE) -> write -> audit_log (AFTER, actor = the Cashier)
-- Firing order on clearance_items:
--   INSERT (e.g. from trg_clearances_create_items):
--     write -> audit_log (AFTER) -> finance_autoclear_on_create (AFTER)
--     -> the same nested UPDATE of that row (audit actor = the requesting student,
--        new cleared_by = the Cashier from the last charge tag in audit_logs)
--   UPDATE (unchanged): guard_immutable_columns (BEFORE) -> require_no_active_hold (BEFORE)
--     -> RLS WITH CHECK -> write -> audit_log (AFTER)
-- "audit_log" sorts before "finance_autoclear..." ('a' < 'f'), so the charge's or the
-- item's INSERT audit row is always written before the item's UPDATE audit row. No
-- recursion: the nested UPDATE fires no INSERT trigger and no trigger on charges.
CREATE TRIGGER finance_autoclear AFTER INSERT OR UPDATE OF status, student_id, term_id ON public.charges
  FOR EACH ROW
  WHEN (NEW.status::text IN ('Cleared', 'Waived'))
  EXECUTE FUNCTION private.finance_autoclear();
CREATE TRIGGER finance_autoclear_on_create AFTER INSERT ON public.clearance_items
  FOR EACH ROW
  WHEN (NEW.cleared_at IS NULL)
  EXECUTE FUNCTION private.finance_autoclear();

-- ------------------------------------------
-- 7. Final clearance requires every item cleared (trigger_final_clearance.sql, issue #63,
--    REQ-REG-03). Status: live since 2026-10-11. Function
--    private.require_all_items_cleared() (SECURITY DEFINER, search_path ''): rejects
--    approved_at or approved_by going NULL -> value while any clearance_items row of that
--    clearance has cleared_at NULL (the Financial item included), or when the clearance has
--    no items; SQLSTATE P0001, message "pending items: ...", pending departments in DETAIL.
--    Applies to every role. Editing or un-approving an approved clearance is not checked.
--    Who may approve is unchanged (policy clearances_registrar_approve, Registrar only).
-- ------------------------------------------
-- Firing order on clearances:
--   UPDATE: guard_immutable_columns (BEFORE) -> require_all_items_cleared (BEFORE)
--           -> RLS WITH CHECK -> write -> audit_log (AFTER)
--   INSERT: write -> audit_log (AFTER) -> trg_clearances_create_items (AFTER)
--           (require_all_items_cleared is UPDATE only)
-- "require_all_items_cleared" sorts after "guard_immutable_columns" ('g' < 'r'). A rejected
-- approval stops before the write, so audit_log writes no row for it. It reads
-- clearance_items and departments only and writes nothing, so it cannot fire any other
-- trigger, and the triggers of sections 5 and 6 never update clearances.
CREATE TRIGGER require_all_items_cleared BEFORE UPDATE ON public.clearances
  FOR EACH ROW
  WHEN ((OLD.approved_at IS NULL AND NEW.approved_at IS NOT NULL)
        OR (OLD.approved_by IS NULL AND NEW.approved_by IS NOT NULL))
  EXECUTE FUNCTION private.require_all_items_cleared();

-- ------------------------------------------
-- 8. Grades rules (grades_rules.sql, issue #92, REQ-REG-01). Functions
--    private.require_approved_enrollment() and private.stamp_grade_encoded_at()
--    (both SECURITY INVOKER, search_path '').
-- ------------------------------------------
-- Firing order on grades:
--   INSERT: require_approved_enrollment (BEFORE) -> stamp_encoded_at (BEFORE) -> RLS WITH CHECK -> write -> audit_log (AFTER)
--   UPDATE: guard_immutable_columns (BEFORE) -> require_approved_enrollment (BEFORE, only UPDATE OF enrollment_item_id)
--           -> stamp_encoded_at (BEFORE) -> RLS WITH CHECK -> write -> audit_log (AFTER)
CREATE TRIGGER require_approved_enrollment BEFORE INSERT OR UPDATE OF enrollment_item_id ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.require_approved_enrollment();
CREATE TRIGGER stamp_encoded_at BEFORE INSERT OR UPDATE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION private.stamp_grade_encoded_at();

-- ------------------------------------------
-- 9. Document status flow (documents_rules.sql, issue #93, REQ-DOC-02): BEFORE UPDATE,
--    function private.require_document_status_flow() (SECURITY INVOKER). Allows only
--    Pending -> Processing -> Ready -> Released and Pending / Processing -> Rejected;
--    Released and Rejected are final; remarks cannot change while Pending; sets
--    processed_by / processed_at from the signed-in user.
-- ------------------------------------------
-- Firing order on document_requests:
--   UPDATE: guard_immutable_columns (BEFORE) -> require_document_status_flow (BEFORE)
--           -> RLS WITH CHECK -> write -> audit_log (AFTER)
--   INSERT: RLS WITH CHECK -> write -> audit_log (AFTER)
CREATE TRIGGER require_document_status_flow BEFORE UPDATE ON public.document_requests
  FOR EACH ROW EXECUTE FUNCTION private.require_document_status_flow();

ROLLBACK;
