-- ==========================================
-- SEED DATA (Test & Initial Records)
-- ==========================================

-- 1. System Roles
INSERT INTO public.roles (role_id, role_name) VALUES
  (1, 'Admin'),
  (2, 'Registrar'),
  (3, 'Cashier'),
  (4, 'Department'),
  (5, 'Student')
ON CONFLICT (role_id) DO NOTHING;

-- 2. Departments
INSERT INTO public.departments (department_id, code, name, department_type) VALUES
  ('d1000000-0000-0000-0000-000000000001', 'CCS', 'College of Computing Studies', 'Academic'),
  ('d1000000-0000-0000-0000-000000000002', 'CBA', 'College of Business Administration', 'Academic'),
  ('d1000000-0000-0000-0000-000000000003', 'LIB', 'University Library', 'Administrative'),
  ('d1000000-0000-0000-0000-000000000004', 'SFA', 'Student Financial Affairs', 'Administrative')
ON CONFLICT (department_id) DO NOTHING;

-- 3. Academic Programs
INSERT INTO public.programs (program_id, department_id, code, name) VALUES
  ('p1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'BSCS', 'Bachelor of Science in Computer Science'),
  ('p1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'BSIT', 'Bachelor of Science in Information Technology')
ON CONFLICT (program_id) DO NOTHING;

-- 4. Academic Terms
INSERT INTO public.terms (term_id, school_year, semester, start_date, end_date, is_current) VALUES
  ('t1000000-0000-0000-0000-000000000001', '2026-2027', '1st Semester', '2026-08-01', '2026-12-20', true)
ON CONFLICT (term_id) DO NOTHING;

-- 5. Financial Fee Types
INSERT INTO public.fee_types (fee_type_id, code, name, description) VALUES
  ('f1000000-0000-0000-0000-000000000001', 'TUIT', 'Tuition Fee', 'Standard semester tuition charge'),
  ('f1000000-0000-0000-0000-000000000002', 'LAB', 'Laboratory Fee', 'Computer laboratory usage fee')
ON CONFLICT (fee_type_id) DO NOTHING;

-- 6. Document Types
INSERT INTO public.document_types (document_type_id, code, name) VALUES
  ('dt000000-0000-0000-0000-000000000001', 'TOR', 'Official Transcript of Records'),
  ('dt000000-0000-0000-0000-000000000002', 'COG', 'Certificate of Grades')
ON CONFLICT (document_type_id) DO NOTHING;

-- 7. User Profiles
-- IMPORTANT: Replace the UUID strings below with the exact user UUIDs generated in Supabase Auth (auth.users.id).
INSERT INTO public.profiles (profile_id, role_id, first_name, last_name, email, is_active) VALUES
  ('fc0c2dd0-4437-4465-b149-a06496f73f7c', 1, 'System', 'Admin', 'admin@pnc.test', true),
  ('00000000-0000-0000-0000-000000000002', 2, 'Registrar', 'Officer', 'registrar@pnc.test', true),
  ('00000000-0000-0000-0000-000000000003', 3, 'Cashier', 'Officer', 'cashier@pnc.test', true),
  ('00000000-0000-0000-0000-000000000004', 4, 'Dept', 'Head', 'dept@pnc.test', true),
  ('00000000-0000-0000-0000-000000000005', 5, 'Student One', 'Cruz', 'student1@pnc.test', true),
  ('00000000-0000-0000-0000-000000000006', 5, 'Student Two', 'Santos', 'student2@pnc.test', true)
ON CONFLICT (profile_id) DO NOTHING;

-- 8. Student Specific Details
INSERT INTO public.students (student_id, student_number, program_id) VALUES
  ('00000000-0000-0000-0000-000000000005', '2024-00001', 'p1000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000006', '2024-00002', 'p1000000-0000-0000-0000-000000000001')
ON CONFLICT (student_id) DO NOTHING;