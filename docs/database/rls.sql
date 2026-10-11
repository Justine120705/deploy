-- ==========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================
-- Run LAST (after schema.sql, views.sql, seed.sql and private_functions.sql).
-- RLS is enabled on every table first; a table without a policy is then closed to all users.

ALTER TABLE public.academic_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clearance_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clearances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grade_scale ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.terms ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------
-- POLICIES: all 49 policies exported from the live Supabase database (pg_policies,
-- schema public) on 2026-10-10. USING / WITH CHECK text is verbatim from the export.
-- Each policy is dropped first so this file can be re-run.
-- ------------------------------------------

-- academic_holds
DROP POLICY IF EXISTS holds_dept_lift ON public.academic_holds;
CREATE POLICY holds_dept_lift ON public.academic_holds
  FOR UPDATE TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id())))
  WITH CHECK (((department_id = private.my_department_id()) AND ((lifted_by IS NULL) OR (lifted_by = ( SELECT private.active_uid() AS active_uid)))));

DROP POLICY IF EXISTS holds_dept_place ON public.academic_holds;
CREATE POLICY holds_dept_place ON public.academic_holds
  FOR INSERT TO authenticated
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()) AND (placed_by = ( SELECT private.active_uid() AS active_uid)) AND (lifted_by IS NULL) AND (lifted_at IS NULL)));

DROP POLICY IF EXISTS holds_read ON public.academic_holds;
CREATE POLICY holds_read ON public.academic_holds
  FOR SELECT TO authenticated
  USING (((student_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR ((( SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()))));

-- audit_logs
DROP POLICY IF EXISTS audit_admin_read ON public.audit_logs;
CREATE POLICY audit_admin_read ON public.audit_logs
  FOR SELECT TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

-- charges
DROP POLICY IF EXISTS charges_cashier_update ON public.charges;
CREATE POLICY charges_cashier_update ON public.charges
  FOR UPDATE TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text));

DROP POLICY IF EXISTS charges_cashier_write ON public.charges;
CREATE POLICY charges_cashier_write ON public.charges
  FOR INSERT TO authenticated
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text));

DROP POLICY IF EXISTS charges_read ON public.charges;
CREATE POLICY charges_read ON public.charges
  FOR SELECT TO authenticated
  USING (((student_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text)));

-- clearance_items
DROP POLICY IF EXISTS clearance_items_dept_update ON public.clearance_items;
CREATE POLICY clearance_items_dept_update ON public.clearance_items
  FOR UPDATE TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND (department_id = private.my_department_id())))
  WITH CHECK (((department_id = private.my_department_id()) AND ((cleared_by IS NULL) OR (cleared_by = ( SELECT private.active_uid() AS active_uid)))));

DROP POLICY IF EXISTS clearance_items_read ON public.clearance_items;
CREATE POLICY clearance_items_read ON public.clearance_items
  FOR SELECT TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR ((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND (department_id = private.my_department_id())) OR (EXISTS ( SELECT 1
   FROM clearances c
  WHERE ((c.clearance_id = clearance_items.clearance_id) AND (c.student_id = ( SELECT private.active_uid() AS active_uid)))))));

-- clearances
DROP POLICY IF EXISTS clearances_read ON public.clearances;
CREATE POLICY clearances_read ON public.clearances
  FOR SELECT TO authenticated
  USING (((student_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR ((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND private.clearance_in_my_department(clearance_id))));

DROP POLICY IF EXISTS clearances_registrar_approve ON public.clearances;
CREATE POLICY clearances_registrar_approve ON public.clearances
  FOR UPDATE TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text))
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND ((approved_by IS NULL) OR (approved_by = ( SELECT private.active_uid() AS active_uid)))));

DROP POLICY IF EXISTS clearances_student_request ON public.clearances;
CREATE POLICY clearances_student_request ON public.clearances
  FOR INSERT TO authenticated
  WITH CHECK (((student_id = ( SELECT private.active_uid() AS active_uid)) AND (( SELECT private.current_role_name() AS current_role_name) = 'Student'::text) AND (approved_by IS NULL) AND (approved_at IS NULL)));

-- department_staff
DROP POLICY IF EXISTS dept_staff_admin_write ON public.department_staff;
CREATE POLICY dept_staff_admin_write ON public.department_staff
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS dept_staff_read ON public.department_staff;
CREATE POLICY dept_staff_read ON public.department_staff
  FOR SELECT TO authenticated
  USING (((profile_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)));

-- departments
DROP POLICY IF EXISTS departments_admin ON public.departments;
CREATE POLICY departments_admin ON public.departments
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS departments_read ON public.departments;
CREATE POLICY departments_read ON public.departments
  FOR SELECT TO authenticated
  USING (true);

-- document_requests
DROP POLICY IF EXISTS docreq_read ON public.document_requests;
CREATE POLICY docreq_read ON public.document_requests
  FOR SELECT TO authenticated
  USING (((student_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)));

DROP POLICY IF EXISTS docreq_registrar_process ON public.document_requests;
CREATE POLICY docreq_registrar_process ON public.document_requests
  FOR UPDATE TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text))
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (processed_by = ( SELECT private.active_uid() AS active_uid))));

DROP POLICY IF EXISTS docreq_student_submit ON public.document_requests;
CREATE POLICY docreq_student_submit ON public.document_requests
  FOR INSERT TO authenticated
  WITH CHECK (((student_id = ( SELECT private.active_uid() AS active_uid)) AND (( SELECT private.current_role_name() AS current_role_name) = 'Student'::text) AND ((status)::text = 'Pending'::text) AND (processed_by IS NULL) AND (processed_at IS NULL)));

-- document_types
DROP POLICY IF EXISTS doc_types_admin ON public.document_types;
CREATE POLICY doc_types_admin ON public.document_types
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS doc_types_read ON public.document_types;
CREATE POLICY doc_types_read ON public.document_types
  FOR SELECT TO authenticated
  USING (true);

-- enrollment_items
DROP POLICY IF EXISTS enrollment_items_read ON public.enrollment_items;
CREATE POLICY enrollment_items_read ON public.enrollment_items
  FOR SELECT TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) OR (EXISTS ( SELECT 1
   FROM enrollments e
  WHERE ((e.enrollment_id = enrollment_items.enrollment_id) AND (e.student_id = ( SELECT private.active_uid() AS active_uid)))))));

DROP POLICY IF EXISTS enrollment_items_student_add ON public.enrollment_items;
CREATE POLICY enrollment_items_student_add ON public.enrollment_items
  FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM enrollments e
  WHERE ((e.enrollment_id = enrollment_items.enrollment_id) AND (e.student_id = ( SELECT private.active_uid() AS active_uid)) AND ((e.status)::text = 'Pending'::text)))));

DROP POLICY IF EXISTS enrollment_items_student_remove ON public.enrollment_items;
CREATE POLICY enrollment_items_student_remove ON public.enrollment_items
  FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM enrollments e
  WHERE ((e.enrollment_id = enrollment_items.enrollment_id) AND (e.student_id = ( SELECT private.active_uid() AS active_uid)) AND ((e.status)::text = 'Pending'::text)))));

-- enrollments
DROP POLICY IF EXISTS enrollments_read ON public.enrollments;
CREATE POLICY enrollments_read ON public.enrollments
  FOR SELECT TO authenticated
  USING (((student_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)));

DROP POLICY IF EXISTS enrollments_registrar_review ON public.enrollments;
CREATE POLICY enrollments_registrar_review ON public.enrollments
  FOR UPDATE TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text))
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (reviewed_by = ( SELECT private.active_uid() AS active_uid))));

DROP POLICY IF EXISTS enrollments_student_submit ON public.enrollments;
CREATE POLICY enrollments_student_submit ON public.enrollments
  FOR INSERT TO authenticated
  WITH CHECK (((student_id = ( SELECT private.active_uid() AS active_uid)) AND (( SELECT private.current_role_name() AS current_role_name) = 'Student'::text) AND ((status)::text = 'Pending'::text) AND (reviewed_by IS NULL) AND (reviewed_at IS NULL)));

-- fee_types
DROP POLICY IF EXISTS fee_types_admin ON public.fee_types;
CREATE POLICY fee_types_admin ON public.fee_types
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS fee_types_read ON public.fee_types;
CREATE POLICY fee_types_read ON public.fee_types
  FOR SELECT TO authenticated
  USING (true);

-- grade_scale
DROP POLICY IF EXISTS grade_scale_read ON public.grade_scale;
CREATE POLICY grade_scale_read ON public.grade_scale
  FOR SELECT TO authenticated
  USING (true);

-- grades
DROP POLICY IF EXISTS grades_read ON public.grades;
CREATE POLICY grades_read ON public.grades
  FOR SELECT TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) OR (EXISTS ( SELECT 1
   FROM (enrollment_items ei
     JOIN enrollments e ON ((e.enrollment_id = ei.enrollment_id)))
  WHERE ((ei.enrollment_item_id = grades.enrollment_item_id) AND (e.student_id = ( SELECT private.active_uid() AS active_uid)))))));

DROP POLICY IF EXISTS grades_registrar_insert ON public.grades;
CREATE POLICY grades_registrar_insert ON public.grades
  FOR INSERT TO authenticated
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (encoded_by = ( SELECT private.active_uid() AS active_uid))));

DROP POLICY IF EXISTS grades_registrar_update ON public.grades;
CREATE POLICY grades_registrar_update ON public.grades
  FOR UPDATE TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text))
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (encoded_by = ( SELECT private.active_uid() AS active_uid))));

-- login_attempts
DROP POLICY IF EXISTS login_attempts_admin_read ON public.login_attempts;
CREATE POLICY login_attempts_admin_read ON public.login_attempts
  FOR SELECT TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

-- payments
DROP POLICY IF EXISTS payments_cashier_insert ON public.payments;
CREATE POLICY payments_cashier_insert ON public.payments
  FOR INSERT TO authenticated
  WITH CHECK (((( SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text) AND (recorded_by = ( SELECT private.active_uid() AS active_uid))));

DROP POLICY IF EXISTS payments_read ON public.payments;
CREATE POLICY payments_read ON public.payments
  FOR SELECT TO authenticated
  USING (((( SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text) OR (EXISTS ( SELECT 1
   FROM charges c
  WHERE ((c.charge_id = payments.charge_id) AND (c.student_id = ( SELECT private.active_uid() AS active_uid)))))));

-- profiles
DROP POLICY IF EXISTS profiles_admin_write ON public.profiles;
CREATE POLICY profiles_admin_write ON public.profiles
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS profiles_read ON public.profiles;
CREATE POLICY profiles_read ON public.profiles
  FOR SELECT TO authenticated
  USING (((profile_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR ((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND private.student_in_my_department(profile_id))));

-- programs
DROP POLICY IF EXISTS programs_admin ON public.programs;
CREATE POLICY programs_admin ON public.programs
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS programs_read ON public.programs;
CREATE POLICY programs_read ON public.programs
  FOR SELECT TO authenticated
  USING (true);

-- roles
DROP POLICY IF EXISTS roles_read ON public.roles;
CREATE POLICY roles_read ON public.roles
  FOR SELECT TO authenticated
  USING (true);

-- sections
DROP POLICY IF EXISTS sections_admin ON public.sections;
CREATE POLICY sections_admin ON public.sections
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS sections_read ON public.sections;
CREATE POLICY sections_read ON public.sections
  FOR SELECT TO authenticated
  USING (true);

-- students
DROP POLICY IF EXISTS students_admin_write ON public.students;
CREATE POLICY students_admin_write ON public.students
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS students_read ON public.students;
CREATE POLICY students_read ON public.students
  FOR SELECT TO authenticated
  USING (((student_id = ( SELECT private.active_uid() AS active_uid)) OR (( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR ((( SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND private.student_in_my_department(student_id))));

-- subjects
DROP POLICY IF EXISTS subjects_admin ON public.subjects;
CREATE POLICY subjects_admin ON public.subjects
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS subjects_read ON public.subjects;
CREATE POLICY subjects_read ON public.subjects
  FOR SELECT TO authenticated
  USING (true);

-- terms
DROP POLICY IF EXISTS terms_admin ON public.terms;
CREATE POLICY terms_admin ON public.terms
  FOR ALL TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

DROP POLICY IF EXISTS terms_read ON public.terms;
CREATE POLICY terms_read ON public.terms
  FOR SELECT TO authenticated
  USING (true);
