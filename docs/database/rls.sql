-- ==========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

-- 1. Roles & System Setup
CREATE POLICY roles_read ON public.roles 
  FOR SELECT TO authenticated USING (true);

-- 2. Departments
CREATE POLICY departments_admin ON public.departments 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY departments_read ON public.departments 
  FOR SELECT TO authenticated USING (true);

-- 3. Terms & Academic Calibration
CREATE POLICY terms_admin ON public.terms 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY terms_read ON public.terms 
  FOR SELECT TO authenticated USING (true);

CREATE POLICY grade_scale_read ON public.grade_scale 
  FOR SELECT TO authenticated USING (true);

-- 4. Financial Configuration
CREATE POLICY fee_types_admin ON public.fee_types 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY fee_types_read ON public.fee_types 
  FOR SELECT TO authenticated USING (true);

-- 5. Document Management
CREATE POLICY doc_types_admin ON public.document_types 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY doc_types_read ON public.document_types 
  FOR SELECT TO authenticated USING (true);

CREATE POLICY docreq_read ON public.document_requests 
  FOR SELECT TO authenticated 
  USING (((student_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)));

CREATE POLICY docreq_registrar_process ON public.document_requests 
  FOR UPDATE TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)) 
  WITH CHECK ((((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (processed_by = (SELECT private.active_uid() AS active_uid))));

-- 6. Programs, Subjects, & Sections
CREATE POLICY programs_admin ON public.programs 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY programs_read ON public.programs 
  FOR SELECT TO authenticated USING (true);

CREATE POLICY subjects_admin ON public.subjects 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY subjects_read ON public.subjects 
  FOR SELECT TO authenticated USING (true);

CREATE POLICY sections_admin ON public.sections 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY sections_read ON public.sections 
  FOR SELECT TO authenticated USING (true);

-- 7. User Profiles & Students
CREATE POLICY profiles_admin_write ON public.profiles 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY profiles_read ON public.profiles 
  FOR SELECT TO authenticated 
  USING (((profile_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR (((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND private.student_in_my_department(profile_id))));

CREATE POLICY students_admin_write ON public.students 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY students_read ON public.students 
  FOR SELECT TO authenticated 
  USING (((student_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR (((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND private.student_in_my_department(student_id))));

CREATE POLICY dept_staff_admin_write ON public.department_staff 
  FOR ALL TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY dept_staff_read ON public.department_staff 
  FOR SELECT TO authenticated 
  USING (((profile_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text)));

-- 8. Enrollments & Coursework
CREATE POLICY enrollments_read ON public.enrollments 
  FOR SELECT TO authenticated 
  USING (((student_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)));

CREATE POLICY enrollments_registrar_review ON public.enrollments 
  FOR UPDATE TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)) 
  WITH CHECK ((((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (reviewed_by = (SELECT private.active_uid() AS active_uid))));

CREATE POLICY enrollment_items_read ON public.enrollment_items 
  FOR SELECT TO authenticated 
  USING ((((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) OR (EXISTS (
    SELECT 1 FROM enrollments e 
    WHERE e.enrollment_id = enrollment_items.enrollment_id 
      AND e.student_id = (SELECT private.active_uid() AS active_uid)
  ))));

CREATE POLICY enrollment_items_student_remove ON public.enrollment_items 
  FOR DELETE TO authenticated 
  USING ((EXISTS (
    SELECT 1 FROM enrollments e 
    WHERE e.enrollment_id = enrollment_items.enrollment_id 
      AND e.student_id = (SELECT private.active_uid() AS active_uid) 
      AND (e.status)::text = 'Pending'::text
  )));

-- 9. Grades
CREATE POLICY grades_read ON public.grades 
  FOR SELECT TO authenticated 
  USING ((((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) OR (EXISTS (
    SELECT 1 FROM (enrollment_items ei JOIN enrollments e ON e.enrollment_id = ei.enrollment_id) 
    WHERE ei.enrollment_item_id = grades.enrollment_item_id 
      AND e.student_id = (SELECT private.active_uid() AS active_uid)
  ))));

CREATE POLICY grades_registrar_update ON public.grades 
  FOR UPDATE TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)) 
  WITH CHECK ((((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND (encoded_by = (SELECT private.active_uid() AS active_uid))));

-- 10. Financials (Charges & Payments)
CREATE POLICY charges_cashier_update ON public.charges 
  FOR UPDATE TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text)) 
  WITH CHECK (((SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text));

CREATE POLICY charges_read ON public.charges 
  FOR SELECT TO authenticated 
  USING (((student_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text)));

CREATE POLICY payments_read ON public.payments 
  FOR SELECT TO authenticated 
  USING ((((SELECT private.current_role_name() AS current_role_name) = 'Cashier'::text) OR (EXISTS (
    SELECT 1 FROM charges c 
    WHERE c.charge_id = payments.charge_id 
      AND c.student_id = (SELECT private.active_uid() AS active_uid)
  ))));

-- 11. Clearances & Academic Holds
CREATE POLICY clearances_read ON public.clearances 
  FOR SELECT TO authenticated 
  USING (((student_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR (((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND private.clearance_in_my_department(clearance_id))));

CREATE POLICY clearances_registrar_approve ON public.clearances 
  FOR UPDATE TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text)) 
  WITH CHECK ((((SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text) AND ((approved_by IS NULL) OR (approved_by = (SELECT private.active_uid() AS active_uid)))));

CREATE POLICY clearance_items_dept_update ON public.clearance_items 
  FOR UPDATE TO authenticated 
  USING ((((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND (department_id = private.my_department_id()))) 
  WITH CHECK (((department_id = private.my_department_id()) AND ((cleared_by IS NULL) OR (cleared_by = (SELECT private.active_uid() AS active_uid)))));

CREATE POLICY clearance_items_read ON public.clearance_items 
  FOR SELECT TO authenticated 
  USING ((((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR (((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Cashier'::text, 'Department'::text])) AND (department_id = private.my_department_id())) OR (EXISTS (
    SELECT 1 FROM clearances c 
    WHERE c.clearance_id = clearance_items.clearance_id 
      AND c.student_id = (SELECT private.active_uid() AS active_uid)
  ))));

CREATE POLICY holds_dept_lift ON public.academic_holds 
  FOR UPDATE TO authenticated 
  USING ((((SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()))) 
  WITH CHECK (((department_id = private.my_department_id()) AND ((lifted_by IS NULL) OR (lifted_by = (SELECT private.active_uid() AS active_uid)))));

CREATE POLICY holds_read ON public.academic_holds 
  FOR SELECT TO authenticated 
  USING (((student_id = (SELECT private.active_uid() AS active_uid)) OR ((SELECT private.current_role_name() AS current_role_name) = ANY (ARRAY['Registrar'::text, 'Admin'::text])) OR (((SELECT private.current_role_name() AS current_role_name) = 'Department'::text) AND (department_id = private.my_department_id()))));

-- 12. Logs & Auditing
CREATE POLICY login_attempts_admin_read ON public.login_attempts 
  FOR SELECT TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));

CREATE POLICY audit_admin_read ON public.audit_logs 
  FOR SELECT TO authenticated 
  USING (((SELECT private.current_role_name() AS current_role_name) = 'Admin'::text));