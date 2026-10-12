-- ==========================================
-- applications_server_grants.sql
-- Table privileges for the server-side admin client (the enrollment site's account setup)
-- ==========================================
-- Why: the first live run of "Accept application" (2026-10-12) stopped at "read Student role:
-- 42501 permission denied for table roles". hardening2.sql section C left the server role (the
-- Supabase server-side role the app's admin client uses, SUPABASE_ADMIN_KEY) with no
-- SELECT/INSERT/UPDATE/DELETE on tables that are not exposed in the Data API (see the note at the
-- end of hardening2.sql). Account setup needs exactly these, and nothing more:
--   public.roles          SELECT                      (find the Student role id)
--   public.profiles       SELECT, INSERT, DELETE      (email check, the new profile, undo of a half setup)
--   public.students       SELECT, INSERT, DELETE      (student number lookup, the new student, undo)
--   public.applications   SELECT, UPDATE (student_id, provisioned_at)   (link the account, once)
-- This file only ADDS what is missing. profiles and applications are already open to the server role by
-- Supabase's default privileges (found at the first rehearsal: the role already had UPDATE there), so the
-- real gap was public.roles. It does not remove any existing right.
--
-- The role is found by property, not by name (the repo's scrub forbids that name in SQL files):
-- every role that bypasses row security, is not a superuser and is not the current user. The
-- admin client is only handed out after the caller proves the Registrar role (lib/supabase/admin.ts).
--
-- REHEARSAL COPY: identical body, ends in ROLLBACK. The live file is applications_server_grants.sql. Run
-- this file as a whole. Undo: the ROLLBACK block at the end (REVOKE the same privileges).
-- ==========================================

-- 1. Safety checks (stop before changing anything)
DO $$
DECLARE
  n int;
BEGIN
  IF to_regclass('public.applications') IS NULL THEN
    RAISE EXCEPTION 'applications_server_grants: public.applications is missing (run applications_rules.sql first)';
  END IF;
  SELECT count(*) INTO n FROM pg_catalog.pg_roles WHERE rolbypassrls AND NOT rolsuper AND rolname <> current_user;
  IF n = 0 THEN
    RAISE EXCEPTION 'applications_server_grants: no server-side role found (a role that bypasses row security, not a superuser)';
  END IF;
END
$$;

BEGIN;

-- 2. The grants
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT rolname FROM pg_catalog.pg_roles
            WHERE rolbypassrls AND NOT rolsuper AND rolname <> current_user
  LOOP
    EXECUTE pg_catalog.format('GRANT SELECT ON public.roles TO %I', r.rolname);
    EXECUTE pg_catalog.format('GRANT SELECT, INSERT, DELETE ON public.profiles TO %I', r.rolname);
    EXECUTE pg_catalog.format('GRANT SELECT, INSERT, DELETE ON public.students TO %I', r.rolname);
    EXECUTE pg_catalog.format('GRANT SELECT ON public.applications TO %I', r.rolname);
    EXECUTE pg_catalog.format('GRANT UPDATE (student_id, provisioned_at) ON public.applications TO %I', r.rolname);
  END LOOP;
END
$$;

-- 3. Checks after the change (any failure rolls back the whole file)
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT oid, rolname FROM pg_catalog.pg_roles
            WHERE rolbypassrls AND NOT rolsuper AND rolname <> current_user
  LOOP
    IF NOT (has_table_privilege(r.oid, 'public.roles', 'SELECT')
        AND has_table_privilege(r.oid, 'public.profiles', 'SELECT')
        AND has_table_privilege(r.oid, 'public.profiles', 'INSERT')
        AND has_table_privilege(r.oid, 'public.profiles', 'DELETE')
        AND has_table_privilege(r.oid, 'public.students', 'SELECT')
        AND has_table_privilege(r.oid, 'public.students', 'INSERT')
        AND has_table_privilege(r.oid, 'public.students', 'DELETE')
        AND has_table_privilege(r.oid, 'public.applications', 'SELECT')
        AND has_column_privilege(r.oid, 'public.applications', 'student_id', 'UPDATE')
        AND has_column_privilege(r.oid, 'public.applications', 'provisioned_at', 'UPDATE')) THEN
      RAISE EXCEPTION 'applications_server_grants: a needed privilege is missing for a server-side role';
    END IF;
  END LOOP;
END
$$;

-- One result row for the SQL editor (all cells must be true)
SELECT
  bool_and(has_table_privilege(r.oid, 'public.roles', 'SELECT')) AS roles_select,
  bool_and(has_table_privilege(r.oid, 'public.profiles', 'INSERT') AND has_table_privilege(r.oid, 'public.profiles', 'DELETE')) AS profiles_insert_delete,
  bool_and(has_table_privilege(r.oid, 'public.students', 'INSERT') AND has_table_privilege(r.oid, 'public.students', 'DELETE')) AS students_insert_delete,
  bool_and(has_column_privilege(r.oid, 'public.applications', 'student_id', 'UPDATE')) AS applications_link,
  bool_and(has_table_privilege(r.oid, 'public.profiles', 'UPDATE')) AS profiles_update_already_there,
  bool_and(has_column_privilege(r.oid, 'public.applications', 'status', 'UPDATE')) AS applications_status_update_already_there,
  count(*) AS server_roles
FROM pg_catalog.pg_roles r
WHERE r.rolbypassrls AND NOT r.rolsuper AND r.rolname <> current_user;

ROLLBACK;

-- ROLLBACK block (undo; run separately if ever needed):
-- DO $$ DECLARE r record; BEGIN
--   FOR r IN SELECT rolname FROM pg_catalog.pg_roles WHERE rolbypassrls AND NOT rolsuper AND rolname <> current_user LOOP
--     EXECUTE pg_catalog.format('REVOKE SELECT ON public.roles FROM %I', r.rolname);
--     EXECUTE pg_catalog.format('REVOKE SELECT, INSERT, DELETE ON public.profiles FROM %I', r.rolname);
--     EXECUTE pg_catalog.format('REVOKE SELECT, INSERT, DELETE ON public.students FROM %I', r.rolname);
--     EXECUTE pg_catalog.format('REVOKE SELECT, UPDATE (student_id, provisioned_at) ON public.applications FROM %I', r.rolname);
--   END LOOP;
-- END $$;
