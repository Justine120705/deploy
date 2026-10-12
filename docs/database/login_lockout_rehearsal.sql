-- ==========================================
-- REHEARSAL: login_lockout.sql + TC-72 to TC-82 in ONE rolled-back transaction
-- ==========================================
-- GitHub issue #90 (Sprint 4 issue 34, SEC-03). One paste, one run, ONE result row,
-- nothing committed. This is TC-72R.
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file (from
-- "begin;" to "rollback;") and click Run on the whole tab, never a selection. If the
-- script stops with an error, run "rollback;" as its own query and send the error back.
--
-- What it does:
--   1. begin;
--   2. the body of docs/database/login_lockout.sql (everything between its "BEGIN;" and
--      "COMMIT;" lines, copied verbatim: safety checks, functions, grants, index, table
--      privileges, checks after the change, NOTIFY). A "login_lockout: ..." error here
--      means the live state is not what the file assumes: do NOT run the file live.
--      The NOTIFY is discarded by the rollback.
--   3. TC-72 to TC-82 (identical to docs/database/login_lockout_test.sql). Each result is
--      stored with set_config('app.rNN', ...).
--   4. One final row: one cell per case, each ending in "-> OK" or "-> FAIL", plus
--      "all_ok". (Booleans inside the cells may print as t / f.)
--   5. rollback; (functions, index, grant changes and all test data disappear)
--
-- RUNNING ONLY THE TESTS (after the change is live): use login_lockout_test.sql, or copy
-- from the "begin;" line right below the "TESTS START HERE" marker to the end of this file.
-- It ends in rollback, so it changes nothing.
--
-- Status: NOT RUN YET (written 2026-10-12 without a local PostgreSQL).

begin;

-- ==========================================
-- 1. The change (body of login_lockout.sql, verbatim)
-- ==========================================

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
BEGIN
  -- a) The table and its columns exist with the expected types (format_type with a NULL
  --    typmod: "character varying", not "character varying(n)").
  IF pg_catalog.to_regclass('public.login_attempts') IS NULL THEN
    RAISE EXCEPTION 'login_lockout: missing table public.login_attempts; stop';
  END IF;
  SELECT string_agg(e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('attempt_id', 'bigint'),
    ('email', 'character varying'),
    ('ip_address', 'inet'),
    ('was_successful', 'boolean'),
    ('attempted_at', 'timestamp with time zone')) AS e(col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.login_attempts'::pg_catalog.regclass
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'login_lockout: login_attempts column missing or other type: %; stop', v_bad;
  END IF;
  IF pg_catalog.pg_get_serial_sequence('public.login_attempts', 'attempt_id') IS NULL THEN
    RAISE EXCEPTION 'login_lockout: login_attempts.attempt_id is not an identity column; stop';
  END IF;

  -- b) RLS is enabled, and the only policy is the Admin SELECT policy (rls.sql).
  IF NOT (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
          WHERE c.oid = 'public.login_attempts'::pg_catalog.regclass) THEN
    RAISE EXCEPTION 'login_lockout: row level security is not enabled on public.login_attempts; stop';
  END IF;
  SELECT string_agg(p.policyname || ' (' || p.cmd || ')', ', ' ORDER BY p.policyname) INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = 'login_attempts';
  IF v_bad IS DISTINCT FROM 'login_attempts_admin_read (SELECT)' THEN
    RAISE EXCEPTION 'login_lockout: policies on login_attempts are [%], expected only login_attempts_admin_read (SELECT); stop and review', v_bad;
  END IF;

  -- c) SECURITY DEFINER only sees every row if its owner (the role running this file)
  --    bypasses RLS on login_attempts: the table owner without FORCE ROW LEVEL SECURITY,
  --    or a role with BYPASSRLS. It must also read auth.users and call auth.uid().
  IF NOT ((SELECT r.rolbypassrls FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
          OR (SELECT c.relowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
                     AND NOT c.relforcerowsecurity
                FROM pg_catalog.pg_class c WHERE c.oid = 'public.login_attempts'::pg_catalog.regclass)) THEN
    RAISE EXCEPTION 'login_lockout: % would not bypass RLS on login_attempts; run as the table owner (postgres); stop', current_user;
  END IF;
  IF pg_catalog.to_regclass('auth.users') IS NULL
     OR NOT pg_catalog.has_table_privilege(current_user, 'auth.users', 'SELECT')
     OR pg_catalog.to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION 'login_lockout: % cannot read auth.users or auth.uid() is missing; stop', current_user;
  END IF;

  -- d) No triggers on login_attempts (not audited by design; nothing else fires).
  SELECT string_agg(t.tgname, ', ') INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.login_attempts'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'login_lockout: unexpected trigger(s) on login_attempts: %; stop and review', v_bad;
  END IF;

  -- e) Schema private exists; no OTHER function with these names exists (an overload in
  --    public would make the PostgREST call ambiguous). The exact signatures below are
  --    fine on a re-run.
  IF pg_catalog.to_regnamespace('private') IS NULL THEN
    RAISE EXCEPTION 'login_lockout: schema private is missing (private_functions.sql); stop';
  END IF;
  SELECT string_agg(p.oid::pg_catalog.regprocedure::text, ', ') INTO v_bad
  FROM pg_catalog.pg_proc p
  WHERE ((p.pronamespace = 'public'::pg_catalog.regnamespace
          AND p.proname IN ('check_login_lockout', 'record_login_attempt'))
      OR (p.pronamespace = 'private'::pg_catalog.regnamespace
          AND p.proname IN ('login_lockout_settings', 'login_lockout_email', 'login_lockout_state')))
    AND p.oid NOT IN (SELECT s.o::oid FROM (VALUES
          (pg_catalog.to_regprocedure('public.check_login_lockout(text)')),
          (pg_catalog.to_regprocedure('public.record_login_attempt(text, boolean, inet)')),
          (pg_catalog.to_regprocedure('private.login_lockout_settings()')),
          (pg_catalog.to_regprocedure('private.login_lockout_email(text)')),
          (pg_catalog.to_regprocedure('private.login_lockout_state(text)'))) AS s(o)
        WHERE o IS NOT NULL);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'login_lockout: function(s) with another signature already exist: %; stop and review', v_bad;
  END IF;
END
$$;

-- ------------------------------------------
-- 2. Internal helpers (schema private, SECURITY INVOKER, not callable by API users)
-- ------------------------------------------

-- The policy constants, in ONE place (header, POLICY).
CREATE OR REPLACE FUNCTION private.login_lockout_settings(
  OUT failure_threshold integer,
  OUT base_lock_seconds integer,
  OUT max_lock_seconds  integer,
  OUT failure_window    interval,
  OUT max_email_length  integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT 5, 60, 900, interval '24 hours', 254
$function$;

-- Validates and normalises an email; raises 22023 on bad input (header, decision 4).
CREATE OR REPLACE FUNCTION private.login_lockout_email(p_email text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_max   integer;
  v_email text;
BEGIN
  SELECT s.max_email_length INTO v_max FROM private.login_lockout_settings() s;
  v_email := pg_catalog.btrim(p_email);
  IF v_email IS NULL OR v_email = '' THEN
    RAISE EXCEPTION 'login lockout: email is required' USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.length(v_email) > v_max THEN
    RAISE EXCEPTION 'login lockout: email is longer than % characters', v_max USING ERRCODE = '22023';
  END IF;
  IF v_email ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'login lockout: email contains a control character' USING ERRCODE = '22023';
  END IF;
  RETURN pg_catalog.lower(v_email);
END
$function$;

-- The lock state of one (already normalised) email (header, POLICY). recent_failures is
-- for postgres diagnostics only; the public function does not return it.
CREATE OR REPLACE FUNCTION private.login_lockout_state(
  p_email text,
  OUT locked            boolean,
  OUT seconds_remaining integer,
  OUT recent_failures   integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
  s              record;
  v_last_success bigint;
  v_last_failure timestamptz;
  v_lock_seconds bigint;
  v_unlock_at    timestamptz;
BEGIN
  SELECT * INTO STRICT s FROM private.login_lockout_settings();
  locked := false;
  seconds_remaining := 0;

  SELECT pg_catalog.max(l.attempt_id) INTO v_last_success
  FROM public.login_attempts l
  WHERE pg_catalog.lower(l.email) = p_email AND l.was_successful;

  SELECT pg_catalog.count(*)::integer, pg_catalog.max(l.attempted_at)
    INTO recent_failures, v_last_failure
  FROM public.login_attempts l
  WHERE pg_catalog.lower(l.email) = p_email
    AND NOT l.was_successful
    AND l.attempt_id > COALESCE(v_last_success, 0)
    AND l.attempted_at > pg_catalog.now() - s.failure_window;

  IF recent_failures >= s.failure_threshold THEN
    -- 60 * 2^(n - 5), capped; the shift is capped first so it can never overflow.
    v_lock_seconds := LEAST((s.base_lock_seconds::bigint << LEAST(recent_failures - s.failure_threshold, 30)),
                            s.max_lock_seconds::bigint);
    v_unlock_at := v_last_failure + v_lock_seconds * interval '1 second';
    IF v_unlock_at > pg_catalog.now() THEN
      locked := true;
      seconds_remaining := pg_catalog.ceil(EXTRACT(EPOCH FROM (v_unlock_at - pg_catalog.now())))::integer;
    END IF;
  END IF;
END
$function$;

REVOKE ALL ON FUNCTION private.login_lockout_settings() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.login_lockout_email(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.login_lockout_state(text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------
-- 3. The two callable functions (schema public, SECURITY DEFINER)
-- ------------------------------------------

-- Lockout check, called BEFORE signInWithPassword. Returns only locked + seconds.
CREATE OR REPLACE FUNCTION public.check_login_lockout(
  p_email text,
  OUT locked            boolean,
  OUT seconds_remaining integer)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT s.locked, s.seconds_remaining
  FROM private.login_lockout_state(private.login_lockout_email(p_email)) s
$function$;

-- Records one attempt. Failure: anyone, ignored while locked. Success: only the signed-in
-- user for their own email (header, decisions 5 and 6).
CREATE OR REPLACE FUNCTION public.record_login_attempt(
  p_email   text,
  p_success boolean,
  p_ip      inet DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_email  text := private.login_lockout_email(p_email);
  v_caller text;
BEGIN
  IF p_success IS NULL THEN
    RAISE EXCEPTION 'login lockout: p_success must be true or false' USING ERRCODE = '22023';
  END IF;

  -- Serialise every recording for this email (concurrent calls see each other's rows).
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('login_attempts:' || v_email, 0));

  IF p_success THEN
    SELECT pg_catalog.lower(pg_catalog.btrim(u.email::text)) INTO v_caller
    FROM auth.users u
    WHERE u.id = auth.uid();
    IF v_caller IS NULL OR v_caller <> v_email THEN
      RAISE EXCEPTION 'login lockout: a successful sign-in can only be recorded by the signed-in user for their own email'
        USING ERRCODE = '42501';
    END IF;
  ELSIF (SELECT st.locked FROM private.login_lockout_state(v_email) st) THEN
    RETURN;  -- already locked: not recorded (bounded rows, no faster escalation)
  END IF;

  INSERT INTO public.login_attempts (email, ip_address, was_successful)
  VALUES (v_email, p_ip, p_success);
END
$function$;

REVOKE ALL ON FUNCTION public.check_login_lockout(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_login_attempt(text, boolean, inet) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_login_lockout(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_login_attempt(text, boolean, inet) TO anon, authenticated;

-- ------------------------------------------
-- 4. Index and table privileges
-- ------------------------------------------
CREATE INDEX IF NOT EXISTS login_attempts_email_attempted_at_idx
  ON public.login_attempts (lower(email), attempted_at DESC);

REVOKE ALL ON TABLE public.login_attempts FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON TABLE public.login_attempts FROM authenticated;

DO $$
BEGIN
  EXECUTE pg_catalog.format('REVOKE ALL ON SEQUENCE %s FROM anon, authenticated',
                            pg_catalog.pg_get_serial_sequence('public.login_attempts', 'attempt_id'));
END
$$;

-- Supabase's own event-trigger helper (turns on RLS for new tables) was found
-- executable by anon during the TC-81 rehearsal. It returns event_trigger, so the API
-- cannot call it, but nobody who is not the owner needs it. Event triggers run as
-- their owner, so this does not stop it firing. Guarded: the function is Supabase-managed.
DO $$
BEGIN
  IF pg_catalog.to_regprocedure('public.rls_auto_enable()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;
  END IF;
END
$$;

-- ------------------------------------------
-- 5. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
BEGIN
  -- a) All five functions exist.
  SELECT string_agg(e.sig, ', ') INTO v_bad
  FROM (VALUES ('public.check_login_lockout(text)'), ('public.record_login_attempt(text, boolean, inet)'),
               ('private.login_lockout_settings()'), ('private.login_lockout_email(text)'),
               ('private.login_lockout_state(text)')) AS e(sig)
  WHERE pg_catalog.to_regprocedure(e.sig) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'login_lockout: function(s) not created: %; rolled back', v_bad;
  END IF;

  -- b) The public ones: SECURITY DEFINER, empty search_path, owned by the running role,
  --    no PUBLIC in the ACL, EXECUTE for anon and authenticated.
  SELECT string_agg(p.oid::pg_catalog.regprocedure::text, ', ') INTO v_bad
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (pg_catalog.to_regprocedure('public.check_login_lockout(text)'),
                  pg_catalog.to_regprocedure('public.record_login_attempt(text, boolean, inet)'))
    AND NOT (p.prosecdef
             AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']
             AND p.proowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
             AND p.proacl IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
             AND pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
             AND pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'login_lockout: not SECURITY DEFINER / empty search_path / owner / grants as intended: %; rolled back', v_bad;
  END IF;

  -- c) The private ones: SECURITY INVOKER, empty search_path, no EXECUTE for PUBLIC, anon,
  --    authenticated.
  SELECT string_agg(p.oid::pg_catalog.regprocedure::text, ', ') INTO v_bad
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (pg_catalog.to_regprocedure('private.login_lockout_settings()'),
                  pg_catalog.to_regprocedure('private.login_lockout_email(text)'),
                  pg_catalog.to_regprocedure('private.login_lockout_state(text)'))
    AND NOT (NOT p.prosecdef
             AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']
             AND p.proacl IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
             AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
             AND NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'login_lockout: private helper(s) not locked down: %; rolled back', v_bad;
  END IF;

  -- d) anon has no privilege at all on login_attempts; authenticated cannot write to it.
  SELECT string_agg(e.who || ' ' || e.priv, ', ') INTO v_bad
  FROM (VALUES ('anon', 'SELECT'), ('anon', 'INSERT'), ('anon', 'UPDATE'), ('anon', 'DELETE'),
               ('anon', 'TRUNCATE'), ('anon', 'REFERENCES'), ('anon', 'TRIGGER'),
               ('authenticated', 'INSERT'), ('authenticated', 'UPDATE'), ('authenticated', 'DELETE'),
               ('authenticated', 'TRUNCATE')) AS e(who, priv)
  WHERE pg_catalog.has_table_privilege(e.who, 'public.login_attempts', e.priv);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'login_lockout: table privileges still present: %; rolled back', v_bad;
  END IF;
  IF pg_catalog.has_any_column_privilege('anon', 'public.login_attempts', 'SELECT, INSERT, UPDATE, REFERENCES') THEN
    RAISE EXCEPTION 'login_lockout: anon still has a column privilege on login_attempts; rolled back';
  END IF;

  -- e) The index exists; RLS and the single Admin policy are unchanged.
  IF pg_catalog.to_regclass('public.login_attempts_email_attempted_at_idx') IS NULL THEN
    RAISE EXCEPTION 'login_lockout: index login_attempts_email_attempted_at_idx missing; rolled back';
  END IF;
  SELECT string_agg(p.policyname || ' (' || p.cmd || ')', ', ' ORDER BY p.policyname) INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = 'login_attempts';
  IF v_bad IS DISTINCT FROM 'login_attempts_admin_read (SELECT)'
     OR NOT (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
             WHERE c.oid = 'public.login_attempts'::pg_catalog.regclass) THEN
    RAISE EXCEPTION 'login_lockout: RLS or policies on login_attempts changed ([%]); rolled back', v_bad;
  END IF;
END
$$;

-- Tell PostgREST (the Data API) to reload its schema cache so the new RPCs are visible
-- (delivered at COMMIT; Supabase usually does this by itself).
NOTIFY pgrst, 'reload schema';




-- ==========================================
-- TESTS START HERE (TC-72 to TC-82)
-- ==========================================
-- To run ONLY the tests once login_lockout.sql is live: copy from the next line ("begin;")
-- to the end of this file into a new tab and run that tab as a whole (or paste
-- login_lockout_test.sql). In the full rehearsal the next line is a second BEGIN inside the
-- open transaction; PostgreSQL only answers "WARNING: there is already a transaction in
-- progress" and carries on (nothing is committed either way; the file ends in rollback).
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
        and current_setting('app.t81_list') = 'check_login_lockout(text), list_programs(), record_login_attempt(text, boolean, inet), submit_application(text, text, text, text, bigint)'
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
