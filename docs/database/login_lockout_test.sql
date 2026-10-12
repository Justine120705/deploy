-- ==========================================
-- TESTS TC-72 to TC-82 for login_lockout.sql (GitHub issue #90, SEC-03)
-- ==========================================
-- Run AFTER login_lockout.sql is live (or use login_lockout_rehearsal.sql, which runs the
-- change and these tests together, TC-72R). This file is the same as the test part of the
-- rehearsal (from its "TESTS START HERE" marker).
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file and click
-- Run on the whole tab, never a selection. It ends in rollback: nothing is committed (the
-- throwaway attempts, the deleted rows of the test emails, everything). If it stops with
-- an error, run "rollback;" as its own query and send the error back.
--
-- Data: emails under @lockout.test (no such account may exist; checked) plus the seed
-- accounts student1@pnc.test and student2@pnc.test (their existing login_attempts rows are
-- deleted INSIDE the transaction so the counts start at 0; rolled back at the end).
-- The anonymous visitor is simulated with SET LOCAL ROLE anon (no JWT); a signed-in user
-- with SET LOCAL ROLE authenticated + request.jwt.claims (sub = the user's id); backdating
-- is done as postgres. now() is the same for the whole transaction, so every lock below is
-- exact (60 s, 120 s, ...).
-- Policy assumed by the expected values: 5 failures, 60 s doubling, cap 900 s, window
-- 24 hours, 254 characters (TC-72 checks private.login_lockout_settings() first).
--
-- Result: ONE row, one cell per case ending in "-> OK" or "-> FAIL", plus all_ok. Every
-- statement that is expected to fail runs inside a do block with an exception handler, so
-- the transaction is never aborted by an expected error. Booleans inside cells may print
-- as t / f.
--
--   TC-72 installed as intended (settings, definer / invoker, search_path, grants, index,
--         RLS + only the Admin policy, no triggers, no anon table privileges)
--   TC-73 4 failures: open; 5th failure: locked 60 s
--   TC-74 failures while locked are ignored (rows stay 5); lock ends after 60 s
--   TC-75 backoff 60 -> 120 -> 240 -> 480 -> 900 s (cap), cap holds at 29 failures
--   TC-76 failures older than the 24 hour window do not count
--   TC-77 a success by the signed-in owner (case / spaces normalised) resets the counter
--   TC-78 a made-up email behaves exactly like a real account (no enumeration)
--   TC-79 a fake success cannot reset a lock (anon, another user, a JWT of no user)
--   TC-80 anon (and a signed-in student) cannot read or write login_attempts directly
--   TC-81 anon cannot call the private helpers; anon can execute only the two functions
--         in schema public
--   TC-82 input validation (NULL, empty, blank, 255 characters, control character,
--         p_success NULL -> 22023, nothing written; 254 characters accepted)
--
-- Status: NOT RUN YET (written 2026-10-12 without a local PostgreSQL).

begin;

-- ==========================================
-- 1. Accounts, preconditions, clean start (as postgres, no user JWT)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1', coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2', coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.nouser', '00000000-0000-4000-8000-000000000079', true);
do $$
begin
  if pg_catalog.to_regprocedure('public.check_login_lockout(text)') is null
     or pg_catalog.to_regprocedure('public.record_login_attempt(text, boolean, inet)') is null
     or pg_catalog.to_regprocedure('private.login_lockout_state(text)') is null then
    raise exception 'TC setup: login_lockout.sql is not installed (run it, or use login_lockout_rehearsal.sql)';
  end if;
  if current_setting('app.s1') = '' or current_setting('app.s2') = ''
     or exists (select 1 from auth.users where lower(email) like '%@lockout.test')
     or exists (select 1 from auth.users where id::text = current_setting('app.nouser')) then
    raise exception 'TC setup: student1 / student2 missing, or an account under @lockout.test or with id % exists (s1 [%], s2 [%])',
      current_setting('app.nouser'), current_setting('app.s1'), current_setting('app.s2');
  end if;
end $$;
delete from public.login_attempts
where lower(email) like '%@lockout.test' or lower(email) in ('student1@pnc.test', 'student2@pnc.test');

-- ==========================================
-- 2. TC-72: installed as intended (catalog)
-- ==========================================
select set_config('app.r72', (select format('settings [%s], public_ok %s/2, private_ok %s/3, index_ok %s, rls %s, policies [%s], triggers [%s], anon_table_privs [%s], authenticated_write_privs [%s] -> %s',
    x.settings, x.pub_ok, x.priv_ok, x.idx_ok, x.rls, x.pol, x.trg, x.anon_privs, x.auth_privs,
    case when x.settings = '5, 60, 900, 24:00:00, 254' and x.pub_ok = 2 and x.priv_ok = 3 and x.idx_ok and x.rls
          and x.pol = 'login_attempts_admin_read (SELECT)' and x.trg = '' and x.anon_privs = '' and x.auth_privs = ''
         then 'OK' else 'FAIL' end)
  from (select
    (select format('%s, %s, %s, %s, %s', s.failure_threshold, s.base_lock_seconds, s.max_lock_seconds,
                   s.failure_window, s.max_email_length) from private.login_lockout_settings() s) as settings,
    (select count(*) from pg_proc p
      where p.oid in (to_regprocedure('public.check_login_lockout(text)'),
                      to_regprocedure('public.record_login_attempt(text, boolean, inet)'))
        and p.prosecdef and array_to_string(p.proconfig, ',') in ('search_path=""', 'search_path=''''')
        and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
        and has_function_privilege('anon', p.oid, 'EXECUTE')
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')
        and exists (select 1 from pg_roles r join pg_class c on c.oid = 'public.login_attempts'::regclass
                     where r.oid = p.proowner
                       and (r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity)))) as pub_ok,
    (select count(*) from pg_proc p
      where p.oid in (to_regprocedure('private.login_lockout_settings()'),
                      to_regprocedure('private.login_lockout_email(text)'),
                      to_regprocedure('private.login_lockout_state(text)'))
        and not p.prosecdef and array_to_string(p.proconfig, ',') in ('search_path=""', 'search_path=''''')
        and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
        and not has_function_privilege('anon', p.oid, 'EXECUTE')
        and not has_function_privilege('authenticated', p.oid, 'EXECUTE')) as priv_ok,
    coalesce((select pg_get_indexdef(i.indexrelid) like '%(lower((email)::text), attempted_at DESC)%'
                from pg_index i where i.indexrelid = to_regclass('public.login_attempts_email_attempted_at_idx')
                  and i.indrelid = 'public.login_attempts'::regclass), false) as idx_ok,
    (select c.relrowsecurity from pg_class c where c.oid = 'public.login_attempts'::regclass) as rls,
    coalesce((select string_agg(p.policyname || ' (' || p.cmd || ')', ', ' order by p.policyname)
                from pg_policies p where p.schemaname = 'public' and p.tablename = 'login_attempts'), '') as pol,
    coalesce((select string_agg(t.tgname::text, ', ') from pg_trigger t
               where t.tgrelid = 'public.login_attempts'::regclass and not t.tgisinternal), '') as trg,
    coalesce((select string_agg(e.priv, ', ') from (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) as e(priv)
               where has_table_privilege('anon', 'public.login_attempts', e.priv)), '') as anon_privs,
    coalesce((select string_agg(e.priv, ', ') from (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) as e(priv)
               where has_table_privilege('authenticated', 'public.login_attempts', e.priv)), '') as auth_privs) x), true);

-- ==========================================
-- 3. TC-73: 4 failures open, the 5th locks for 60 s
-- ==========================================
set local role anon;
select public.record_login_attempt('tc73@lockout.test', false, '203.0.113.73') from generate_series(1, 4);
select set_config('app.t73_4', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc73@lockout.test') s), true);
select public.record_login_attempt('tc73@lockout.test', false, '203.0.113.73');
select set_config('app.t73_5', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc73@lockout.test') s), true);
reset role;
select set_config('app.r73', format('after 4 failures [%s], after 5 [%s], rows %s -> %s',
  current_setting('app.t73_4'), current_setting('app.t73_5'),
  (select count(*) from public.login_attempts where email = 'tc73@lockout.test' and not was_successful
     and ip_address = '203.0.113.73'::inet),
  case when current_setting('app.t73_4') = 'open 0s' and current_setting('app.t73_5') = 'locked 60s'
        and (select count(*) from public.login_attempts where email = 'tc73@lockout.test' and not was_successful
               and ip_address = '203.0.113.73'::inet) = 5
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 4. TC-74: failures while locked are ignored; the lock ends after 60 s
-- ==========================================
set local role anon;
select public.record_login_attempt('tc74@lockout.test', false) from generate_series(1, 5);
select set_config('app.t74_locked', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc74@lockout.test') s), true);
select public.record_login_attempt('tc74@lockout.test', false) from generate_series(1, 3);
select set_config('app.t74_more', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc74@lockout.test') s), true);
reset role;
select set_config('app.t74_rows', (select count(*)::text from public.login_attempts where email = 'tc74@lockout.test'), true);
update public.login_attempts set attempted_at = attempted_at - interval '59 seconds' where email = 'tc74@lockout.test';
set local role anon;
select set_config('app.t74_59', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc74@lockout.test') s), true);
reset role;
update public.login_attempts set attempted_at = attempted_at - interval '2 seconds' where email = 'tc74@lockout.test';
set local role anon;
select set_config('app.t74_61', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc74@lockout.test') s), true);
reset role;
select set_config('app.r74', format('after 5 [%s], after 3 more [%s], rows %s, 59 s later [%s], 61 s later [%s] -> %s',
  current_setting('app.t74_locked'), current_setting('app.t74_more'), current_setting('app.t74_rows'),
  current_setting('app.t74_59'), current_setting('app.t74_61'),
  case when current_setting('app.t74_locked') = 'locked 60s' and current_setting('app.t74_more') = 'locked 60s'
        and current_setting('app.t74_rows') = '5' and current_setting('app.t74_59') = 'locked 1s'
        and current_setting('app.t74_61') = 'open 0s'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 5. TC-75: exponential backoff 60, 120, 240, 480, 900 (cap)
-- ==========================================
-- After each lock, postgres moves every attempt of the email back by lock + 1 s (the lock
-- has expired), then anon records ONE more failure.
set local role anon;
select public.record_login_attempt('tc75@lockout.test', false) from generate_series(1, 5);
select set_config('app.t75_1', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc75@lockout.test') s), true);
reset role;
update public.login_attempts set attempted_at = attempted_at - interval '61 seconds' where email = 'tc75@lockout.test';
set local role anon;
select public.record_login_attempt('tc75@lockout.test', false);
select set_config('app.t75_2', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc75@lockout.test') s), true);
reset role;
update public.login_attempts set attempted_at = attempted_at - interval '121 seconds' where email = 'tc75@lockout.test';
set local role anon;
select public.record_login_attempt('tc75@lockout.test', false);
select set_config('app.t75_3', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc75@lockout.test') s), true);
reset role;
update public.login_attempts set attempted_at = attempted_at - interval '241 seconds' where email = 'tc75@lockout.test';
set local role anon;
select public.record_login_attempt('tc75@lockout.test', false);
select set_config('app.t75_4', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc75@lockout.test') s), true);
reset role;
update public.login_attempts set attempted_at = attempted_at - interval '481 seconds' where email = 'tc75@lockout.test';
set local role anon;
select public.record_login_attempt('tc75@lockout.test', false);
select set_config('app.t75_5', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc75@lockout.test') s), true);
reset role;
select set_config('app.t75_rows', (select count(*)::text from public.login_attempts where email = 'tc75@lockout.test'), true);
insert into public.login_attempts (email, was_successful)
select 'tc75@lockout.test', false from generate_series(1, 20);
set local role anon;
select set_config('app.t75_cap', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc75@lockout.test') s), true);
reset role;
select set_config('app.r75', format('5 [%s], 6 [%s], 7 [%s], 8 [%s], 9 [%s], rows %s, 29 [%s] -> %s',
  current_setting('app.t75_1'), current_setting('app.t75_2'), current_setting('app.t75_3'),
  current_setting('app.t75_4'), current_setting('app.t75_5'), current_setting('app.t75_rows'),
  current_setting('app.t75_cap'),
  case when current_setting('app.t75_1') = 'locked 60s' and current_setting('app.t75_2') = 'locked 120s'
        and current_setting('app.t75_3') = 'locked 240s' and current_setting('app.t75_4') = 'locked 480s'
        and current_setting('app.t75_5') = 'locked 900s' and current_setting('app.t75_rows') = '9'
        and current_setting('app.t75_cap') = 'locked 900s'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 6. TC-76: failures older than the 24 hour window do not count
-- ==========================================
insert into public.login_attempts (email, was_successful, attempted_at)
select 'tc76@lockout.test', false, now() - interval '25 hours' from generate_series(1, 9);
set local role anon;
select set_config('app.t76_old', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc76@lockout.test') s), true);
select public.record_login_attempt('tc76@lockout.test', false) from generate_series(1, 4);
select set_config('app.t76_4', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc76@lockout.test') s), true);
select public.record_login_attempt('tc76@lockout.test', false);
select set_config('app.t76_5', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('tc76@lockout.test') s), true);
reset role;
select set_config('app.r76', format('9 old failures [%s], +4 new [%s], +5 new [%s] -> %s',
  current_setting('app.t76_old'), current_setting('app.t76_4'), current_setting('app.t76_5'),
  case when current_setting('app.t76_old') = 'open 0s' and current_setting('app.t76_4') = 'open 0s'
        and current_setting('app.t76_5') = 'locked 60s'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 7. TC-77: a success by the signed-in owner resets the counter
-- ==========================================
set local role anon;
select public.record_login_attempt('student1@pnc.test', false) from generate_series(1, 5);
select set_config('app.t77_locked', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('student1@pnc.test') s), true);
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
begin
  perform public.record_login_attempt('  Student1@PNC.test ', true, '203.0.113.77');
  perform set_config('app.t77_success', 'recorded', true);
exception when others then
  perform set_config('app.t77_success', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.t77_after', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('student1@pnc.test') s), true);
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select public.record_login_attempt('student1@pnc.test', false) from generate_series(1, 4);
select set_config('app.t77_4', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('student1@pnc.test') s), true);
select public.record_login_attempt('student1@pnc.test', false);
select set_config('app.t77_5', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('student1@pnc.test') s), true);
reset role;
select set_config('app.r77', format('5 failures [%s], owner success [%s], after success [%s], +4 [%s], +5 [%s], success_rows_normalised %s -> %s',
  current_setting('app.t77_locked'), current_setting('app.t77_success'), current_setting('app.t77_after'),
  current_setting('app.t77_4'), current_setting('app.t77_5'),
  (select count(*) from public.login_attempts where email = 'student1@pnc.test' and was_successful),
  case when current_setting('app.t77_locked') = 'locked 60s' and current_setting('app.t77_success') = 'recorded'
        and current_setting('app.t77_after') = 'open 0s' and current_setting('app.t77_4') = 'open 0s'
        and current_setting('app.t77_5') = 'locked 60s'
        and (select count(*) from public.login_attempts where email = 'student1@pnc.test' and was_successful) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 8. TC-78: a made-up email behaves exactly like a real account
-- ==========================================
set local role anon;
do $$
declare
  e  text;
  s4 text;
  s5 text;
  s6 text;
  fs text;
  i  integer;
begin
  foreach e in array array['tc78-ghost@lockout.test', 'student2@pnc.test'] loop
    for i in 1..4 loop
      perform public.record_login_attempt(e, false);
    end loop;
    select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's' into s4
    from public.check_login_lockout(e) s;
    perform public.record_login_attempt(e, false);
    select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's' into s5
    from public.check_login_lockout(e) s;
    perform public.record_login_attempt(e, false);
    select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's' into s6
    from public.check_login_lockout(e) s;
    begin
      perform public.record_login_attempt(e, true);
      fs := 'ACCEPTED';
    exception when others then
      fs := sqlstate || ' ' || sqlerrm;
    end;
    perform set_config(case when e like '%@lockout.test' then 'app.t78_ghost' else 'app.t78_real' end,
      format('4 [%s], 5 [%s], 6 [%s], fake success [%s]', s4, s5, s6, fs), true);
  end loop;
end $$;
reset role;
select set_config('app.r78', format('made-up [%s], real [%s], rows %s / %s -> %s',
  current_setting('app.t78_ghost'), current_setting('app.t78_real'),
  (select count(*) from public.login_attempts where email = 'tc78-ghost@lockout.test'),
  (select count(*) from public.login_attempts where email = 'student2@pnc.test'),
  case when current_setting('app.t78_ghost') = current_setting('app.t78_real')
        and current_setting('app.t78_ghost') like '4 [open 0s], 5 [locked 60s], 6 [locked 60s], fake success [42501 login lockout:%'
        and (select count(*) from public.login_attempts where email = 'tc78-ghost@lockout.test') = 5
        and (select count(*) from public.login_attempts where email = 'student2@pnc.test') = 5
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 9. TC-79: a fake success cannot reset a lock
-- ==========================================
delete from public.login_attempts where lower(email) = 'student1@pnc.test';
set local role anon;
select public.record_login_attempt('student1@pnc.test', false) from generate_series(1, 5);
do $$
begin
  perform public.record_login_attempt('student1@pnc.test', true);
  perform set_config('app.t79_anon', 'ACCEPTED', true);
exception when others then
  perform set_config('app.t79_anon', sqlstate, true);
end $$;
reset role;
set local role authenticated;
do $$
declare
  r record;
begin
  for r in select * from (values (1, 'other_user', current_setting('app.s2')),
                                 (2, 'no_such_user', current_setting('app.nouser'))) as t(ord, label, sub)
           order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', r.sub, 'role', 'authenticated')::text, true);
    begin
      perform public.record_login_attempt('student1@pnc.test', true);
      perform set_config('app.t79_' || r.label, 'ACCEPTED', true);
    exception when others then
      perform set_config('app.t79_' || r.label, sqlstate, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select set_config('app.t79_after', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout('student1@pnc.test') s), true);
reset role;
select set_config('app.r79', format('anon [%s], other user [%s], JWT of no user [%s], state after [%s], success rows %s -> %s',
  current_setting('app.t79_anon'), current_setting('app.t79_other_user'), current_setting('app.t79_no_such_user'),
  current_setting('app.t79_after'),
  (select count(*) from public.login_attempts where lower(email) = 'student1@pnc.test' and was_successful),
  case when current_setting('app.t79_anon') = '42501' and current_setting('app.t79_other_user') = '42501'
        and current_setting('app.t79_no_such_user') = '42501' and current_setting('app.t79_after') = 'locked 60s'
        and (select count(*) from public.login_attempts where lower(email) = 'student1@pnc.test' and was_successful) = 0
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 10. TC-80: no direct table access for anon (nor writes for a signed-in student)
-- ==========================================
select set_config('app.t80_rows_before', (select count(*)::text from public.login_attempts), true);
set local role anon;
do $$
declare
  r   record;
  n   bigint;
  v_out text := '';
begin
  for r in select * from (values
    (1, 'select',   $q$select * from public.login_attempts$q$),
    (2, 'insert',   $q$insert into public.login_attempts (email, was_successful) values ('tc80@lockout.test', true)$q$),
    (3, 'update',   $q$update public.login_attempts set was_successful = true where email = 'student1@pnc.test'$q$),
    (4, 'delete',   $q$delete from public.login_attempts$q$),
    (5, 'truncate', $q$truncate public.login_attempts$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label || ' ALLOWED rows ' || n;
    exception when others then
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label
             || case when sqlerrm like 'permission denied%' then ' denied' else ' ERROR ' || sqlstate end;
    end;
  end loop;
  perform set_config('app.t80_anon', v_out, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare
  r   record;
  n   bigint;
  v_out text := '';
begin
  for r in select * from (values
    (1, 'select',   $q$select * from public.login_attempts$q$),
    (2, 'insert',   $q$insert into public.login_attempts (email, was_successful) values ('student1@pnc.test', true)$q$),
    (3, 'update',   $q$update public.login_attempts set was_successful = true where email = 'student1@pnc.test'$q$),
    (4, 'delete',   $q$delete from public.login_attempts where email = 'student1@pnc.test'$q$),
    (5, 'truncate', $q$truncate public.login_attempts$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label || ' rows ' || n;
    exception when others then
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label
             || case when sqlerrm like 'permission denied%' then ' denied' else ' ERROR ' || sqlstate end;
    end;
  end loop;
  perform set_config('app.t80_student', v_out, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r80', format('anon [%s], student [%s], rows unchanged %s -> %s',
  current_setting('app.t80_anon'), current_setting('app.t80_student'),
  (select count(*)::text from public.login_attempts) = current_setting('app.t80_rows_before'),
  case when current_setting('app.t80_anon') = 'select denied, insert denied, update denied, delete denied, truncate denied'
        and current_setting('app.t80_student') in ('select denied, insert denied, update denied, delete denied, truncate denied',
                                                   'select rows 0, insert denied, update denied, delete denied, truncate denied')
        and (select count(*)::text from public.login_attempts) = current_setting('app.t80_rows_before')
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 11. TC-81: anon cannot call anything else
-- ==========================================
set local role anon;
do $$
declare
  r   record;
  v_out text := '';
begin
  for r in select * from (values
    (1, 'state',    $q$select private.login_lockout_state('tc81@lockout.test')$q$),
    (2, 'email',    $q$select private.login_lockout_email('tc81@lockout.test')$q$),
    (3, 'settings', $q$select private.login_lockout_settings()$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label || ' ALLOWED';
    exception when others then
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label
             || case when sqlerrm like 'permission denied%' then ' denied' else ' ERROR ' || sqlstate end;
    end;
  end loop;
  perform set_config('app.t81_anon', v_out, true);
end $$;
reset role;
select set_config('app.t81_list', coalesce((select string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')', ', ' order by p.proname)
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and has_function_privilege('anon', p.oid, 'EXECUTE')
    and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass
                    and d.objid = p.oid and d.deptype = 'e')), ''), true);
select set_config('app.r81', format('anon calls [%s], anon-executable in public [%s], authenticated_private_execute %s -> %s',
  current_setting('app.t81_anon'), current_setting('app.t81_list'),
  (select count(*) from pg_proc p
    where p.oid in (to_regprocedure('private.login_lockout_settings()'), to_regprocedure('private.login_lockout_email(text)'),
                    to_regprocedure('private.login_lockout_state(text)'))
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  case when current_setting('app.t81_anon') = 'state denied, email denied, settings denied'
        and current_setting('app.t81_list') = 'check_login_lockout(text), record_login_attempt(text, boolean, inet)'
        and (select count(*) from pg_proc p
              where p.oid in (to_regprocedure('private.login_lockout_settings()'), to_regprocedure('private.login_lockout_email(text)'),
                              to_regprocedure('private.login_lockout_state(text)'))
                and has_function_privilege('authenticated', p.oid, 'EXECUTE')) = 0
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 12. TC-82: input validation
-- ==========================================
select set_config('app.t82_rows_before', (select count(*)::text from public.login_attempts), true);
set local role anon;
do $$
declare
  r   record;
  v_out text := '';
begin
  for r in select * from (values
    (1, 'null',         $q$select public.check_login_lockout(null)$q$),
    (2, 'empty',        $q$select public.check_login_lockout('')$q$),
    (3, 'blank',        $q$select public.check_login_lockout('   ')$q$),
    (4, '255 chars',    $q$select public.check_login_lockout(repeat('a', 242) || '@lockout.test')$q$),
    (5, 'control',      $q$select public.record_login_attempt(e'tc82\n@lockout.test', false)$q$),
    (6, 'record null',  $q$select public.record_login_attempt(null, false)$q$),
    (7, 'record 255',   $q$select public.record_login_attempt(repeat('b', 242) || '@lockout.test', false)$q$),
    (8, 'success null', $q$select public.record_login_attempt('tc82@lockout.test', null)$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label || ' ACCEPTED';
    exception when others then
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label || ' ' || sqlstate;
    end;
  end loop;
  perform set_config('app.t82_bad', v_out, true);
end $$;
select set_config('app.t82_254', (select case when s.locked then 'locked ' else 'open ' end || s.seconds_remaining || 's'
  from public.check_login_lockout(repeat('a', 241) || '@lockout.test') s), true);
select public.record_login_attempt('  TC82-Case@Lockout.TEST ', false);
reset role;
select set_config('app.r82', format('rejected [%s], 254 chars [%s], rows written by bad input %s, stored normalised %s -> %s',
  current_setting('app.t82_bad'), current_setting('app.t82_254'),
  (select count(*) from public.login_attempts) - current_setting('app.t82_rows_before')::bigint - 1,
  (select count(*) from public.login_attempts where email = 'tc82-case@lockout.test'),
  case when current_setting('app.t82_bad') = 'null 22023, empty 22023, blank 22023, 255 chars 22023, control 22023, record null 22023, record 255 22023, success null 22023'
        and current_setting('app.t82_254') = 'open 0s'
        and (select count(*) from public.login_attempts) - current_setting('app.t82_rows_before')::bigint = 1
        and (select count(*) from public.login_attempts where email = 'tc82-case@lockout.test') = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- Result: ONE row
-- ==========================================
select (current_setting('app.r72') like '%-> OK' and current_setting('app.r73') like '%-> OK'
        and current_setting('app.r74') like '%-> OK' and current_setting('app.r75') like '%-> OK'
        and current_setting('app.r76') like '%-> OK' and current_setting('app.r77') like '%-> OK'
        and current_setting('app.r78') like '%-> OK' and current_setting('app.r79') like '%-> OK'
        and current_setting('app.r80') like '%-> OK' and current_setting('app.r81') like '%-> OK'
        and current_setting('app.r82') like '%-> OK') as all_ok,
  current_setting('app.r72') as tc72, current_setting('app.r73') as tc73, current_setting('app.r74') as tc74,
  current_setting('app.r75') as tc75, current_setting('app.r76') as tc76, current_setting('app.r77') as tc77,
  current_setting('app.r78') as tc78, current_setting('app.r79') as tc79, current_setting('app.r80') as tc80,
  current_setting('app.r81') as tc81, current_setting('app.r82') as tc82;

rollback;
