-- ==========================================
-- HELPER FUNCTIONS USED BY THE RLS POLICIES (schema "private")
-- ==========================================
-- Run AFTER seed.sql and BEFORE rls.sql.
--
-- DRAFT RECONSTRUCTION: the policies in rls.sql call these five functions, but the
-- original definitions only exist in Supabase. These versions follow the documented
-- behaviour (SECURITY DEFINER, search_path = '', active accounts only). Compare them
-- with the live definitions (export query in docs/database/README.md, "Known gaps")
-- and replace this file with the exported text if they differ.
--
-- They are SECURITY DEFINER so the policies can look up the caller's role and
-- department without exposing profiles or department_staff to every user.

CREATE SCHEMA IF NOT EXISTS private;

-- The signed-in user's id, or NULL when signed out or the profile is deactivated.
CREATE OR REPLACE FUNCTION private.active_uid() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT p.profile_id FROM public.profiles p
  WHERE p.profile_id = auth.uid() AND p.is_active
$$;

-- The signed-in user's role name ('Student', 'Registrar', 'Cashier', 'Department', 'Admin').
CREATE OR REPLACE FUNCTION private.current_role_name() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT r.role_name::text
  FROM public.profiles p JOIN public.roles r ON r.role_id = p.role_id
  WHERE p.profile_id = auth.uid() AND p.is_active
$$;

-- The department of a Department or Cashier user (department_staff).
CREATE OR REPLACE FUNCTION private.my_department_id() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT ds.department_id FROM public.department_staff ds
  WHERE ds.profile_id = (SELECT private.active_uid())
$$;

-- True when the student has a clearance item in the caller's department.
CREATE OR REPLACE FUNCTION private.student_in_my_department(sid uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clearances c
    JOIN public.clearance_items ci ON ci.clearance_id = c.clearance_id
    WHERE c.student_id = sid AND ci.department_id = private.my_department_id()
  )
$$;

-- True when the clearance has an item in the caller's department.
CREATE OR REPLACE FUNCTION private.clearance_in_my_department(cid bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.clearance_items ci
    WHERE ci.clearance_id = cid AND ci.department_id = private.my_department_id()
  )
$$;

GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA private TO authenticated;
