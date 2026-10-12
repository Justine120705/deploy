-- ==========================================
-- student_id_login.sql
-- Sign in with a student ID: public.login_email_for_student_id(text)
-- ==========================================
-- Why: students sign in with their student ID (2026-0001 or 20260001). Supabase Auth needs an email,
-- so the login action asks this function which email the ID signs in with:
--   * a student with an account: the email of that account (the seed students sign in as
--     student1@pnc.test ..., students accepted through the enrollment site as 2026-0004@students.pnc.test);
--   * an ID nobody has: the internal form <id>@students.pnc.test, which no account has, so the
--     sign-in fails with the same generic message as a wrong password (the app does not reveal
--     whether an ID exists);
--   * input that is not a student ID: NULL.
-- The function only returns text. It never returns a password, a hash or any other column.
-- Residual note: anyone who knows the public API key can call it directly and learn the sign-in email
-- of a valid student ID. For students accepted through the enrollment site that email is internal and
-- has no mailbox; for the seed students it is their test email. Real contact emails are never returned
-- (profiles.email is not read).
--
-- Run: rehearse with student_id_login_rehearsal.sql, then this file, then student_id_login_test.sql.
-- Undo: the ROLLBACK block at the end (drop the function; the app then falls back to <id>@students.pnc.test).
-- ==========================================

DO $$
BEGIN
  IF to_regclass('public.students') IS NULL OR to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'student_id_login: public.students or auth.users is missing';
  END IF;
END
$$;

BEGIN;

CREATE OR REPLACE FUNCTION public.login_email_for_student_id(p_student_id text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH n AS (
    SELECT CASE
             WHEN pg_catalog.btrim(p_student_id) ~ '^[0-9]{8,10}$'
               THEN pg_catalog.substr(pg_catalog.btrim(p_student_id), 1, 4) || '-' || pg_catalog.substr(pg_catalog.btrim(p_student_id), 5)
             ELSE pg_catalog.lower(pg_catalog.btrim(p_student_id))
           END AS id
  )
  SELECT CASE
           WHEN n.id !~ '^[0-9]{4}-[0-9]{4,6}$' THEN NULL
           ELSE COALESCE(
                  (SELECT u.email::text
                     FROM public.students st
                     JOIN auth.users u ON u.id = st.student_id
                    WHERE st.student_number::text = n.id
                    LIMIT 1),
                  n.id || '@students.pnc.test')
         END
    FROM n;
$function$;

REVOKE ALL ON FUNCTION public.login_email_for_student_id(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_email_for_student_id(text) TO anon, authenticated;

-- Checks after the change (any failure rolls back the whole file)
DO $$
BEGIN
  IF NOT has_function_privilege('anon', 'public.login_email_for_student_id(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.login_email_for_student_id(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'student_id_login: anon / authenticated cannot execute the function';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'public.login_email_for_student_id(text)'::regprocedure) THEN
    RAISE EXCEPTION 'student_id_login: the function is not SECURITY DEFINER';
  END IF;
END
$$;

COMMIT;

-- ROLLBACK block (undo; run separately if ever needed):
-- DROP FUNCTION IF EXISTS public.login_email_for_student_id(text);
