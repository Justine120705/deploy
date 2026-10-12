-- ==========================================
-- LOGIN LOCKOUT WITH EXPONENTIAL BACKOFF (GitHub issue #90, Sprint 4 issue 34, SEC-03)
-- ==========================================
-- SRS SEC-03 (docs/documentation.md): account lockout and exponential backoff after
-- repeated failed logins; attempts recorded in public.login_attempts by server-side
-- logic; the lockout check runs BEFORE the credentials are verified.
-- Runs AFTER hardening2.sql section C (anon has no SELECT on public tables) and the
-- clearance changes of Sprint 3 (no dependency on them).
--
-- WHAT IT DOES
--   Two callable functions in schema public, both SECURITY DEFINER (owner postgres),
--   EXECUTE for anon and authenticated only:
--     public.check_login_lockout(p_email text)
--       -> one row (locked boolean, seconds_remaining integer). Nothing else: no count, no
--          "user exists" flag. Read-only.
--     public.record_login_attempt(p_email text, p_success boolean, p_ip inet DEFAULT NULL)
--       -> void. Records one attempt (see decisions 4 to 6 for what is accepted).
--   Three internal helpers in schema private (no EXECUTE for PUBLIC, anon, authenticated;
--   only the two functions above, running as the owner, call them):
--     private.login_lockout_settings()  the policy constants, in ONE place
--     private.login_lockout_email(text) validates and normalises an email
--     private.login_lockout_state(text) computes the lock from public.login_attempts
--   One index: login_attempts_email_attempted_at_idx on (lower(email), attempted_at DESC).
--   Table privileges: anon loses every privilege on public.login_attempts (and its identity
--   sequence); authenticated loses INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--   TRIGGER / MAINTAIN on it. Any SELECT that authenticated has stays (the Admin SELECT
--   policy login_attempts_admin_read is unchanged and still the only policy).
--
-- HOW THE APP USES IT (app/(auth)/login/actions.ts, the login server action; runs as anon
-- until signInWithPassword succeeds; no all-powerful key on Vercel)
--   1. rpc('check_login_lockout', { p_email })      locked -> generic "too many attempts,
--      try again in N minutes" message, and do NOT call signInWithPassword.
--   2. signInWithPassword fails (invalid credentials) -> rpc('record_login_attempt',
--      { p_email, p_success: false, p_ip }) still as anon, then the generic error.
--   3. signInWithPassword succeeds -> the SAME supabase client now carries the user's JWT;
--      rpc('record_login_attempt', { p_email, p_success: true, p_ip }) as authenticated.
--   check_login_lockout returns a single object (OUT parameters), not an array.
--   Errors: SQLSTATE 22023 (invalid_parameter_value, HTTP 400) for bad input, 42501
--   (HTTP 401/403) for a success the caller may not record. Messages start with
--   "login lockout:".
--
-- POLICY (private.login_lockout_settings(); change the numbers only there)
--   failure_threshold  5          failures before the first lock
--   base_lock_seconds  60         first lock: 1 minute
--   max_lock_seconds   900        cap: 15 minutes
--   failure_window     24 hours   failures older than this are forgotten
--   max_email_length   254        longest accepted email (RFC 5321 path limit)
--   n = failures of this email that are (a) newer than the last SUCCESS of this email (by
--   attempt_id, so ties in time cannot reorder them) and (b) inside failure_window.
--   n < 5: open. n >= 5: lock = least(60 * 2^(n - 5), 900) seconds, counted from the
--   LAST counted failure: n = 5 -> 1 min, 6 -> 2, 7 -> 4, 8 -> 8, 9 and more -> 15 (cap).
--   locked = now() < last failure + lock; seconds_remaining = ceil(seconds to unlock),
--   0 when open.
--
-- DESIGN DECISIONS
--   1. Schema public for the two callable functions: the Supabase Data API (PostgREST)
--      exposes schema public only, and supabase-js .rpc() calls public. Schema private is
--      not exposed and anon is not meant to use it; the logic that touches the table
--      lives there and cannot be called by API users at all.
--   2. SECURITY DEFINER, owner postgres (the owner of login_attempts, no FORCE RLS; safety
--      check (c)), SET search_path TO '' and every name schema-qualified. This is what lets
--      anon record and check attempts with NO table privilege and NO RLS policy for anon:
--      the functions are the only door, and they only do the narrow things below. The
--      private helpers are SECURITY INVOKER: even if someone could call them, they would
--      run with the caller's (absent) table rights.
--   3. No user enumeration: the email is never looked up in auth.users or profiles by
--      check_login_lockout or by a failure; a made-up email locks and unlocks exactly like
--      a real one (TC-78). The only lookup in auth.users is for a SUCCESS, and there the
--      caller must already be signed in as that user (decision 5).
--   4. Normalisation and input checks (private.login_lockout_email): lower(btrim(email));
--      NULL, empty or blank -> 22023; longer than 254 characters -> 22023; any control
--      character (newline, tab, NUL-like) -> 22023. Rows are stored normalised; the index
--      and every query use lower(email), so an old non-normalised row still counts.
--      p_success NULL -> 22023.
--   5. A SUCCESS resets the counter, so it must not be forgeable: it is accepted only when
--      the caller is signed in (auth.uid() not NULL) AND auth.users.email of auth.uid()
--      equals the normalised p_email. Otherwise 42501 and nothing is written. So anon
--      cannot record a success at all, and a signed-in user cannot reset someone else's
--      counter (TC-79). A signed-in user CAN reset their own lock (they already have a
--      valid session, so nothing is gained).
--   6. FAILURES from anon cannot be avoided (the app records them before anybody is signed
--      in), so anyone can record a failure for any email. Mitigations:
--        - a failure recorded while the email is ALREADY locked is ignored (not inserted):
--          rows per email are bounded (5, then at most one per expired lock), and an
--          attacker cannot push the backoff up faster than real time (TC-74);
--        - the lock is capped at 15 minutes;
--        - recording takes a per-email transaction advisory lock
--          (pg_advisory_xact_lock(hashtextextended('login_attempts:' || email, 0))), so
--          concurrent calls for one email are serialised and the "ignore while locked"
--          rule holds under concurrency.
--      The residual risk (DoS lockout of a victim) is listed under RESIDUAL RISKS.
--   7. p_ip is stored for the Admin's review only and is NOT used by the policy: it is
--      supplied by the caller (an anon RPC caller can pass anything; behind Vercel the app
--      reads it from a forwarded header). Per-IP limiting belongs to issue #91.
--   8. Grants: REVOKE ALL FROM PUBLIC (and anon, authenticated) first, then GRANT EXECUTE
--      to anon and authenticated on the two public functions only. authenticated also gets
--      check / record because a signed-in browser may still post the login form, and the
--      success call runs as authenticated. Supabase's default privileges also give its
--      server role EXECUTE on new public functions; that role bypasses RLS anyway and is
--      not used by the app, so it is left alone (its name is kept out of this repo).
--   9. Not audited (by design, hardening2.sql section B): login_attempts has no triggers
--      (safety check (d)); high volume, and it is itself a log.
--  10. Index (lower(email), attempted_at DESC): both queries filter on lower(email) and the
--      time window; with retention (below) the table stays small.
--
-- RESIDUAL RISKS (honest list; not solved here)
--   R1 DoS lockout: anyone who knows an email can keep it locked by recording a failure
--      each time the lock expires (at most 15 minutes at a time, continuously). The real
--      user cannot sign in meanwhile (the app does not call signInWithPassword while
--      locked). Inherent to a per-account lockout recorded by an anonymous caller.
--      Mitigation: issue #91 (per-IP rate limit at the Vercel firewall / Upstash in front
--      of the login action and of the Supabase API), the Admin can delete the email's rows
--      (diagnostic (c) / maintenance (m2)).
--   R2 Direct calls to Supabase Auth: the anon key is public, so an attacker can call the
--      Supabase Auth password endpoint directly and never pass through the login action;
--      this lockout then does not apply. Remaining protection: Supabase Auth's own
--      per-IP rate limits (dashboard: Authentication, Rate Limits) and, if enabled, CAPTCHA
--      (Authentication, Attack Protection). Closing it fully needs a Supabase Auth hook
--      (password verification attempt hook, paid plans) that calls the same logic.
--   R3 Check-then-sign-in race: N parallel login requests can all pass the check before
--      any failure is recorded, so a burst can exceed 5 guesses before the first lock.
--      Bounded by the app's concurrency; mitigated by #91.
--   R4 The lock state of any email is visible to anyone (locked yes/no and seconds). It
--      does not reveal whether the account exists (decision 3).
--   R5 Table growth: random emails each add up to 5 rows (plus one per expired lock).
--      Mitigated by #91 and the retention cleanup (maintenance (m1)).
--   R6 p_ip is untrusted (decision 7).
--
-- RETENTION
--   Nothing deletes old rows automatically. Recommended: keep 30 days (the policy only
--   reads 24 hours; the Admin reads the rest), delete older rows as postgres with
--   maintenance (m1) at the bottom, by hand or later with pg_cron (a separate decision).
--
-- How to run: Supabase SQL editor, as postgres (the owner of the table). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (CREATE OR REPLACE, IF NOT EXISTS, idempotent grants; a
-- "WARNING: no privileges could be revoked" is harmless). CREATE INDEX takes a short lock
-- on login_attempts (a tiny table).
--   - Before running: run diagnostics (a), (b) and (e) at the bottom and SAVE the output.
--   - Rehearse first: docs/database/login_lockout_rehearsal.sql runs this change and all
--     tests (TC-72 to TC-82) in ONE rolled-back transaction with one result row (TC-72R).
-- Test afterwards: docs/database/login_lockout_test.sql (TC-72 to TC-82, the same test
-- part as the rehearsal, rolled back), then docs/database/regression_after_grants.sql.
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: NOT RUN YET (written 2026-10-12 without a local PostgreSQL; rehearse first).


BEGIN;

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

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state before this file)
-- ------------------------------------------
-- Drops the five functions and the index. The table privileges revoked in section 4 are
-- NOT given back (anon and authenticated must not write login_attempts directly; compare
-- with the saved diagnostic (a) if a restore is ever really needed). Recorded rows stay;
-- delete them separately if wanted (maintenance (m1)). Remove the RPC calls from the app
-- FIRST, otherwise every login fails.
--
-- BEGIN;
--
-- DROP FUNCTION IF EXISTS public.record_login_attempt(text, boolean, inet);
-- DROP FUNCTION IF EXISTS public.check_login_lockout(text);
-- DROP FUNCTION IF EXISTS private.login_lockout_state(text);
-- DROP FUNCTION IF EXISTS private.login_lockout_email(text);
-- DROP FUNCTION IF EXISTS private.login_lockout_settings();
-- DROP INDEX IF EXISTS public.login_attempts_email_attempted_at_idx;
-- NOTIFY pgrst, 'reload schema';
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: privileges on login_attempts and its sequence (relation ACL and
--    column ACLs), RLS flags and policies. After: no anon entry; authenticated at most r.
-- select c.relname, c.relkind, c.relacl::text as acl, c.relrowsecurity, c.relforcerowsecurity,
--        pg_get_userbyid(c.relowner) as owner
-- from pg_class c
-- where c.oid in ('public.login_attempts'::regclass,
--                 pg_get_serial_sequence('public.login_attempts', 'attempt_id')::regclass);
-- select a.attname, a.attacl::text from pg_attribute a
-- where a.attrelid = 'public.login_attempts'::regclass and a.attacl is not null;
-- select policyname, cmd, roles, qual from pg_policies
-- where schemaname = 'public' and tablename = 'login_attempts';
--
-- b) BEFORE and AFTER: functions with these names, their properties and grants.
-- select p.oid::regprocedure as function, pg_get_userbyid(p.proowner) as owner,
--        p.prosecdef as security_definer, p.provolatile, p.proconfig, p.proacl::text as acl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
-- from pg_proc p
-- where p.proname in ('check_login_lockout', 'record_login_attempt', 'login_lockout_settings',
--                     'login_lockout_email', 'login_lockout_state')
-- order by 1;
--
-- c) AFTER: emails with failures in the last 24 hours and their lock state (as postgres;
--    contains email addresses, do not paste into public places).
-- select x.email, st.recent_failures, st.locked, st.seconds_remaining, x.last_attempt
-- from (select lower(email) as email, max(attempted_at) as last_attempt
--       from public.login_attempts
--       where attempted_at > now() - interval '24 hours'
--       group by lower(email)) x
-- cross join lateral private.login_lockout_state(x.email) st
-- order by st.locked desc, st.recent_failures desc, x.email;
--
-- d) AFTER: table size and age (for the retention decision).
-- select count(*) as rows, min(attempted_at) as oldest, max(attempted_at) as newest,
--        count(distinct lower(email)) as emails,
--        pg_size_pretty(pg_total_relation_size('public.login_attempts')) as size
-- from public.login_attempts;
--
-- e) BEFORE and AFTER: functions in schema public that anon can execute (extension
--    members excluded). After: exactly check_login_lockout(text) and
--    record_login_attempt(text, boolean, inet).
-- select p.oid::regprocedure as function, p.prosecdef as security_definer
-- from pg_proc p
-- where p.pronamespace = 'public'::regnamespace
--   and has_function_privilege('anon', p.oid, 'EXECUTE')
--   and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass
--                   and d.objid = p.oid and d.deptype = 'e')
-- order by 1;


-- ==========================================
-- MAINTENANCE (these WRITE; run only on purpose, as postgres)
-- ==========================================
-- m1) Retention: delete attempts older than 30 days.
-- delete from public.login_attempts where attempted_at < now() - interval '30 days';
--
-- m2) Unlock one email at once (for example after a DoS lockout, R1): delete its recent
--     failures. Replace the address; it is matched normalised.
-- delete from public.login_attempts
-- where lower(email) = lower(btrim('someone@pnc.test')) and not was_successful
--   and attempted_at > now() - interval '24 hours';
