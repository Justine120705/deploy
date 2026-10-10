-- ==========================================
-- SEED DATA (fictional test records, ETH-01 / ETH-02)
-- ==========================================
-- Run AFTER schema.sql and BEFORE rls.sql.
-- Create the 7 test accounts in Supabase Auth first (Authentication -> Users);
-- profiles are linked to them by e-mail, so no UUIDs are hard-coded here.
--   admin@pnc.test, registrar@pnc.test, cashier@pnc.test, dept@pnc.test,
--   student1@pnc.test, student2@pnc.test, student3@pnc.test

-- 1. Roles
INSERT INTO public.roles (role_name) VALUES
  ('Student'), ('Registrar'), ('Cashier'), ('Department'), ('Admin')
ON CONFLICT (role_name) DO NOTHING;

-- 2. Departments (Financial = the Cashier's Office item of every clearance)
INSERT INTO public.departments (code, name, department_type) VALUES
  ('CCS', 'College of Computing Studies', 'Academic'),
  ('CBA', 'College of Business Administration', 'Academic'),
  ('CAS', 'College of Arts and Sciences', 'Academic'),
  ('CSH', 'Cashier''s Office', 'Financial')
ON CONFLICT (code) DO NOTHING;

-- 3. Programs
INSERT INTO public.programs (department_id, code, name)
SELECT d.department_id, v.code, v.name
FROM (VALUES
  ('CCS', 'BSCS', 'Bachelor of Science in Computer Science'),
  ('CCS', 'BSIT', 'Bachelor of Science in Information Technology'),
  ('CBA', 'BSBA', 'Bachelor of Science in Business Administration')
) AS v(dept, code, name)
JOIN public.departments d ON d.code = v.dept
ON CONFLICT (code) DO NOTHING;

-- 4. Current term
INSERT INTO public.terms (school_year, semester, start_date, end_date, is_current)
SELECT '2026-2027', '1st', DATE '2026-08-01', DATE '2026-12-20', true
WHERE NOT EXISTS (SELECT 1 FROM public.terms WHERE school_year = '2026-2027' AND semester = '1st');

-- 5. Grade scale
INSERT INTO public.grade_scale (grade_code, numeric_value, is_passing, description) VALUES
  ('1.00', 1.00, true,  'Excellent'),
  ('1.25', 1.25, true,  'Superior'),
  ('1.50', 1.50, true,  'Very good'),
  ('1.75', 1.75, true,  'Good'),
  ('2.00', 2.00, true,  'Satisfactory'),
  ('2.25', 2.25, true,  'Fairly satisfactory'),
  ('2.50', 2.50, true,  'Fair'),
  ('2.75', 2.75, true,  'Passing'),
  ('3.00', 3.00, true,  'Lowest passing grade'),
  ('5.00', 5.00, false, 'Failed'),
  ('INC',  NULL, false, 'Incomplete'),
  ('DRP',  NULL, false, 'Dropped')
ON CONFLICT (grade_code) DO NOTHING;

-- 6. Fee types and document types
INSERT INTO public.fee_types (name) VALUES ('Tuition'), ('Laboratory')
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.document_types (name) VALUES
  ('Official Transcript of Records'), ('Certificate of Grades')
ON CONFLICT (name) DO NOTHING;

-- 7. Profiles (linked to auth.users by e-mail)
INSERT INTO public.profiles (profile_id, role_id, first_name, last_name, email)
SELECT u.id, r.role_id, v.first_name, v.last_name, u.email
FROM (VALUES
  ('admin@pnc.test',    'Admin',      'System',    'Admin'),
  ('registrar@pnc.test','Registrar',  'Registrar', 'Office'),
  ('cashier@pnc.test',  'Cashier',    'Cashier',   'Office'),
  ('dept@pnc.test',     'Department', 'CCS',       'Staff'),
  ('student1@pnc.test', 'Student',    'Ana',       'Reyes'),
  ('student2@pnc.test', 'Student',    'Ben',       'Santos'),
  ('student3@pnc.test', 'Student',    'Carla',     'Mendoza')
) AS v(email, role_name, first_name, last_name)
JOIN auth.users u ON u.email = v.email
JOIN public.roles r ON r.role_name = v.role_name
ON CONFLICT (profile_id) DO NOTHING;

-- 8. Students
INSERT INTO public.students (student_id, student_number, program_id)
SELECT p.profile_id, v.student_number, pr.program_id
FROM (VALUES
  ('student1@pnc.test', '2026-0001', 'BSCS'),
  ('student2@pnc.test', '2026-0002', 'BSIT'),
  ('student3@pnc.test', '2026-0003', 'BSBA')
) AS v(email, student_number, program)
JOIN public.profiles p ON p.email = v.email
JOIN public.programs pr ON pr.code = v.program
ON CONFLICT (student_id) DO NOTHING;

-- 9. Department staff
INSERT INTO public.department_staff (profile_id, department_id)
SELECT p.profile_id, d.department_id
FROM (VALUES ('dept@pnc.test', 'CCS'), ('cashier@pnc.test', 'CSH')) AS v(email, dept)
JOIN public.profiles p ON p.email = v.email
JOIN public.departments d ON d.code = v.dept
ON CONFLICT (profile_id) DO NOTHING;

-- 10. Subjects and sections (current term)
INSERT INTO public.subjects (department_id, code, title, units)
SELECT d.department_id, v.code, v.title, v.units
FROM (VALUES
  ('CCS', 'CS101',  'Introduction to Computing', 3),
  ('CCS', 'CS102',  'Computer Programming 1',    3),
  ('CAS', 'GE101',  'Understanding the Self',    3)
) AS v(dept, code, title, units)
JOIN public.departments d ON d.code = v.dept
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.sections (subject_id, term_id, section_code, schedule, capacity)
SELECT s.subject_id, t.term_id, v.section_code, v.schedule, 40
FROM (VALUES
  ('CS101', 'CS-1A', 'MWF 8-9 AM'),
  ('CS102', 'CS-1A', 'TTh 9-10:30 AM'),
  ('GE101', 'GE-1B', 'MWF 10-11 AM')
) AS v(subject, section_code, schedule)
JOIN public.subjects s ON s.code = v.subject
CROSS JOIN (SELECT term_id FROM public.terms WHERE is_current LIMIT 1) t;

-- 11. Enrollments: Ana and Carla approved, Ben pending (3 subjects each)
INSERT INTO public.enrollments (student_id, term_id, year_level, status, submitted_at, reviewed_by, reviewed_at)
SELECT p.profile_id, t.term_id, 1, v.status, v.submitted::timestamptz,
       CASE WHEN v.status = 'Approved' THEN reg.profile_id END,
       CASE WHEN v.status = 'Approved' THEN (v.submitted::timestamptz + interval '1 day') END
FROM (VALUES
  ('student1@pnc.test', 'Approved', '2026-09-20'),
  ('student2@pnc.test', 'Pending',  '2026-09-22'),
  ('student3@pnc.test', 'Approved', '2026-09-21')
) AS v(email, status, submitted)
JOIN public.profiles p ON p.email = v.email
CROSS JOIN (SELECT term_id FROM public.terms WHERE is_current LIMIT 1) t
CROSS JOIN (SELECT profile_id FROM public.profiles WHERE email = 'registrar@pnc.test') reg;

INSERT INTO public.enrollment_items (enrollment_id, section_id)
SELECT e.enrollment_id, sec.section_id
FROM public.enrollments e
CROSS JOIN public.sections sec;

-- 12. Grades for Ana (encoded by the Registrar)
INSERT INTO public.grades (enrollment_item_id, grade_code, encoded_by)
SELECT ei.enrollment_item_id, v.grade, reg.profile_id
FROM public.enrollment_items ei
JOIN public.enrollments e ON e.enrollment_id = ei.enrollment_id
JOIN public.profiles p ON p.profile_id = e.student_id AND p.email = 'student1@pnc.test'
JOIN public.sections sec ON sec.section_id = ei.section_id
JOIN public.subjects s ON s.subject_id = sec.subject_id
JOIN (VALUES ('CS101', '1.75'), ('CS102', '2.00'), ('GE101', '1.50')) AS v(subject, grade) ON v.subject = s.code
CROSS JOIN (SELECT profile_id FROM public.profiles WHERE email = 'registrar@pnc.test') reg;

-- 13. Charges and payments (Cashier)
INSERT INTO public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
SELECT p.profile_id, t.term_id, ft.fee_type_id, 15000, DATE '2026-10-15', v.status
FROM (VALUES
  ('student1@pnc.test', 'Cleared'),
  ('student2@pnc.test', 'Unpaid'),
  ('student3@pnc.test', 'Unpaid')
) AS v(email, status)
JOIN public.profiles p ON p.email = v.email
CROSS JOIN (SELECT term_id FROM public.terms WHERE is_current LIMIT 1) t
CROSS JOIN (SELECT fee_type_id FROM public.fee_types WHERE name = 'Tuition') ft;

INSERT INTO public.payments (charge_id, amount_paid, paid_at, receipt_number, recorded_by)
SELECT c.charge_id, v.amount, v.paid_at::timestamptz, v.receipt, cash.profile_id
FROM (VALUES
  ('student1@pnc.test', 15000, '2026-09-20', 'OR-0001'),
  ('student3@pnc.test',  5000, '2026-09-21', 'OR-0002')
) AS v(email, amount, paid_at, receipt)
JOIN public.profiles p ON p.email = v.email
JOIN public.charges c ON c.student_id = p.profile_id
CROSS JOIN (SELECT profile_id FROM public.profiles WHERE email = 'cashier@pnc.test') cash;

-- 14. Clearances: one item per office; cleared_at / cleared_by set when cleared
INSERT INTO public.clearances (student_id, term_id, created_at)
SELECT p.profile_id, t.term_id, v.created::timestamptz
FROM (VALUES
  ('student1@pnc.test', '2026-09-23'),
  ('student2@pnc.test', '2026-09-23'),
  ('student3@pnc.test', '2026-09-24')
) AS v(email, created)
JOIN public.profiles p ON p.email = v.email
CROSS JOIN (SELECT term_id FROM public.terms WHERE is_current LIMIT 1) t;

-- Cleared offices: Ana = CSH, CBA, CAS (CCS pending); Ben = CBA, CAS; Carla = CBA, CAS, CCS (CSH pending)
INSERT INTO public.clearance_items (clearance_id, department_id, cleared_at, cleared_by)
SELECT cl.clearance_id, d.department_id,
       CASE WHEN v.cleared THEN now() END,
       CASE WHEN v.cleared THEN
         (SELECT profile_id FROM public.profiles WHERE email =
            CASE d.code WHEN 'CSH' THEN 'cashier@pnc.test' WHEN 'CCS' THEN 'dept@pnc.test' ELSE 'admin@pnc.test' END)
       END
FROM (VALUES
  ('student1@pnc.test', 'CSH', true),  ('student1@pnc.test', 'CBA', true),
  ('student1@pnc.test', 'CAS', true),  ('student1@pnc.test', 'CCS', false),
  ('student2@pnc.test', 'CSH', false), ('student2@pnc.test', 'CBA', true),
  ('student2@pnc.test', 'CAS', true),  ('student2@pnc.test', 'CCS', false),
  ('student3@pnc.test', 'CSH', false), ('student3@pnc.test', 'CBA', true),
  ('student3@pnc.test', 'CAS', true),  ('student3@pnc.test', 'CCS', true)
) AS v(email, dept, cleared)
JOIN public.profiles p ON p.email = v.email
JOIN public.clearances cl ON cl.student_id = p.profile_id
JOIN public.departments d ON d.code = v.dept;

-- 15. Academic holds: Ben has an active CCS hold; Carla's was lifted
INSERT INTO public.academic_holds (student_id, department_id, reason, placed_by, placed_at, lifted_by, lifted_at)
SELECT p.profile_id, d.department_id, v.reason, staff.profile_id, v.placed::timestamptz,
       CASE WHEN v.lifted IS NOT NULL THEN staff.profile_id END, v.lifted::timestamptz
FROM (VALUES
  ('student2@pnc.test', 'Missing lab equipment', '2026-09-22', NULL),
  ('student3@pnc.test', 'Advising required',     '2026-09-21', '2026-09-22')
) AS v(email, reason, placed, lifted)
JOIN public.profiles p ON p.email = v.email
CROSS JOIN (SELECT department_id FROM public.departments WHERE code = 'CCS') d
CROSS JOIN (SELECT profile_id FROM public.profiles WHERE email = 'dept@pnc.test') staff;

-- 16. Document requests (ticket numbers come from document_ticket_seq)
INSERT INTO public.document_requests (student_id, document_type_id, purpose, copies, status, requested_at, processed_by, processed_at)
SELECT p.profile_id, dt.document_type_id, v.purpose, v.copies, v.status, v.requested::timestamptz,
       CASE WHEN v.status = 'Ready' THEN reg.profile_id END,
       CASE WHEN v.status = 'Ready' THEN v.requested::timestamptz + interval '1 day' END
FROM (VALUES
  ('student1@pnc.test', 'Official Transcript of Records', 'Scholarship application', 1, 'Processing', '2026-09-24'),
  ('student2@pnc.test', 'Certificate of Grades',          'Job application',         1, 'Pending',    '2026-09-26'),
  ('student3@pnc.test', 'Certificate of Grades',          'Transfer',                2, 'Ready',      '2026-09-25')
) AS v(email, doc, purpose, copies, status, requested)
JOIN public.profiles p ON p.email = v.email
JOIN public.document_types dt ON dt.name = v.doc
CROSS JOIN (SELECT profile_id FROM public.profiles WHERE email = 'registrar@pnc.test') reg;

-- audit_logs and login_attempts are filled by the app and database triggers, not seeded.
