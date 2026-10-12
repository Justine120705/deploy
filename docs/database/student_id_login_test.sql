-- ==========================================
-- TESTS TC-136 to TC-138 for student_id_login.sql
-- ==========================================
-- TC-136 a known ID returns the email of that account (with or without the hyphen, spaces trimmed)
-- TC-137 an unknown ID returns the internal <id>@students.pnc.test; input that is not an ID returns NULL
-- TC-138 anon and authenticated can call it; it is SECURITY DEFINER with an empty search_path
-- Run AFTER student_id_login.sql is live (or use student_id_login_rehearsal.sql). One rolled-back
-- transaction, one result row (all_ok plus one cell per case ending in -> OK or -> FAIL).
begin;
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
