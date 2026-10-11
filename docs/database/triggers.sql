-- ==========================================
-- TABLE TRIGGERS (schema public) - RECORD ONLY, DO NOT RUN
-- ==========================================
-- A record of the app's triggers as they should exist after hardening.sql,
-- hardening2.sql (section B) and trigger_dept_approval.sql (section 5, run live 2026-10-11).
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
DO $$ BEGIN RAISE EXCEPTION 'docs/database/triggers.sql is a record, not a script; use hardening.sql / hardening2.sql / trigger_dept_approval.sql'; END $$;

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

ROLLBACK;
