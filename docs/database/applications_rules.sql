-- ==========================================
-- ENROLLMENT SITE FOR NEW APPLICANTS: DATABASE SIDE (feature/enrollment-site)
-- ==========================================
-- A public enrollment site: a NEW applicant (no account yet) submits an application without
-- signing in; the Registrar accepts or rejects it; on Accept the app (server side, with the
-- server-only key, "the server role") creates the Auth account, the profiles row and the
-- students row, links them to the application and emails the student number and a
-- set-password link. This file is the DATABASE side only. Runs AFTER hardening2.sql (A, B,
-- C), login_lockout.sql and enrollment_rules.sql (independent of them; keep README order).
--
-- WHAT IT DOES
--   1. Table public.applications (RLS on, audited by private.audit_log('application_id')):
--        application_id bigint identity PK
--        first_name varchar(100) NOT NULL, last_name varchar(100) NOT NULL
--        email varchar(254) NOT NULL          stored lower(btrim(...))
--        mobile varchar(20) NULL
--        program_id bigint NOT NULL           FK programs
--        status varchar NOT NULL DEFAULT 'Pending'   CHECK Pending | Accepted | Rejected
--        submitted_at timestamptz NOT NULL DEFAULT now()  (always set by the database)
--        reviewed_by uuid NULL                FK profiles (set by the database)
--        reviewed_at timestamptz NULL         (set by the database)
--        remarks varchar(300) NULL            required to Reject
--        student_id uuid NULL                 UNIQUE, FK students (set once, by provisioning)
--        provisioned_at timestamptz NULL      (set by the database when student_id is set)
--      CHECK constraints (named ck_applications_*), a partial unique index "one open
--      (Pending or Accepted) application per email", two plain indexes.
--   2. Callable functions in schema public (SECURITY DEFINER, owner postgres, search_path ''):
--        public.list_programs() RETURNS TABLE(program_id bigint, code text, name text)
--          EXECUTE: anon, authenticated. anon has NO privilege on public.programs itself.
--        public.submit_application(p_first_name text, p_last_name text, p_email text,
--                                  p_mobile text, p_program_id bigint) RETURNS void
--          EXECUTE: anon, authenticated.
--        public.next_student_number() RETURNS text   ('YYYY-NNNN')
--          EXECUTE: NOT PUBLIC, NOT anon, NOT authenticated (only the server role, through
--          Supabase's default privileges; its name is kept out of this repo).
--   3. Internal helpers in schema private (SECURITY INVOKER, no EXECUTE for PUBLIC, anon,
--      authenticated): private.application_settings() (the limits, in ONE place),
--      private.application_name(text, text), private.application_email(text),
--      private.application_mobile(text) (validate + normalise, raise 22023).
--   4. BEFORE INSERT OR UPDATE trigger require_application_rules on public.applications
--      (function private.require_application_rules(), SECURITY INVOKER): the status flow,
--      reviewer / time set by the database, the one-time provisioning link.
--   5. Sequence public.student_number_seq (no privileges for PUBLIC, anon, authenticated),
--      positioned after the highest student number already in public.students.
--   6. Grants: applications: anon nothing; authenticated SELECT + UPDATE (status, remarks)
--      only (no INSERT, no DELETE). Policies: applications_registrar_read (SELECT) and
--      applications_registrar_review (UPDATE), both Registrar only. Nobody else reads.
--      programs: anon loses any privilege it may still have (idempotent).
--
-- HOW THE APP USES IT (the contract)
--   Public site (anon key, no session):
--     rpc('list_programs')                 -> [{program_id, code, name}, ...] ordered by code
--     rpc('submit_application', { p_first_name, p_last_name, p_email, p_mobile, p_program_id })
--       -> null on success. ALWAYS show the same "application received" message on success,
--          also when the database silently skipped a duplicate (see decision 4).
--       p_mobile has no default: send null when empty.
--   Registrar screen (signed-in Registrar):
--     from('applications').select(...)    every row (policy); nobody else sees any row
--     from('applications').update({ status: 'Accepted' | 'Rejected', remarks })
--       .eq('application_id', id)          reviewed_by / reviewed_at are set by the database
--       (do NOT send them: no column grant -> 42501 permission denied)
--   Server side, server role (after Accepted, once):
--     n = rpc('next_student_number')       -> '2026-0004' style text
--     create the Auth user (email = applications.email), insert profiles (role Student, the
--     SAME email) and students (student_number n, the SAME program_id), then
--     from('applications').update({ student_id: <the new user id> }).eq('application_id', id)
--       -> provisioned_at is set by the database (any sent value is replaced).
--     Then send the email. If any step fails, delete what was created and leave the
--     application Accepted and unlinked; the step can be retried.
--   Errors the app must handle (PostgREST: code = SQLSTATE, message = text):
--     22023 (HTTP 400)  "invalid application: <field> ..."   field = first_name, last_name,
--                       email, mobile or program_id; safe to show to the applicant
--     P0001 (HTTP 400)  "try later: ..."      the hourly flood valve (decision 6); show a
--                       generic "the site is busy, try again later"
--     P0001 (HTTP 400)  "remarks required: ..."   Reject without remarks (Registrar)
--     P0001 (HTTP 400)  "bad decision: ..."   any other refused change (not Pending ->
--                       Accepted/Rejected, final row, applicant data changed, reviewer
--                       missing, wrong provisioning link)
--     42501             permission denied (a column without grant; anon / non-server role
--                       calling next_student_number)
--     23505             only on a race the advisory lock cannot see (should not happen)
--
-- DESIGN DECISIONS
--   1. Schema public for the callable functions (PostgREST exposes public only); the logic
--      that is not meant to be called lives in schema private. SECURITY DEFINER, owner
--      postgres (owner of the tables, no FORCE RLS; safety check (e)), search_path '' and
--      every name schema-qualified: anon writes and reads through these doors only.
--   2. Input validation (private.application_*; limits in private.application_settings()):
--        names: btrim, runs of spaces collapsed; 1..100 characters; no control character;
--          letters (ASCII and Latin accented letters, e.g. n with tilde), spaces, hyphen,
--          apostrophe (' and the typographic one), period; must start with a letter.
--        email: btrim + lower; 1..254 characters; no control character; local part 1..64
--          of [a-z0-9._%+'-] without leading / trailing / double dots; domain labels of
--          [a-z0-9-] not starting or ending with '-'; top-level domain 2..63 letters.
--        mobile: NULL, empty or blank -> NULL; else 7..20 characters, optional leading '+',
--          digits, spaces, dashes, at least 7 digits, starts and ends with a digit.
--        program: must exist in public.programs.
--      Each check raises SQLSTATE 22023 "invalid application: <field> ...". Lengths are
--      checked BEFORE the regular expressions. The checks run before anything that looks
--      at existing data, so an error never depends on who has applied.
--   3. One open application per email: partial unique index uq_applications_open_email
--      (email) WHERE status IN ('Pending', 'Accepted'). After a Rejection the person may
--      apply again (a new row), within the per-email cap (decision 5).
--   4. No enumeration. submit_application returns the SAME empty success, and inserts
--      nothing, when the email (normalised) already has a Pending or Accepted application,
--      already exists in public.profiles or auth.users, or reached the per-email cap. The
--      applicant is told "received; you will get an email"; a real duplicate gets no new
--      email. All of that runs under a per-email transaction advisory lock
--      (pg_advisory_xact_lock(hashtextextended('applications:' || email, 0))), so two
--      concurrent submissions of one email cannot both insert.
--   5. Abuse caps: max 3 applications per email in 365 days (all statuses; the 4th is
--      silently skipped, decision 4).
--   6. Flood valve: when 200 or more applications were submitted in the last hour (all
--      emails), every further submission fails with P0001 "try later:" until the hour
--      rolls over. Checked BEFORE the duplicate checks, so the answer is the same for
--      every email. This protects the table and the Registrar's queue from a script that
--      calls the public RPC directly with the public anon key (it bypasses any Vercel rate
--      limit). Cost: a flood blocks real applicants for up to an hour (R1). PM decision.
--   7. Status flow (trigger, every role): INSERT must be Pending (else "bad decision:");
--      on INSERT the database sets submitted_at = now(), clears reviewed_*, remarks,
--      student_id, provisioned_at, normalises email and trims the names.
--      UPDATE of a Pending row: only to Accepted or Rejected (Pending -> Pending, another
--      value, or a provisioning link -> "bad decision:"); Rejected needs non-blank remarks
--      ("remarks required:"); the database sets reviewed_at = now() and reviewed_by =
--      auth.uid() (owner / server role without a JWT: the reviewed_by given in the UPDATE
--      is kept and must not be NULL, else "bad decision: reviewer required").
--      Accepted and Rejected are FINAL for status, remarks, reviewed_by, reviewed_at; the
--      applicant's data (names, email, mobile, program, submitted_at) never changes
--      after INSERT. A correction is a reviewed change by the table owner (ALTER TABLE
--      public.applications DISABLE TRIGGER require_application_rules; fix; ENABLE TRIGGER).
--   8. Provisioning link (the only change allowed on a final row, once, any caller that
--      has the column privilege: the server role or the owner; the Registrar has none):
--      student_id NULL -> value on an ACCEPTED row, nothing else changed. The linked
--      student must exist, its profile must have role Student, its profile email
--      (normalised) must equal the application email and its program_id must equal the
--      application's program_id (else "bad decision:"). The database sets provisioned_at =
--      now(). Once linked, every further UPDATE of the row is refused. The server role
--      bypasses RLS, but this trigger still fires for it.
--   9. reviewed_by / reviewed_at are not in the Registrar's grant (UPDATE (status, remarks)
--      only): the database sets them (the BEFORE trigger fires before RLS WITH CHECK, so the
--      policy sees the database's values).
--  10. next_student_number(): year = now() in Asia/Manila (the school's calendar year, not
--      UTC), number = nextval(public.student_number_seq) padded to 4 digits (more digits
--      after 9999, never truncated); a number already in students.student_number is
--      skipped (up to 1000 tries). The counter is global (not reset each year), so the
--      number part only grows. Sequence numbers are never reused: a failed provisioning
--      leaves a gap (normal for sequences). SECURITY DEFINER so it reads students and uses
--      the sequence without granting either to anyone.
--  11. Audit: AFTER INSERT OR UPDATE OR DELETE trigger audit_log (private.audit_log,
--      hardening2.sql B). actor_id = the Registrar for decisions, NULL for anon submissions
--      and server-role provisioning (no user JWT). The audit rows contain the applicant's
--      personal data (whole row); see RETENTION.
--  12. Grants are rebuilt on applications (REVOKE ALL, then GRANT): Supabase gives new
--      tables, sequences and functions in public full default rights for anon and
--      authenticated; they are removed here. The server role keeps its default rights
--      (bypasses RLS; needs SELECT/UPDATE on applications and EXECUTE on
--      next_student_number), never named or granted in this repo.
--
-- RESIDUAL RISKS (honest list; not solved here)
--   R1 Flood / DoS: anyone with the public anon key can submit up to 200 junk applications
--      per hour (distinct emails), and doing so blocks real applicants until the hour rolls
--      over (decision 6). Mitigation: issue #91 rate limiting in front of the site, CAPTCHA
--      on the form (app side), the Registrar rejects junk; maintenance (m3) deletes junk.
--   R2 Timing: a skipped duplicate is a little faster than a real insert (no INSERT, no
--      audit row). Measurable only statistically over many requests; accepted.
--   R3 Email ownership is not verified at submission; the set-password link sent after
--      acceptance goes to the given address, so an impostor gains nothing unless they
--      control that mailbox. Someone can apply in another person's name; the Registrar
--      reviews.
--   R4 The audit log keeps the applicant's data (append-only); the retention purge below
--      must include the audit rows.
--
-- RETENTION (Data Privacy Act of 2012: proportionality, retention only as long as needed)
--   Proposed (PM to confirm): an application that did NOT become a student (Rejected,
--   Accepted but never linked, or Pending and never reviewed) is kept 12 months after its
--   decision (or after submission when never reviewed): one admission cycle plus time for
--   questions and appeals. Then delete it AND its audit rows (maintenance (m1)). Linked
--   applications (student_id set) are part of the student's admission record and follow
--   the student-record retention. Nothing deletes automatically; run (m1) by hand each
--   term, or later with pg_cron (a separate decision).
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (IF NOT EXISTS, CREATE OR REPLACE, DROP ... IF EXISTS, grants
-- rebuilt; a "WARNING: no privileges could be revoked" is harmless). The sequence is only
-- ever moved forward.
--   - Before running: run diagnostics (a), (b), (c) and (e) at the bottom and SAVE the
--     output; READ (a): the live CHECK / UNIQUE constraints on profiles, students and
--     programs (the live database has constraints that are not in schema.sql).
--   - Rehearse first: docs/database/applications_rules_rehearsal.sql runs this change and
--     all tests (TC-123 to TC-135) in ONE rolled-back transaction with one result row
--     (TC-123R).
-- Test afterwards: docs/database/applications_rules_test.sql (TC-123 to TC-135, the same as
-- the test part of the rehearsal), then docs/database/regression_after_grants.sql.
-- NOTE: login_lockout_test.sql TC-81 expects anon to execute ONLY the two lockout functions;
-- after this file anon also executes list_programs() and submit_application(...), so TC-81's
-- expected list must be updated (TC-134 here checks the new list).
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: NOT RUN YET (written 2026-10-12 without a local PostgreSQL; rehearse first).


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad    text;
  v_ok     boolean;
  v_expr   text;
  v_sample text;
  r        record;
  v_fn     regprocedure := pg_catalog.to_regprocedure('private.require_application_rules()');
BEGIN
  IF current_setting('server_version_num')::int < 170000 THEN
    RAISE EXCEPTION 'applications_rules: PostgreSQL 17+ expected (REVOKE ALL includes MAINTAIN); found %', current_setting('server_version');
  END IF;

  -- a) Tables, schema private, the helpers this file calls, auth.users / auth.uid().
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('programs'), ('profiles'), ('students'), ('roles'), ('audit_logs')) AS e(t)
  WHERE pg_catalog.to_regclass('public.' || e.t) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: missing table(s) public.%; stop', v_bad;
  END IF;
  IF pg_catalog.to_regnamespace('private') IS NULL
     OR pg_catalog.to_regprocedure('private.audit_log()') IS NULL
     OR pg_catalog.to_regprocedure('private.current_role_name()') IS NULL THEN
    RAISE EXCEPTION 'applications_rules: schema private, private.audit_log() or private.current_role_name() is missing; stop';
  END IF;
  IF pg_catalog.to_regclass('auth.users') IS NULL
     OR NOT pg_catalog.has_table_privilege(current_user, 'auth.users', 'SELECT')
     OR pg_catalog.to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION 'applications_rules: % cannot read auth.users or auth.uid() is missing; stop', current_user;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles r2 WHERE r2.role_name = 'Registrar')
     OR NOT EXISTS (SELECT 1 FROM public.roles r2 WHERE r2.role_name = 'Student') THEN
    RAISE EXCEPTION 'applications_rules: roles Registrar / Student missing in public.roles; stop';
  END IF;

  -- b) Columns used, with the expected types (format_type with a NULL typmod).
  SELECT string_agg(e.t || '.' || e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('programs', 'program_id', 'bigint'),
    ('programs', 'code', 'character varying'),
    ('programs', 'name', 'character varying'),
    ('profiles', 'profile_id', 'uuid'),
    ('profiles', 'role_id', 'smallint'),
    ('profiles', 'email', 'character varying'),
    ('students', 'student_id', 'uuid'),
    ('students', 'student_number', 'character varying'),
    ('students', 'program_id', 'bigint')) AS e(t, col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.t)
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: missing column or other type: %; stop', v_bad;
  END IF;

  -- c) Re-run: if public.applications already exists it must have exactly the contract's
  --    columns and types, and no BEFORE trigger other than this file's.
  IF pg_catalog.to_regclass('public.applications') IS NOT NULL THEN
    WITH expected(col, typ) AS (VALUES
      ('application_id', 'bigint'), ('first_name', 'character varying'),
      ('last_name', 'character varying'), ('email', 'character varying'),
      ('mobile', 'character varying'), ('program_id', 'bigint'),
      ('status', 'character varying'), ('submitted_at', 'timestamp with time zone'),
      ('reviewed_by', 'uuid'), ('reviewed_at', 'timestamp with time zone'),
      ('remarks', 'character varying'), ('student_id', 'uuid'),
      ('provisioned_at', 'timestamp with time zone')),
    live AS (
      SELECT a.attname::text AS col, pg_catalog.format_type(a.atttypid, NULL) AS typ
      FROM pg_catalog.pg_attribute a
      WHERE a.attrelid = 'public.applications'::pg_catalog.regclass AND a.attnum > 0 AND NOT a.attisdropped),
    diff AS (
      (SELECT 'missing ' || col || ' ' || typ AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
      UNION ALL
      (SELECT 'unexpected ' || col || ' ' || typ FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x))
    SELECT string_agg(d, '; ') INTO v_bad FROM diff;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'applications_rules: public.applications exists with other columns: %; stop and review', v_bad;
    END IF;
    SELECT string_agg(t.tgname, ', ') INTO v_bad
    FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid = 'public.applications'::pg_catalog.regclass AND NOT t.tgisinternal
      AND t.tgname NOT IN ('require_application_rules', 'audit_log');
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'applications_rules: unexpected trigger(s) on public.applications: %; stop and review', v_bad;
    END IF;
    SELECT string_agg(p.policyname, ', ') INTO v_bad
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = 'applications'
      AND p.policyname NOT IN ('applications_registrar_read', 'applications_registrar_review');
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'applications_rules: unexpected policy(ies) on public.applications: %; stop and review', v_bad;
    END IF;
  END IF;

  -- d) The sequence name is free or is a sequence; no function with these names and
  --    another signature (an overload would make the PostgREST call ambiguous); a trigger
  --    named require_application_rules calls this file's function only.
  IF pg_catalog.to_regclass('public.student_number_seq') IS NOT NULL
     AND (SELECT c.relkind FROM pg_catalog.pg_class c
          WHERE c.oid = pg_catalog.to_regclass('public.student_number_seq')) <> 'S' THEN
    RAISE EXCEPTION 'applications_rules: public.student_number_seq exists and is not a sequence; stop';
  END IF;
  SELECT string_agg(p.oid::pg_catalog.regprocedure::text, ', ') INTO v_bad
  FROM pg_catalog.pg_proc p
  WHERE ((p.pronamespace = 'public'::pg_catalog.regnamespace
          AND p.proname IN ('list_programs', 'submit_application', 'next_student_number'))
      OR (p.pronamespace = 'private'::pg_catalog.regnamespace
          AND p.proname IN ('application_settings', 'application_name', 'application_email',
                            'application_mobile', 'require_application_rules')))
    AND p.oid NOT IN (SELECT s.o::oid FROM (VALUES
          (pg_catalog.to_regprocedure('public.list_programs()')),
          (pg_catalog.to_regprocedure('public.submit_application(text, text, text, text, bigint)')),
          (pg_catalog.to_regprocedure('public.next_student_number()')),
          (pg_catalog.to_regprocedure('private.application_settings()')),
          (pg_catalog.to_regprocedure('private.application_name(text, text)')),
          (pg_catalog.to_regprocedure('private.application_email(text)')),
          (pg_catalog.to_regprocedure('private.application_mobile(text)')),
          (pg_catalog.to_regprocedure('private.require_application_rules()'))) AS s(o)
        WHERE o IS NOT NULL);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: function(s) with another signature already exist: %; stop and review', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname = 'require_application_rules' AND NOT t.tgisinternal
               AND (v_fn IS NULL OR t.tgfoid <> v_fn)) THEN
    RAISE EXCEPTION 'applications_rules: a different trigger named require_application_rules already exists; stop and review';
  END IF;

  -- e) SECURITY DEFINER only sees every row if its owner (the role running this file)
  --    bypasses RLS on the tables it reads: owner without FORCE RLS, or BYPASSRLS.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.programs'::pg_catalog.regclass, 'public.profiles'::pg_catalog.regclass,
                  'public.students'::pg_catalog.regclass)
    AND NOT (SELECT r2.rolbypassrls FROM pg_catalog.pg_roles r2 WHERE r2.rolname = current_user)
    AND NOT (c.relowner = (SELECT r2.oid FROM pg_catalog.pg_roles r2 WHERE r2.rolname = current_user)
             AND NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: % would not bypass RLS on %; run as the table owner (postgres); stop', current_user, v_bad;
  END IF;

  -- f) The live database has CHECK constraints that are not in schema.sql. Every
  --    single-column CHECK on profiles.email / first_name / last_name and
  --    students.student_number must accept what this feature will write there
  --    (provisioning copies the application's names and email; next_student_number()
  --    issues 'YYYY-NNNN'). Each one is evaluated against a sample value.
  FOR r IN
    SELECT c.conrelid::pg_catalog.regclass::text AS tbl, c.conname::text AS conname,
           pg_catalog.pg_get_constraintdef(c.oid) AS def, a.attname::text AS col
    FROM pg_catalog.pg_constraint c
    JOIN pg_catalog.pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'c' AND pg_catalog.array_length(c.conkey, 1) = 1
      AND ((c.conrelid = 'public.profiles'::pg_catalog.regclass AND a.attname IN ('email', 'first_name', 'last_name'))
        OR (c.conrelid = 'public.students'::pg_catalog.regclass AND a.attname = 'student_number'))
  LOOP
    v_expr := pg_catalog.regexp_replace(r.def, '^CHECK \((.*)\)( NOT VALID)?$', '\1');
    FOREACH v_sample IN ARRAY CASE r.col
        WHEN 'email' THEN ARRAY['juan.delacruz@example.com', 'o''brien+ph@mail.example.org']
        WHEN 'first_name' THEN ARRAY['Juan', 'Ma. Teresa', U&'Ni\00F1o']
        WHEN 'last_name' THEN ARRAY['Dela Cruz', 'O''Brien-Santos', U&'Pe\00F1a']
        ELSE ARRAY[pg_catalog.to_char(pg_catalog.now() AT TIME ZONE 'Asia/Manila', 'YYYY') || '-0004',
                   pg_catalog.to_char(pg_catalog.now() AT TIME ZONE 'Asia/Manila', 'YYYY') || '-0123']
      END
    LOOP
      EXECUTE pg_catalog.format('SELECT (%s) FROM (SELECT %L::character varying AS %I) AS x', v_expr, v_sample, r.col)
        INTO v_ok;
      IF v_ok IS FALSE THEN
        RAISE EXCEPTION 'applications_rules: live constraint %.% (%) rejects the sample value [%] that this feature will write; stop and review (diagnostic (a))',
          r.tbl, r.conname, r.def, v_sample;
      END IF;
    END LOOP;
  END LOOP;
END
$$;

-- ------------------------------------------
-- 2. The table, its constraints and indexes
-- ------------------------------------------
CREATE TABLE IF NOT EXISTS public.applications (
  application_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  first_name character varying(100) NOT NULL,
  last_name character varying(100) NOT NULL,
  email character varying(254) NOT NULL,
  mobile character varying(20),
  program_id bigint NOT NULL,
  status character varying NOT NULL DEFAULT 'Pending'::character varying,
  submitted_at timestamp with time zone NOT NULL DEFAULT now(),
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  remarks character varying(300),
  student_id uuid,
  provisioned_at timestamp with time zone,
  CONSTRAINT applications_pkey PRIMARY KEY (application_id),
  CONSTRAINT fk_applications_program_id FOREIGN KEY (program_id) REFERENCES public.programs(program_id),
  CONSTRAINT fk_applications_reviewed_by FOREIGN KEY (reviewed_by) REFERENCES public.profiles(profile_id),
  CONSTRAINT fk_applications_student_id FOREIGN KEY (student_id) REFERENCES public.students(student_id),
  CONSTRAINT uq_applications_student_id UNIQUE (student_id),
  CONSTRAINT ck_applications_status CHECK (status::text = ANY (ARRAY['Pending'::text, 'Accepted'::text, 'Rejected'::text])),
  CONSTRAINT ck_applications_names CHECK (btrim(first_name::text) <> '' AND btrim(last_name::text) <> ''),
  CONSTRAINT ck_applications_email CHECK (email::text = lower(btrim(email::text)) AND email::text <> ''),
  CONSTRAINT ck_applications_review CHECK (
    (status::text = 'Pending' AND reviewed_by IS NULL AND reviewed_at IS NULL)
    OR (status::text <> 'Pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
  CONSTRAINT ck_applications_rejected_remarks CHECK (
    status::text <> 'Rejected' OR (remarks IS NOT NULL AND btrim(remarks::text) <> '')),
  CONSTRAINT ck_applications_provisioned CHECK (
    (student_id IS NULL) = (provisioned_at IS NULL) AND (student_id IS NULL OR status::text = 'Accepted'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_applications_open_email
  ON public.applications (email) WHERE status::text IN ('Pending', 'Accepted');
CREATE INDEX IF NOT EXISTS applications_email_submitted_at_idx
  ON public.applications (email, submitted_at);
CREATE INDEX IF NOT EXISTS applications_submitted_at_idx
  ON public.applications (submitted_at);

ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------
-- 3. Internal helpers (schema private, SECURITY INVOKER, not callable by API users)
-- ------------------------------------------

-- The limits, in ONE place (header, decisions 2, 5, 6, 10).
CREATE OR REPLACE FUNCTION private.application_settings(
  OUT max_name_length   integer,
  OUT max_email_length  integer,
  OUT min_mobile_length integer,
  OUT max_mobile_length integer,
  OUT max_per_email     integer,
  OUT per_email_window  interval,
  OUT max_per_hour      integer,
  OUT number_time_zone  text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT 100, 254, 7, 20, 3, interval '365 days', 200, 'Asia/Manila'::text
$function$;

-- A first or last name: trimmed, single spaces, 1..100 characters, letters (ASCII and
-- Latin accented), spaces, hyphen, apostrophes, period; starts with a letter.
CREATE OR REPLACE FUNCTION private.application_name(p_value text, p_field text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_max integer;
  v     text;
BEGIN
  SELECT s.max_name_length INTO v_max FROM private.application_settings() s;
  v := pg_catalog.btrim(p_value);
  IF v IS NULL OR v = '' THEN
    RAISE EXCEPTION 'invalid application: % is required', p_field USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.length(v) > v_max THEN
    RAISE EXCEPTION 'invalid application: % is longer than % characters', p_field, v_max USING ERRCODE = '22023';
  END IF;
  IF v ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'invalid application: % contains a control character', p_field USING ERRCODE = '22023';
  END IF;
  v := pg_catalog.regexp_replace(v, ' {2,}', ' ', 'g');
  IF v !~ '^[A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F\u1E00-\u1EFF][A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F\u1E00-\u1EFF .''\u2019-]*$' THEN
    RAISE EXCEPTION 'invalid application: % may contain only letters, spaces, hyphens, apostrophes and periods, and must start with a letter', p_field
      USING ERRCODE = '22023';
  END IF;
  RETURN v;
END
$function$;

-- An email: trimmed, lower case, 1..254 characters, a plausible address shape.
CREATE OR REPLACE FUNCTION private.application_email(p_email text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_max integer;
  v     text;
BEGIN
  SELECT s.max_email_length INTO v_max FROM private.application_settings() s;
  v := pg_catalog.btrim(p_email);
  IF v IS NULL OR v = '' THEN
    RAISE EXCEPTION 'invalid application: email is required' USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.length(v) > v_max THEN
    RAISE EXCEPTION 'invalid application: email is longer than % characters', v_max USING ERRCODE = '22023';
  END IF;
  IF v ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'invalid application: email contains a control character' USING ERRCODE = '22023';
  END IF;
  v := pg_catalog.lower(v);
  IF v !~ '^[a-z0-9_%+''-]+(\.[a-z0-9_%+''-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$'
     OR pg_catalog.length(pg_catalog.split_part(v, '@', 1)) > 64 THEN
    RAISE EXCEPTION 'invalid application: email is not a valid address' USING ERRCODE = '22023';
  END IF;
  RETURN v;
END
$function$;

-- A mobile number: optional (NULL / empty / blank -> NULL); 7..20 characters of digits,
-- spaces and dashes with an optional leading '+', at least 7 digits.
CREATE OR REPLACE FUNCTION private.application_mobile(p_mobile text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  s record;
  v text;
BEGIN
  SELECT * INTO STRICT s FROM private.application_settings();
  v := NULLIF(pg_catalog.btrim(p_mobile), '');
  IF v IS NULL THEN
    RETURN NULL;
  END IF;
  IF v ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'invalid application: mobile contains a control character' USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.length(v) < s.min_mobile_length OR pg_catalog.length(v) > s.max_mobile_length THEN
    RAISE EXCEPTION 'invalid application: mobile must be % to % characters long', s.min_mobile_length, s.max_mobile_length
      USING ERRCODE = '22023';
  END IF;
  IF v !~ '^\+?[0-9]([0-9 -]*[0-9])?$'
     OR pg_catalog.length(pg_catalog.regexp_replace(v, '[^0-9]', '', 'g')) < s.min_mobile_length THEN
    RAISE EXCEPTION 'invalid application: mobile may contain only digits, spaces, dashes and a leading +, with at least % digits', s.min_mobile_length
      USING ERRCODE = '22023';
  END IF;
  RETURN v;
END
$function$;

REVOKE ALL ON FUNCTION private.application_settings() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.application_name(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.application_email(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.application_mobile(text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------
-- 4. Trigger function and triggers on applications
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.require_application_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid     uuid := auth.uid();
  v_email   text;
  v_program bigint;
  v_role    text;
BEGIN
  IF TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW' OR TG_OP NOT IN ('INSERT', 'UPDATE')
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'applications' THEN
    RAISE EXCEPTION 'private.require_application_rules must be a BEFORE INSERT OR UPDATE FOR EACH ROW trigger on public.applications';
  END IF;

  -- INSERT: always Pending; the database sets the time and clears everything else.
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IS DISTINCT FROM 'Pending' THEN
      RAISE EXCEPTION 'bad decision: a new application must be Pending, not %', COALESCE(NEW.status::text, 'NULL')
        USING ERRCODE = 'P0001';
    END IF;
    NEW.first_name     := pg_catalog.btrim(NEW.first_name);
    NEW.last_name      := pg_catalog.btrim(NEW.last_name);
    NEW.email          := pg_catalog.lower(pg_catalog.btrim(NEW.email));
    NEW.submitted_at   := pg_catalog.now();
    NEW.reviewed_by    := NULL;
    NEW.reviewed_at    := NULL;
    NEW.remarks        := NULL;
    NEW.student_id     := NULL;
    NEW.provisioned_at := NULL;
    RETURN NEW;
  END IF;

  -- UPDATE. The applicant's data never changes.
  IF NEW.application_id IS DISTINCT FROM OLD.application_id
     OR NEW.first_name IS DISTINCT FROM OLD.first_name
     OR NEW.last_name IS DISTINCT FROM OLD.last_name
     OR NEW.email IS DISTINCT FROM OLD.email
     OR NEW.mobile IS DISTINCT FROM OLD.mobile
     OR NEW.program_id IS DISTINCT FROM OLD.program_id
     OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at THEN
    RAISE EXCEPTION 'bad decision: the applicant''s data of application % cannot be changed', OLD.application_id
      USING ERRCODE = 'P0001',
            HINT = 'Only status and remarks change (the decision), then the one-time account link.';
  END IF;

  -- The decision: Pending -> Accepted | Rejected.
  IF OLD.status::text = 'Pending' THEN
    IF NEW.student_id IS NOT NULL OR NEW.provisioned_at IS NOT NULL THEN
      RAISE EXCEPTION 'bad decision: application % must be Accepted before an account is linked', OLD.application_id
        USING ERRCODE = 'P0001';
    END IF;
    IF NEW.status IS NULL OR NEW.status::text NOT IN ('Accepted', 'Rejected') THEN
      RAISE EXCEPTION 'bad decision: application % is Pending and can only become Accepted or Rejected, not %',
        OLD.application_id, COALESCE(NEW.status::text, 'NULL')
        USING ERRCODE = 'P0001';
    END IF;
    NEW.remarks := NULLIF(pg_catalog.btrim(NEW.remarks), '');
    IF NEW.status::text = 'Rejected' AND NEW.remarks IS NULL THEN
      RAISE EXCEPTION 'remarks required: application % cannot be rejected without remarks', OLD.application_id
        USING ERRCODE = 'P0001',
              HINT = 'Tell the applicant why (up to 300 characters).';
    END IF;
    NEW.reviewed_at := pg_catalog.now();
    IF v_uid IS NOT NULL THEN
      NEW.reviewed_by := v_uid;
    END IF;
    IF NEW.reviewed_by IS NULL THEN
      RAISE EXCEPTION 'bad decision: reviewer required: application % cannot be set to % without a reviewer', OLD.application_id, NEW.status
        USING ERRCODE = 'P0001',
              HINT = 'Sign in as the Registrar, or (owner only) set reviewed_by in the same UPDATE.';
    END IF;
    RETURN NEW;
  END IF;

  -- Accepted / Rejected are final for the decision columns.
  IF NEW.status IS DISTINCT FROM OLD.status
     OR NEW.remarks IS DISTINCT FROM OLD.remarks
     OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
     OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at THEN
    RAISE EXCEPTION 'bad decision: application % is % and final', OLD.application_id, OLD.status
      USING ERRCODE = 'P0001',
            HINT = 'Accepted and Rejected are final. A correction needs a reviewed change by the table owner.';
  END IF;

  -- The only change left: the one-time account link of an Accepted application.
  IF OLD.student_id IS NOT NULL THEN
    RAISE EXCEPTION 'bad decision: application % is already linked to an account', OLD.application_id
      USING ERRCODE = 'P0001';
  END IF;
  IF NEW.student_id IS NULL THEN
    RAISE EXCEPTION 'bad decision: application % is % and final; only the one-time account link (student_id) is allowed', OLD.application_id, OLD.status
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.status::text <> 'Accepted' THEN
    RAISE EXCEPTION 'bad decision: application % is %; only an Accepted application can be linked to an account', OLD.application_id, OLD.status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT pg_catalog.lower(pg_catalog.btrim(p.email::text)), s.program_id, r.role_name::text
    INTO v_email, v_program, v_role
  FROM public.students s
  JOIN public.profiles p ON p.profile_id = s.student_id
  JOIN public.roles r ON r.role_id = p.role_id
  WHERE s.student_id = NEW.student_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'bad decision: student % does not exist; create the profiles and students rows first', NEW.student_id
      USING ERRCODE = 'P0001';
  END IF;
  IF v_role IS DISTINCT FROM 'Student' OR v_email IS DISTINCT FROM OLD.email::text
     OR v_program IS DISTINCT FROM OLD.program_id THEN
    RAISE EXCEPTION 'bad decision: student % does not match application % (role Student, same email and same program required)', NEW.student_id, OLD.application_id
      USING ERRCODE = 'P0001';
  END IF;

  NEW.provisioned_at := pg_catalog.now();
  RETURN NEW;
END
$function$;

REVOKE EXECUTE ON FUNCTION private.require_application_rules() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.require_application_rules() TO authenticated;

-- Firing order: require_application_rules (BEFORE) -> RLS WITH CHECK -> CHECK / unique ->
-- write -> audit_log (AFTER). A refused change writes no audit row.
DROP TRIGGER IF EXISTS require_application_rules ON public.applications;
CREATE TRIGGER require_application_rules BEFORE INSERT OR UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION private.require_application_rules();

DROP TRIGGER IF EXISTS audit_log ON public.applications;
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE OR DELETE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION private.audit_log('application_id');

-- ------------------------------------------
-- 5. Student number sequence (positioned after the highest existing number)
-- ------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.student_number_seq AS bigint MINVALUE 1 START WITH 1 NO CYCLE;

-- Highest numeric part of the existing 'YYYY-NNNN' numbers (any year); at least 3, so the
-- first number issued is NNNN = 0004 or higher. Never moves the sequence backwards.
DO $$
DECLARE
  v_max    bigint;
  v_last   bigint;
  v_called boolean;
BEGIN
  SELECT COALESCE(pg_catalog.max(pg_catalog.substring(s.student_number::text, '^[0-9]{4}-([0-9]{1,15})$')::bigint), 0)
    INTO v_max
  FROM public.students s;
  SELECT q.last_value, q.is_called INTO v_last, v_called FROM public.student_number_seq q;
  PERFORM pg_catalog.setval('public.student_number_seq',
                            GREATEST(v_max, 3, CASE WHEN v_called THEN v_last ELSE v_last - 1 END), true);
END
$$;

REVOKE ALL ON SEQUENCE public.student_number_seq FROM PUBLIC, anon, authenticated;

-- ------------------------------------------
-- 6. The callable functions (schema public, SECURITY DEFINER)
-- ------------------------------------------

-- Programs for the public form (anon has no privilege on public.programs).
CREATE OR REPLACE FUNCTION public.list_programs()
 RETURNS TABLE(program_id bigint, code text, name text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT p.program_id, p.code::text, p.name::text
  FROM public.programs p
  ORDER BY p.code
$function$;

-- The public application form (header, decisions 2 to 6).
CREATE OR REPLACE FUNCTION public.submit_application(
  p_first_name text,
  p_last_name  text,
  p_email      text,
  p_mobile     text,
  p_program_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  s        record;
  v_first  text := private.application_name(p_first_name, 'first_name');
  v_last   text := private.application_name(p_last_name, 'last_name');
  v_email  text := private.application_email(p_email);
  v_mobile text := private.application_mobile(p_mobile);
BEGIN
  SELECT * INTO STRICT s FROM private.application_settings();

  IF p_program_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.programs p WHERE p.program_id = p_program_id) THEN
    RAISE EXCEPTION 'invalid application: program_id is not an offered program' USING ERRCODE = '22023';
  END IF;

  -- Flood valve: the same answer for every email (decision 6).
  IF (SELECT pg_catalog.count(*) FROM public.applications a
       WHERE a.submitted_at > pg_catalog.now() - interval '1 hour') >= s.max_per_hour THEN
    RAISE EXCEPTION 'try later: the enrollment site received too many applications in the last hour'
      USING ERRCODE = 'P0001';
  END IF;

  -- One submission per email at a time.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('applications:' || v_email, 0));

  -- Duplicate, existing account or cap reached: success without inserting (decision 4).
  IF EXISTS (SELECT 1 FROM public.applications a
              WHERE a.email = v_email AND a.status::text IN ('Pending', 'Accepted'))
     OR EXISTS (SELECT 1 FROM public.profiles p WHERE pg_catalog.lower(pg_catalog.btrim(p.email::text)) = v_email)
     OR EXISTS (SELECT 1 FROM auth.users u WHERE pg_catalog.lower(pg_catalog.btrim(u.email::text)) = v_email)
     OR (SELECT pg_catalog.count(*) FROM public.applications a
          WHERE a.email = v_email AND a.submitted_at > pg_catalog.now() - s.per_email_window) >= s.max_per_email THEN
    RETURN;
  END IF;

  INSERT INTO public.applications (first_name, last_name, email, mobile, program_id)
  VALUES (v_first, v_last, v_email, v_mobile, p_program_id);
END
$function$;

-- 'YYYY-NNNN' for a new student (header, decision 10). Server role only.
CREATE OR REPLACE FUNCTION public.next_student_number()
 RETURNS text
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_year text;
  v_n    bigint;
  v_num  text;
  i      integer;
BEGIN
  SELECT pg_catalog.to_char(pg_catalog.now() AT TIME ZONE s.number_time_zone, 'YYYY') INTO v_year
  FROM private.application_settings() s;
  FOR i IN 1..1000 LOOP
    v_n := pg_catalog.nextval('public.student_number_seq');
    v_num := v_year || '-' || CASE WHEN v_n < 10000 THEN pg_catalog.lpad(v_n::text, 4, '0') ELSE v_n::text END;
    IF NOT EXISTS (SELECT 1 FROM public.students st WHERE st.student_number::text = v_num) THEN
      RETURN v_num;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'student number: no free number found after 1000 tries' USING ERRCODE = 'P0001';
END
$function$;

REVOKE ALL ON FUNCTION public.list_programs() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_application(text, text, text, text, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.next_student_number() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_programs() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_application(text, text, text, text, bigint) TO anon, authenticated;

-- next_student_number() is for the server side only. The REVOKE above also removed the access that
-- Supabase's default privileges give its server role, so give EXECUTE back to the roles that bypass
-- row security (and are not superusers): the app's server-side admin client runs as one of them.
-- Found by property, not by name (the repo's scrub forbids that name in SQL files). Rehearsal TC-133
-- found that without this the server side cannot issue a student number.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT rolname FROM pg_catalog.pg_roles
            WHERE rolbypassrls AND NOT rolsuper AND rolname <> current_user
  LOOP
    EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION public.next_student_number() TO %I', r.rolname);
  END LOOP;
END
$$;

-- ------------------------------------------
-- 7. Policies and grants on applications (rebuilt from nothing); programs for anon
-- ------------------------------------------
DROP POLICY IF EXISTS applications_registrar_read ON public.applications;
CREATE POLICY applications_registrar_read ON public.applications
  FOR SELECT TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text));

DROP POLICY IF EXISTS applications_registrar_review ON public.applications;
CREATE POLICY applications_registrar_review ON public.applications
  FOR UPDATE TO authenticated
  USING ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text))
  WITH CHECK ((( SELECT private.current_role_name() AS current_role_name) = 'Registrar'::text));

REVOKE ALL ON public.applications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.applications TO authenticated;
GRANT UPDATE (status, remarks) ON public.applications TO authenticated;

DO $$
BEGIN
  EXECUTE pg_catalog.format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC, anon, authenticated',
                            pg_catalog.pg_get_serial_sequence('public.applications', 'application_id'));
END
$$;

REVOKE ALL ON public.programs FROM anon;

-- ------------------------------------------
-- 8. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_bad    text;
  v_max    bigint;
  v_last   bigint;
  v_called boolean;
BEGIN
  -- a) All functions exist.
  SELECT string_agg(e.sig, ', ') INTO v_bad
  FROM (VALUES ('public.list_programs()'), ('public.submit_application(text, text, text, text, bigint)'),
               ('public.next_student_number()'), ('private.application_settings()'),
               ('private.application_name(text, text)'), ('private.application_email(text)'),
               ('private.application_mobile(text)'), ('private.require_application_rules()')) AS e(sig)
  WHERE pg_catalog.to_regprocedure(e.sig) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: function(s) not created: %; rolled back', v_bad;
  END IF;

  -- b) Public functions: SECURITY DEFINER, empty search_path, owned by the running role,
  --    no PUBLIC; list_programs / submit_application executable by anon and authenticated;
  --    next_student_number by neither.
  SELECT string_agg(p.oid::pg_catalog.regprocedure::text, ', ') INTO v_bad
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (pg_catalog.to_regprocedure('public.list_programs()'),
                  pg_catalog.to_regprocedure('public.submit_application(text, text, text, text, bigint)'),
                  pg_catalog.to_regprocedure('public.next_student_number()'))
    AND NOT (p.prosecdef
             AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']
             AND p.proowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
             AND p.proacl IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
             AND pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                 = (p.proname <> 'next_student_number')
             AND pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                 = (p.proname <> 'next_student_number'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: not SECURITY DEFINER / empty search_path / owner / grants as intended: %; rolled back', v_bad;
  END IF;

  -- c) Private helpers and the trigger function: SECURITY INVOKER, empty search_path, no
  --    PUBLIC, no anon; helpers also not authenticated.
  SELECT string_agg(p.oid::pg_catalog.regprocedure::text, ', ') INTO v_bad
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (pg_catalog.to_regprocedure('private.application_settings()'),
                  pg_catalog.to_regprocedure('private.application_name(text, text)'),
                  pg_catalog.to_regprocedure('private.application_email(text)'),
                  pg_catalog.to_regprocedure('private.application_mobile(text)'),
                  pg_catalog.to_regprocedure('private.require_application_rules()'))
    AND NOT (NOT p.prosecdef
             AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']
             AND p.proacl IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
             AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
             AND (p.proname = 'require_application_rules'
                  OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: private function(s) not locked down: %; rolled back', v_bad;
  END IF;

  -- d) Triggers: require_application_rules BEFORE INSERT OR UPDATE ROW (1+2+4+16 = 23),
  --    audit_log AFTER INSERT OR DELETE OR UPDATE ROW (1+4+8+16 = 29), both enabled.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.applications'::pg_catalog.regclass
                   AND t.tgname = 'require_application_rules' AND NOT t.tgisinternal
                   AND t.tgfoid = pg_catalog.to_regprocedure('private.require_application_rules()')
                   AND t.tgtype = 23 AND t.tgenabled = 'O')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.applications'::pg_catalog.regclass
                      AND t.tgname = 'audit_log' AND NOT t.tgisinternal
                      AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()')
                      AND t.tgtype = 29 AND t.tgenabled = 'O') THEN
    RAISE EXCEPTION 'applications_rules: trigger require_application_rules / audit_log missing or not the expected type; rolled back';
  END IF;

  -- e) RLS on; exactly the two Registrar policies.
  SELECT string_agg(p.policyname || ' (' || p.cmd || ')', ', ' ORDER BY p.policyname) INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = 'applications';
  IF v_bad IS DISTINCT FROM 'applications_registrar_read (SELECT), applications_registrar_review (UPDATE)'
     OR NOT (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
             WHERE c.oid = 'public.applications'::pg_catalog.regclass) THEN
    RAISE EXCEPTION 'applications_rules: RLS or policies on applications not as intended ([%]); rolled back', v_bad;
  END IF;

  -- f) Table privileges: anon nothing on applications and programs; authenticated SELECT
  --    and column UPDATE (status, remarks) only.
  IF pg_catalog.has_table_privilege('anon', 'public.applications', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR pg_catalog.has_any_column_privilege('anon', 'public.applications', 'SELECT, INSERT, UPDATE, REFERENCES')
     OR pg_catalog.has_table_privilege('anon', 'public.programs', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR pg_catalog.has_any_column_privilege('anon', 'public.programs', 'SELECT, INSERT, UPDATE, REFERENCES') THEN
    RAISE EXCEPTION 'applications_rules: anon still has a privilege on applications / programs; rolled back';
  END IF;
  IF NOT pg_catalog.has_table_privilege('authenticated', 'public.applications', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.applications', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN') THEN
    RAISE EXCEPTION 'applications_rules: table-level grants of authenticated on applications are not SELECT only; rolled back';
  END IF;
  SELECT string_agg(a.attname || ' ' || x.privilege_type, ', ' ORDER BY a.attname, x.privilege_type) INTO v_bad
  FROM pg_catalog.pg_attribute a
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
  WHERE a.attrelid = 'public.applications'::pg_catalog.regclass AND a.attnum > 0 AND NOT a.attisdropped
    AND a.attacl IS NOT NULL AND x.grantee = 'authenticated'::regrole;
  IF v_bad IS DISTINCT FROM 'remarks UPDATE, status UPDATE' THEN
    RAISE EXCEPTION 'applications_rules: column grants of authenticated on applications are [%], expected remarks UPDATE, status UPDATE; rolled back', v_bad;
  END IF;

  -- g) Sequences: no privilege for anon / authenticated / PUBLIC; student_number_seq after
  --    the highest existing number.
  SELECT string_agg(q.s || ' ' || q.who, ', ') INTO v_bad
  FROM (SELECT seq.s, w.who
        FROM (VALUES ('public.student_number_seq'),
                     (pg_catalog.pg_get_serial_sequence('public.applications', 'application_id'))) AS seq(s)
        CROSS JOIN (VALUES ('anon'), ('authenticated')) AS w(who)
        WHERE pg_catalog.has_sequence_privilege(w.who, seq.s, 'USAGE, SELECT, UPDATE')) q;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'applications_rules: sequence privileges still present: %; rolled back', v_bad;
  END IF;
  SELECT COALESCE(pg_catalog.max(pg_catalog.substring(s.student_number::text, '^[0-9]{4}-([0-9]{1,15})$')::bigint), 0)
    INTO v_max
  FROM public.students s;
  SELECT q.last_value, q.is_called INTO v_last, v_called FROM public.student_number_seq q;
  IF NOT v_called OR v_last < GREATEST(v_max, 3) THEN
    RAISE EXCEPTION 'applications_rules: student_number_seq (last %, called %) is not after the highest student number (%); rolled back', v_last, v_called, v_max;
  END IF;

  -- h) The partial unique index exists as intended.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i
                 WHERE i.indexrelid = pg_catalog.to_regclass('public.uq_applications_open_email')
                   AND i.indrelid = 'public.applications'::pg_catalog.regclass
                   AND i.indisunique AND i.indpred IS NOT NULL) THEN
    RAISE EXCEPTION 'applications_rules: partial unique index uq_applications_open_email missing; rolled back';
  END IF;
END
$$;

-- Ask PostgREST to reload its schema cache (sent when the transaction commits).
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state before this file)
-- ------------------------------------------
-- DESTROYS every application (and the link to provisioned students; the students,
-- profiles and Auth users stay). Export the table first if it holds real data. Remove the
-- enrollment site's RPC calls and the Registrar screen from the app FIRST. Audit rows of
-- applications stay (append-only). The anon REVOKE on programs is not given back (anon
-- had no privilege there after hardening2.sql section C).
--
-- BEGIN;
--
-- DROP TABLE IF EXISTS public.applications;   -- drops its triggers, policies, indexes
-- DROP FUNCTION IF EXISTS public.submit_application(text, text, text, text, bigint);
-- DROP FUNCTION IF EXISTS public.list_programs();
-- DROP FUNCTION IF EXISTS public.next_student_number();
-- DROP FUNCTION IF EXISTS private.require_application_rules();
-- DROP FUNCTION IF EXISTS private.application_mobile(text);
-- DROP FUNCTION IF EXISTS private.application_email(text);
-- DROP FUNCTION IF EXISTS private.application_name(text, text);
-- DROP FUNCTION IF EXISTS private.application_settings();
-- DROP SEQUENCE IF EXISTS public.student_number_seq;
-- NOTIFY pgrst, 'reload schema';
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: every CHECK, UNIQUE, PRIMARY KEY and FOREIGN KEY constraint and every
--    unique index on the tables this feature touches. READ IT: the live database has CHECK
--    constraints that are not in schema.sql; provisioning must satisfy those on profiles
--    and students (safety check (f) tests the single-column ones with sample values).
-- select c.conrelid::regclass as table_name, c.conname, c.contype, pg_get_constraintdef(c.oid) as definition
-- from pg_constraint c
-- where c.conrelid in ('public.profiles'::regclass, 'public.students'::regclass, 'public.programs'::regclass)
--    or c.conrelid = to_regclass('public.applications')
-- union all
-- select i.indrelid::regclass, ic.relname, 'index', pg_get_indexdef(i.indexrelid)
-- from pg_index i join pg_class ic on ic.oid = i.indexrelid
-- where i.indisunique and not i.indisprimary
--   and (i.indrelid in ('public.profiles'::regclass, 'public.students'::regclass, 'public.programs'::regclass)
--        or i.indrelid = to_regclass('public.applications'))
-- order by 1, 3, 2;
--
-- b) BEFORE and AFTER: functions with these names, their properties and grants.
-- select p.oid::regprocedure as function, pg_get_userbyid(p.proowner) as owner,
--        p.prosecdef as security_definer, p.proconfig, p.proacl::text as acl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
-- from pg_proc p
-- where p.proname in ('list_programs', 'submit_application', 'next_student_number', 'application_settings',
--                     'application_name', 'application_email', 'application_mobile', 'require_application_rules')
-- order by 1;
--
-- c) BEFORE and AFTER: privileges on programs, applications and the sequences (relation and
--    column ACLs), RLS flags, policies, triggers.
-- select c.relname, c.relkind, c.relacl::text as acl, c.relrowsecurity, c.relforcerowsecurity,
--        pg_get_userbyid(c.relowner) as owner
-- from pg_class c
-- where c.oid in ('public.programs'::regclass)
--    or c.oid = to_regclass('public.applications') or c.oid = to_regclass('public.student_number_seq')
--    or c.oid = to_regclass(pg_get_serial_sequence('public.applications', 'application_id'));
-- select a.attname, a.attacl::text from pg_attribute a
-- where a.attrelid = to_regclass('public.applications') and a.attacl is not null;
-- select policyname, cmd, roles, qual, with_check from pg_policies
-- where schemaname = 'public' and tablename = 'applications';
-- select t.tgname, t.tgtype, t.tgenabled, t.tgfoid::regprocedure from pg_trigger t
-- where t.tgrelid = to_regclass('public.applications') and not t.tgisinternal order by 1;
--
-- d) AFTER: student numbers and the sequence (the next number issued is last_value + 1).
-- select (select max(student_number) from public.students) as highest_number,
--        (select count(*) from public.students) as students,
--        q.last_value, q.is_called
-- from public.student_number_seq q;
--
-- e) BEFORE and AFTER: functions in schema public that anon can execute (extension members
--    excluded). After: check_login_lockout(text), list_programs(),
--    record_login_attempt(text, boolean, inet), submit_application(text, text, text, text, bigint).
-- select p.oid::regprocedure as function, p.prosecdef as security_definer
-- from pg_proc p
-- where p.pronamespace = 'public'::regnamespace
--   and has_function_privilege('anon', p.oid, 'EXECUTE')
--   and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass
--                   and d.objid = p.oid and d.deptype = 'e')
-- order by 1;
--
-- f) AFTER: the server-side provisioning needs these privileges for the roles that bypass
--    RLS (the role names are printed by the query, not written here). Expected for the
--    server role: every column true.
-- select r.rolname,
--        has_function_privilege(r.oid, 'public.next_student_number()', 'EXECUTE') as next_number,
--        has_table_privilege(r.oid, 'public.applications', 'SELECT') as app_select,
--        has_column_privilege(r.oid, 'public.applications', 'student_id', 'UPDATE') as app_link,
--        has_table_privilege(r.oid, 'public.profiles', 'INSERT') as profiles_insert,
--        has_table_privilege(r.oid, 'public.students', 'INSERT') as students_insert
-- from pg_roles r
-- where r.rolbypassrls and not r.rolsuper and r.rolname <> current_user
-- order by 1;
--
-- g) AFTER: applications per status and the last hour (no personal data).
-- select status, count(*), min(submitted_at), max(submitted_at),
--        count(*) filter (where submitted_at > now() - interval '1 hour') as last_hour,
--        count(*) filter (where student_id is not null) as linked
-- from public.applications group by status order by status;
--
-- h) AFTER: rows that the retention rule (m1) would delete (counts only).
-- select status, count(*) from public.applications
-- where student_id is null and coalesce(reviewed_at, submitted_at) < now() - interval '12 months'
-- group by status;


-- ==========================================
-- MAINTENANCE (these WRITE; run only on purpose, as postgres)
-- ==========================================
-- m1) Retention (header, RETENTION; PM to confirm the 12 months): delete applications that
--     did not become a student, 12 months after their decision (or submission when never
--     reviewed), together with their audit rows (which hold the same personal data). The
--     row delete itself is not audited (it would copy the data into a new audit row).
-- BEGIN;
-- CREATE TEMP TABLE purge_applications ON COMMIT DROP AS
--   SELECT a.application_id FROM public.applications a
--   WHERE a.student_id IS NULL
--     AND coalesce(a.reviewed_at, a.submitted_at) < now() - interval '12 months';
-- ALTER TABLE public.applications DISABLE TRIGGER audit_log;
-- DELETE FROM public.applications a USING purge_applications p WHERE a.application_id = p.application_id;
-- ALTER TABLE public.applications ENABLE TRIGGER audit_log;
-- ALTER TABLE public.audit_logs DISABLE TRIGGER audit_logs_readonly;
-- DELETE FROM public.audit_logs l USING purge_applications p
--   WHERE l.table_name = 'applications' AND l.record_id = p.application_id::text;
-- ALTER TABLE public.audit_logs ENABLE ALWAYS TRIGGER audit_logs_readonly;
-- SELECT count(*) AS purged FROM purge_applications;
-- COMMIT;
--
-- m2) Correct a decided application (owner only, reviewed change): the trigger is off only
--     inside this transaction. Replace the id and the SET list.
-- BEGIN;
-- ALTER TABLE public.applications DISABLE TRIGGER require_application_rules;
-- UPDATE public.applications SET remarks = 'corrected: ...' WHERE application_id = 0;
-- ALTER TABLE public.applications ENABLE TRIGGER require_application_rules;
-- COMMIT;
--
-- m3) Junk after a flood (R1): delete Pending applications submitted in a time window
--     (check the count with a SELECT first; audit rows stay unless purged as in m1).
-- DELETE FROM public.applications
-- WHERE status = 'Pending' AND submitted_at BETWEEN '2026-10-15 10:00+08' AND '2026-10-15 11:00+08';
