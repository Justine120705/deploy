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
-- REHEARSAL COPY: this change plus TC-136 to TC-138 in ONE rolled-back transaction. The live file is student_id_login.sql.
-- Undo: the ROLLBACK block at the end (drop the function; the app then falls back to <id>@students.pnc.test).
-- ==========================================

DO $$
BEGIN
  IF to_regclass('public.students') IS NULL OR to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'student_id_login: public.students or auth.users is missing';
  END IF;
END
$$;

begin;

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


-- ROLLBACK block (undo; run separately if ever needed):
-- DROP FUNCTION IF EXISTS public.login_email_for_student_id(text);

-- ==========================================
-- TESTS START HERE
-- ==========================================
-- ==========================================
-- TESTS TC-136 to TC-138 for student_id_login.sql
-- ==========================================
-- TC-136 a known ID returns the email of that account (with or without the hyphen, spaces trimmed)
-- TC-137 an unknown ID returns the internal <id>@students.pnc.test; input that is not an ID returns NULL
-- TC-138 anon and authenticated can call it; it is SECURITY DEFINER with an empty search_path
-- Run AFTER student_id_login.sql is live (or use student_id_login_rehearsal.sql). One rolled-back
-- transaction, one result row (all_ok plus one cell per case ending in -> OK or -> FAIL).
select set_config('request.jwt.claims', '', true);

do $$
declare
  a1 text; a2 text; a3 text;
  u1 text; u2 text; u3 text; u4 text; u5 text; u6 text; u7 text; u8 text;
  c136 text; c137 text; c138 text;
  ok136 boolean; ok137 boolean; ok138 boolean;
  an text; au text;
begin
  a1 := public.login_email_for_student_id('2026-0001');
  a2 := public.login_email_for_student_id('20260001');
  a3 := public.login_email_for_student_id('  2026-0002 ');
  ok136 := a1 = 'student1@pnc.test' and a2 = 'student1@pnc.test' and a3 = 'student2@pnc.test';
  c136 := format('2026-0001 [%s], 20260001 [%s], " 2026-0002 " [%s] -> %s', a1, a2, a3, case when ok136 then 'OK' else 'FAIL' end);

  u1 := public.login_email_for_student_id('2026-9999');
  u2 := public.login_email_for_student_id('20269999');
  u3 := public.login_email_for_student_id('abc');
  u4 := public.login_email_for_student_id('');
  u5 := public.login_email_for_student_id(null);
  u6 := public.login_email_for_student_id('2026-00');
  u7 := public.login_email_for_student_id('student1@pnc.test');
  u8 := public.login_email_for_student_id('2026-0001; drop table x');
  ok137 := u1 = '2026-9999@students.pnc.test' and u2 = '2026-9999@students.pnc.test'
           and u3 is null and u4 is null and u5 is null and u6 is null and u7 is null and u8 is null;
  c137 := format('unknown [%s], unknown no hyphen [%s], abc [%s], empty [%s], null [%s], short [%s], email [%s], injection [%s] -> %s',
                 u1, u2, coalesce(u3, 'NULL'), coalesce(u4, 'NULL'), coalesce(u5, 'NULL'), coalesce(u6, 'NULL'),
                 coalesce(u7, 'NULL'), coalesce(u8, 'NULL'), case when ok137 then 'OK' else 'FAIL' end);

  set local role anon;
  an := public.login_email_for_student_id('20260001');
  reset role;
  set local role authenticated;
  au := public.login_email_for_student_id('20260001');
  reset role;
  ok138 := an = 'student1@pnc.test' and au = 'student1@pnc.test'
           and (select p.prosecdef and p.proconfig @> array['search_path=""']
                  from pg_proc p where p.oid = 'public.login_email_for_student_id(text)'::regprocedure)
           and has_function_privilege('anon', 'public.login_email_for_student_id(text)', 'EXECUTE');
  c138 := format('anon [%s], authenticated [%s], definer + empty search_path checked -> %s', an, au, case when ok138 then 'OK' else 'FAIL' end);

  perform set_config('app.c136', c136, true);
  perform set_config('app.c137', c137, true);
  perform set_config('app.c138', c138, true);
  perform set_config('app.ok', (ok136 and ok137 and ok138)::text, true);
end $$;

select current_setting('app.ok')::boolean as all_ok,
       current_setting('app.c136') as tc136,
       current_setting('app.c137') as tc137,
       current_setting('app.c138') as tc138;
rollback;
