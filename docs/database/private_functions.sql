-- ==========================================
-- HELPER FUNCTIONS USED BY THE RLS POLICIES (schema "private")
-- ==========================================
-- Run AFTER seed.sql and BEFORE rls.sql.
--
-- Exported from the live Supabase database on 2026-10-10 with
-- pg_get_functiondef(p.oid) for every function in schema private. Bodies are verbatim.
--
-- They are SECURITY DEFINER so the policies can look up the caller's role and
-- department without exposing profiles or department_staff to every user.
-- private.create_clearance_items() is a trigger function; the trigger that calls it
-- was not exported (see README.md).

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.active_uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT p.profile_id FROM public.profiles p WHERE p.profile_id = auth.uid() AND p.is_active
$function$;

CREATE OR REPLACE FUNCTION private.clearance_in_my_department(cid bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.clearance_items ci
                 WHERE ci.clearance_id = cid AND ci.department_id = private.my_department_id())
$function$;

CREATE OR REPLACE FUNCTION private.create_clearance_items()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.clearance_items (clearance_id, department_id)
  SELECT NEW.clearance_id, d.department_id FROM public.departments d;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION private.current_role_name()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT r.role_name
  FROM public.profiles p JOIN public.roles r ON r.role_id = p.role_id
  WHERE p.profile_id = auth.uid() AND p.is_active
$function$;

CREATE OR REPLACE FUNCTION private.my_department_id()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT CASE private.current_role_name()
    WHEN 'Department' THEN (SELECT ds.department_id FROM public.department_staff ds WHERE ds.profile_id = auth.uid())
    WHEN 'Cashier'    THEN (SELECT d.department_id FROM public.departments d WHERE d.department_type = 'Financial' LIMIT 1)
  END
$function$;

CREATE OR REPLACE FUNCTION private.student_in_my_department(sid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.clearance_items ci JOIN public.clearances c ON c.clearance_id = ci.clearance_id
    WHERE c.student_id = sid AND ci.department_id = private.my_department_id())
$function$;

-- Grants not exported, verify against the live database. The previous draft of this
-- file had:
--   GRANT USAGE ON SCHEMA private TO authenticated;
--   GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA private TO authenticated;
