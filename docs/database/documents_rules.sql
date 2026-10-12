-- ==========================================
-- DOCUMENT REQUESTS: DATABASE RULES AND GRANTS (GitHub issue #93, Sprint 4 issue 37)
-- ==========================================
-- REQ-DOC-01, REQ-DOC-02, REQ-STU-04, REQ-REG-02, SEC-02. Runs AFTER hardening.sql,
-- hardening2.sql (A, B, C), views_extend.sql and grants_clearance.sql (all live).
--
-- WHAT EXISTS ALREADY (not changed here, checked in section 1)
--   - RLS policies on document_requests (rls.sql, verbatim from the live export):
--       docreq_read               SELECT  own rows (student_id = active_uid) or Registrar
--       docreq_student_submit     INSERT  Student only, student_id = self, status 'Pending',
--                                         processed_by and processed_at NULL
--       docreq_registrar_process  UPDATE  Registrar only; WITH CHECK processed_by = self
--     No DELETE policy. document_types: doc_types_read (SELECT, everyone signed in) and
--     doc_types_admin (ALL, Admin; catalog writes are issue #95, not this file).
--   - BEFORE UPDATE trigger guard_immutable_columns('student_id', 'ticket_number')
--     (hardening.sql) and AFTER trigger audit_log (hardening2.sql B) on document_requests.
--   - Grants: authenticated has SELECT only on both tables, anon nothing (hardening2.sql
--     section C, grants_clearance.sql section 3). The grants on document_ticket_seq were
--     never written down (probably Supabase's defaults: anon and authenticated USAGE,
--     SELECT, UPDATE); diagnostic (a) shows them, save it before running.
--
-- WHAT THIS FILE CHANGES
--   1. Grants (authenticated only; RLS still decides the rows):
--        document_requests  SELECT; INSERT (student_id, document_type_id, purpose, copies);
--                           UPDATE (status, remarks); no DELETE, nothing else
--        document_types     SELECT (anon and PUBLIC revoked; other grants of authenticated
--                           are left alone, so a later catalog grant (#95) is not undone)
--        document_ticket_seq  USAGE only (see decision 1); SELECT / UPDATE revoked
--      anon and PUBLIC get nothing on the two tables and the sequence.
--   2. New BEFORE UPDATE trigger require_document_status_flow (function
--      private.require_document_status_flow(), SECURITY INVOKER) enforcing the status flow
--      and setting processed_by / processed_at itself (decisions 3 to 6).
--
-- DESIGN DECISIONS
--   1. Ticket number (REQ-DOC-01). The column DEFAULT builds it:
--        'DR-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('document_ticket_seq')::text, 6, '0')
--      plus UNIQUE on ticket_number. A DEFAULT runs with the rights of the INSERTING role,
--      so the student (authenticated) needs USAGE on the sequence (USAGE allows nextval and
--      currval; UPDATE would also allow setval, SELECT only currval/last_value). Only USAGE
--      is granted. Notes: the number never resets per year (DR-2027-000123 can follow
--      DR-2026-000122); a failed insert still uses up a number (gaps are normal); after
--      999999 the number gets 7 digits (lpad never cuts it). The sequence is not reachable
--      through the Data API (PostgREST does not expose sequences), so USAGE does not let a
--      signed-in user burn numbers from the app.
--   2. The student cannot choose the ticket: ticket_number is NOT in the INSERT column
--      grant, so an INSERT that names it fails with "permission denied" (42501) before any
--      row is written; the same holds for status, requested_at (no back-dating),
--      processed_by and processed_at. On UPDATE ticket_number and student_id stay locked by
--      guard_immutable_columns and are not in the UPDATE grant either. No extra INSERT
--      trigger: a trigger cannot tell a supplied ticket from the default one (both arrive
--      in NEW), and the column grant already refuses it. If someone later toggles the table
--      in the dashboard (full table grants), run this file again (section 2 starts from
--      REVOKE ALL), as for grants_clearance.sql.
--   3. Status flow (REQ-DOC-02), the only changes allowed, one step at a time:
--        Pending -> Processing -> Ready -> Released
--        Pending -> Rejected, Processing -> Rejected
--      Ready -> Rejected is NOT allowed (the document is already produced; PM may decide
--      otherwise: add 'Ready -> Rejected' to the list in the function). No skipping
--      (Pending -> Ready / Released, Processing -> Released), no going back. Released and
--      Rejected are final: neither status NOR remarks can change any more.
--      The rule applies to EVERY role (API users, postgres, the server role), like
--      require_all_items_cleared (issue 24); a deliberate correction needs a reviewed change
--      by the table owner (DISABLE TRIGGER, fix, ENABLE TRIGGER). INSERT is not checked:
--      the student can only insert 'Pending' (no status grant, policy), only the owner can
--      insert another status (seed.sql does).
--   4. processed_by / processed_at are set by the database, never taken from the statement,
--      for every caller with a user JWT (auth.uid() NOT NULL):
--        - status or remarks changed -> processed_by = auth.uid(), processed_at = now()
--        - nothing of those changed  -> both are put back to their OLD values
--      So they cannot be forged even with a broader grant (TC-104 proves it with a
--      temporary grant). A remarks-only edit (allowed on Processing / Ready only; refused on Pending, see the trigger comment) also
--      stamps them: the live policy requires processed_by = the caller on every Registrar
--      UPDATE, so the meaning is "the Registrar who last changed the request, and when".
--      Without a user JWT (postgres / SQL editor) a status change sets processed_at = now()
--      and processed_by is left as written.
--      Side effect: an UPDATE that changes nothing fails the policy WITH CHECK when the row
--      was never processed (processed_by NULL); that is a no-op anyway.
--   5. Error: RAISE EXCEPTION with SQLSTATE 'P0001' and the stable prefix
--      "bad status change:" (same style as "active hold:" and "pending items:"):
--        bad status change: <old> -> <new> is not allowed (request <id>)
--        bad status change: request <id> is <Released|Rejected> (final) and cannot be changed
--      PostgREST returns HTTP 400 with code P0001; the app recognises it by the prefix.
--   6. SECURITY INVOKER, SET search_path TO '': the function reads no table (only OLD, NEW
--      and auth.uid()), so it needs no owner rights. Grants like the other trigger
--      functions: no PUBLIC / anon EXECUTE, explicit EXECUTE for authenticated.
--   7. Firing order on document_requests (BEFORE by name, then RLS WITH CHECK, then the
--      write, then AFTER by name):
--        UPDATE: guard_immutable_columns (BEFORE) -> require_document_status_flow (BEFORE)
--                -> RLS WITH CHECK (processed_by = caller, now true because the trigger set
--                it) -> write -> audit_log (AFTER)
--        INSERT: RLS WITH CHECK -> write -> audit_log (AFTER)
--      A BEFORE trigger fires before RLS WITH CHECK, which is what lets the policy's
--      "processed_by = caller" pass without the Registrar writing processed_by. Rows a role
--      may not update (Student, Cashier, Department, Admin) are filtered by the policy USING
--      before any trigger fires: their UPDATE changes 0 rows, without an error.
--   8. No DELETE for anyone through the API (no grant, no policy). Requests are kept;
--      Rejected is the end state for a request that will not be served.
--
-- KNOWN LIMITS / FOR THE PM
--   - Admin cannot read document_requests (docreq_read: own student or Registrar). Not
--     changed here; add Admin to docreq_read in a separate change if the Admin dashboard
--     needs it.
--   - The server role is not touched (its grants on the table and sequence stay as they
--     are); server-side code with that key bypasses RLS but not this trigger.
--   - No per-student limit on open requests (spam); copies is limited to 1..10 by the
--     table CHECK.
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (CREATE OR REPLACE, DROP TRIGGER IF EXISTS, section 2 starts
-- from REVOKE ALL). Short locks on document_requests, document_types and the sequence.
--   - Before running: run diagnostics (a), (b) and (c) at the bottom and SAVE the output.
--   - Rehearse first: docs/database/documents_rules_rehearsal.sql runs this change and all
--     tests (TC-95 to TC-108) in ONE rolled-back transaction with one result row (TC-95R).
-- Test afterwards: docs/database/documents_rules_test.sql (TC-95 to TC-108, one result
-- row, rolled back), then docs/database/regression_after_grants.sql (TC-12 to TC-33) again.
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: NOT RUN YET (written without a local PostgreSQL; rehearse first).


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
  v_def text;
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.require_document_status_flow()');
BEGIN
  IF current_setting('server_version_num')::int < 170000 THEN
    RAISE EXCEPTION 'documents_rules: PostgreSQL 17+ required (MAINTAIN in the checks); found %', current_setting('server_version');
  END IF;

  -- a) The objects exist with the expected kind; auth.uid() exists.
  SELECT string_agg(e.name, ', ') INTO v_bad
  FROM (VALUES ('document_requests', 'r'), ('document_types', 'r'), ('profiles', 'r'),
               ('audit_logs', 'r'), ('document_ticket_seq', 'S')) AS e(name, kind)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                    WHERE c.relnamespace = 'public'::regnamespace
                      AND c.relname = e.name AND c.relkind::text = e.kind);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: missing or wrong kind in schema public: %; stop', v_bad;
  END IF;
  IF pg_catalog.to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION 'documents_rules: function auth.uid() not found; stop';
  END IF;

  -- b) Columns and types (format_type with a NULL typmod).
  SELECT string_agg(e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('request_id', 'bigint'), ('ticket_number', 'character varying'), ('student_id', 'uuid'),
    ('document_type_id', 'bigint'), ('purpose', 'character varying'), ('copies', 'smallint'),
    ('status', 'character varying'), ('requested_at', 'timestamp with time zone'),
    ('processed_by', 'uuid'), ('processed_at', 'timestamp with time zone'),
    ('remarks', 'character varying')) AS e(col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.document_requests'::pg_catalog.regclass
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: document_requests column missing or other type: %; stop', v_bad;
  END IF;

  -- c) The ticket DEFAULT is the documented one (DR- prefix, year, lpad of nextval of
  --    document_ticket_seq) and ticket_number has a single-column UNIQUE index.
  SELECT pg_catalog.pg_get_expr(d.adbin, d.adrelid) INTO v_def
  FROM pg_catalog.pg_attrdef d
  JOIN pg_catalog.pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
  WHERE d.adrelid = 'public.document_requests'::pg_catalog.regclass AND a.attname = 'ticket_number';
  IF v_def IS NULL
     OR position('''DR-''' IN v_def) = 0
     OR position('''YYYY''' IN v_def) = 0
     OR position('lpad(' IN v_def) = 0
     OR position('nextval(' IN v_def) = 0
     OR position('document_ticket_seq''::regclass' IN v_def) = 0 THEN
    RAISE EXCEPTION 'documents_rules: ticket_number DEFAULT is not the expected one: [%]; stop', v_def;
  END IF;
  IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
      WHERE i.indrelid = 'public.document_requests'::pg_catalog.regclass
        AND i.indisunique AND i.indnatts = 1 AND a.attname = 'ticket_number') THEN
    RAISE EXCEPTION 'documents_rules: no UNIQUE index on document_requests.ticket_number; stop';
  END IF;

  -- d) A CHECK constraint on status lists the 5 statuses the flow uses.
  IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint k
      WHERE k.conrelid = 'public.document_requests'::pg_catalog.regclass AND k.contype = 'c'
        AND position('status' IN pg_catalog.pg_get_constraintdef(k.oid)) > 0
        AND position('''Pending''' IN pg_catalog.pg_get_constraintdef(k.oid)) > 0
        AND position('''Processing''' IN pg_catalog.pg_get_constraintdef(k.oid)) > 0
        AND position('''Ready''' IN pg_catalog.pg_get_constraintdef(k.oid)) > 0
        AND position('''Released''' IN pg_catalog.pg_get_constraintdef(k.oid)) > 0
        AND position('''Rejected''' IN pg_catalog.pg_get_constraintdef(k.oid)) > 0) THEN
    RAISE EXCEPTION 'documents_rules: no CHECK constraint on document_requests.status with the 5 statuses; stop';
  END IF;

  -- e) RLS is enabled on both tables (granting writes without RLS would open them).
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.document_requests'::pg_catalog.regclass, 'public.document_types'::pg_catalog.regclass)
    AND NOT c.relrowsecurity;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: RLS is not enabled on %; stop', v_bad;
  END IF;

  -- f) The policies on document_requests are exactly the 3 reviewed ones, all PERMISSIVE
  --    and TO authenticated, with the conditions this file relies on.
  WITH expected(policyname, cmd) AS (VALUES
    ('docreq_read', 'SELECT'), ('docreq_registrar_process', 'UPDATE'), ('docreq_student_submit', 'INSERT')),
  live AS (
    SELECT p.policyname::text, p.cmd::text FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = 'document_requests'
      AND p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[]),
  diff AS (
    (SELECT 'missing ' || policyname || ' ' || cmd AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || policyname || ' ' || cmd FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x)
    UNION ALL
    (SELECT 'not permissive / not TO authenticated: ' || p.policyname FROM pg_catalog.pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'document_requests'
       AND NOT (p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[])))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: policies on document_requests differ from the reviewed set: %; stop', v_bad;
  END IF;

  SELECT string_agg(p.policyname, ', ') INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = 'document_requests'
    AND NOT CASE p.policyname
      WHEN 'docreq_read' THEN
        position('active_uid' IN coalesce(p.qual, '')) > 0 AND position('''Registrar''' IN coalesce(p.qual, '')) > 0
      WHEN 'docreq_student_submit' THEN
        position('active_uid' IN coalesce(p.with_check, '')) > 0 AND position('''Student''' IN coalesce(p.with_check, '')) > 0
        AND position('''Pending''' IN coalesce(p.with_check, '')) > 0
      WHEN 'docreq_registrar_process' THEN
        position('''Registrar''' IN coalesce(p.qual, '')) > 0 AND position('''Registrar''' IN coalesce(p.with_check, '')) > 0
        AND position('processed_by' IN coalesce(p.with_check, '')) > 0 AND position('active_uid' IN coalesce(p.with_check, '')) > 0
      ELSE false END;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: policy text differs from rls.sql on %; stop and review', v_bad;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
                 WHERE p.schemaname = 'public' AND p.tablename = 'document_types'
                   AND p.policyname = 'doc_types_read' AND p.cmd = 'SELECT'
                   AND p.roles = ARRAY['authenticated']::name[]) THEN
    RAISE EXCEPTION 'documents_rules: policy doc_types_read (SELECT TO authenticated) missing on document_types; stop';
  END IF;

  -- g) The function is absent (first run) or is this file's trigger function (re-run), and
  --    no trigger with this name anywhere calls a different function.
  IF v_fn IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
                          <> 'pg_catalog.trigger'::pg_catalog.regtype THEN
    RAISE EXCEPTION 'documents_rules: private.require_document_status_flow() exists and is not a trigger function; stop and review';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname = 'require_document_status_flow' AND NOT t.tgisinternal
               AND (v_fn IS NULL OR t.tgfoid <> v_fn)) THEN
    RAISE EXCEPTION 'documents_rules: a different trigger named require_document_status_flow already exists; stop and review';
  END IF;

  -- h) The triggers on document_requests are exactly guard_immutable_columns (BEFORE,
  --    hardening.sql) and audit_log (AFTER, hardening2.sql B), both enabled, plus this
  --    file's trigger on a re-run. tgtype bit 2 = BEFORE.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.document_requests'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns' AND (t.tgtype::integer & 2) = 2
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'audit_log' AND (t.tgtype::integer & 2) = 0
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'require_document_status_flow' AND v_fn IS NOT NULL AND t.tgfoid = v_fn));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: unexpected trigger(s) on document_requests: %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('audit_log')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.document_requests'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: trigger(s) missing or disabled on document_requests: %; stop', v_bad;
  END IF;
END
$$;

-- ------------------------------------------
-- 2. Grants (authenticated only; anon and PUBLIC nothing)
-- ------------------------------------------
-- document_requests: start from nothing (REVOKE on a table also removes its column grants),
-- then SELECT back (it had it; docreq_read limits the rows) plus the column writes.
REVOKE ALL ON public.document_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.document_requests TO authenticated;
-- Student submit (docreq_student_submit: Student, own student_id, Pending). Left out on
-- purpose: request_id (identity), ticket_number (DEFAULT, decision 2), status (DEFAULT
-- 'Pending'), requested_at (DEFAULT now(), no back-dating), processed_*, remarks.
GRANT INSERT (student_id, document_type_id, purpose, copies) ON public.document_requests TO authenticated;
-- Registrar processing (docreq_registrar_process). processed_by / processed_at are set by
-- the trigger below, so they are not granted.
GRANT UPDATE (status, remarks) ON public.document_requests TO authenticated;

-- document_types: read for every signed-in user (doc_types_read), nothing for anon.
REVOKE ALL ON public.document_types FROM PUBLIC, anon;
GRANT SELECT ON public.document_types TO authenticated;

-- The ticket sequence: USAGE is what the DEFAULT's nextval needs (decision 1).
REVOKE ALL ON SEQUENCE public.document_ticket_seq FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SEQUENCE public.document_ticket_seq TO authenticated;

-- ------------------------------------------
-- 3. The trigger function (decisions 3 to 6)
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.require_document_status_flow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
DECLARE
  v_old             text;
  v_new             text;
  v_uid             uuid;
  v_status_changed  boolean;
  v_remarks_changed boolean;
BEGIN
  IF TG_OP <> 'UPDATE' OR TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW'
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'document_requests' THEN
    RAISE EXCEPTION 'private.require_document_status_flow must be a BEFORE UPDATE FOR EACH ROW trigger on public.document_requests';
  END IF;

  v_old := OLD.status::text;
  v_new := NEW.status::text;
  v_status_changed  := v_new IS DISTINCT FROM v_old;
  v_remarks_changed := NEW.remarks::text IS DISTINCT FROM OLD.remarks::text;
  v_uid := auth.uid();

  -- Final states: nothing about the decision can change any more.
  IF v_old IN ('Released', 'Rejected') AND (v_status_changed OR v_remarks_changed) THEN
    RAISE EXCEPTION 'bad status change: request % is % (final) and cannot be changed', OLD.request_id, v_old
      USING ERRCODE = 'P0001',
            DETAIL = pg_catalog.format('attempted: status %s -> %s%s', v_old, COALESCE(v_new, 'NULL'),
                                       CASE WHEN v_remarks_changed THEN ', remarks changed' ELSE '' END),
            HINT = 'Released and Rejected are final. The student files a new request instead.';
  END IF;

  -- A Pending request cannot carry processed_by (table check) while the Registrar policy
  -- demands processed_by = the caller on every update, so remarks can only be edited
  -- together with a status change, or once the request is Processing or Ready.
  IF NOT v_status_changed AND v_remarks_changed AND v_old = 'Pending' THEN
    RAISE EXCEPTION 'bad status change: remarks cannot be edited while request % is Pending', OLD.request_id
      USING ERRCODE = 'P0001',
            HINT = 'Move the request to Processing or Rejected (remarks can go in the same update), then edit remarks.';
  END IF;

  -- One step of the flow at a time.
  IF v_status_changed
     AND (COALESCE(v_old, 'NULL') || ' -> ' || COALESCE(v_new, 'NULL')) NOT IN
         ('Pending -> Processing', 'Processing -> Ready', 'Ready -> Released',
          'Pending -> Rejected', 'Processing -> Rejected') THEN
    RAISE EXCEPTION 'bad status change: % -> % is not allowed (request %)',
                    COALESCE(v_old, 'NULL'), COALESCE(v_new, 'NULL'), OLD.request_id
      USING ERRCODE = 'P0001',
            HINT = 'Allowed: Pending -> Processing -> Ready -> Released, or Pending / Processing -> Rejected, one step at a time.';
  END IF;

  -- Who processed it and when: always from the database, never from the statement.
  IF v_uid IS NOT NULL THEN
    IF v_status_changed OR v_remarks_changed THEN
      NEW.processed_by := v_uid;
      NEW.processed_at := pg_catalog.now();
    ELSE
      NEW.processed_by := OLD.processed_by;
      NEW.processed_at := OLD.processed_at;
    END IF;
  ELSIF v_status_changed THEN
    NEW.processed_at := pg_catalog.now();
  END IF;

  RETURN NEW;
END
$function$;

-- Same grant style as the other trigger functions (hardening2.sql section C).
REVOKE EXECUTE ON FUNCTION private.require_document_status_flow() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.require_document_status_flow() TO authenticated;

-- ------------------------------------------
-- 4. The trigger (after guard_immutable_columns by name, before RLS WITH CHECK and
--    audit_log; decision 7). No WHEN clause: it must also reset processed_* on updates
--    that do not change the status.
-- ------------------------------------------
DROP TRIGGER IF EXISTS require_document_status_flow ON public.document_requests;
CREATE TRIGGER require_document_status_flow BEFORE UPDATE ON public.document_requests
  FOR EACH ROW EXECUTE FUNCTION private.require_document_status_flow();

-- ------------------------------------------
-- 5. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.require_document_status_flow()');
  v_bad text;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'documents_rules: function not created; rolled back';
  END IF;

  -- a) Function: SECURITY INVOKER, empty search_path; no PUBLIC entry, anon cannot
  --    execute, authenticated can.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.oid = v_fn AND NOT p.prosecdef
                   AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']) THEN
    RAISE EXCEPTION 'documents_rules: function is not SECURITY INVOKER with an empty search_path; rolled back';
  END IF;
  IF (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
      FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
     OR pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'documents_rules: function grants are not PUBLIC none / anon none / authenticated EXECUTE; rolled back';
  END IF;

  -- b) Trigger: BEFORE UPDATE FOR EACH ROW (tgtype 1 + 2 + 16 = 19), enabled, no WHEN.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.document_requests'::pg_catalog.regclass
                   AND t.tgname = 'require_document_status_flow' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn AND t.tgtype = 19 AND t.tgenabled = 'O' AND t.tgqual IS NULL) THEN
    RAISE EXCEPTION 'documents_rules: trigger require_document_status_flow missing or not BEFORE UPDATE ROW enabled; rolled back';
  END IF;

  -- c) Exactly the 3 expected triggers on document_requests, BEFORE ones in this order.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.document_requests'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, guard_immutable_columns, require_document_status_flow' THEN
    RAISE EXCEPTION 'documents_rules: triggers on document_requests are [%]; rolled back', v_bad;
  END IF;

  -- d) anon: no privilege of any kind on the two tables and the sequence.
  IF pg_catalog.has_table_privilege('anon', 'public.document_requests', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR pg_catalog.has_any_column_privilege('anon', 'public.document_requests', 'SELECT, INSERT, UPDATE, REFERENCES')
     OR pg_catalog.has_table_privilege('anon', 'public.document_types', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR pg_catalog.has_any_column_privilege('anon', 'public.document_types', 'SELECT, INSERT, UPDATE, REFERENCES')
     OR pg_catalog.has_sequence_privilege('anon', 'public.document_ticket_seq', 'USAGE, SELECT, UPDATE') THEN
    RAISE EXCEPTION 'documents_rules: anon still has a privilege on document_requests, document_types or document_ticket_seq; rolled back';
  END IF;

  -- e) authenticated on document_requests: SELECT, and NO table-level INSERT / UPDATE /
  --    DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN; on document_types: SELECT and
  --    no TRUNCATE / REFERENCES / TRIGGER / MAINTAIN; on the sequence: USAGE only.
  IF NOT pg_catalog.has_table_privilege('authenticated', 'public.document_requests', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.document_requests', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR NOT pg_catalog.has_table_privilege('authenticated', 'public.document_types', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.document_types', 'TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR NOT pg_catalog.has_sequence_privilege('authenticated', 'public.document_ticket_seq', 'USAGE')
     OR pg_catalog.has_sequence_privilege('authenticated', 'public.document_ticket_seq', 'SELECT, UPDATE') THEN
    RAISE EXCEPTION 'documents_rules: wrong table-level or sequence grants for authenticated; rolled back';
  END IF;

  -- f) The column grants of authenticated on document_requests are exactly the 6 above.
  WITH expected(col, priv) AS (VALUES
    ('student_id', 'INSERT'), ('document_type_id', 'INSERT'), ('purpose', 'INSERT'), ('copies', 'INSERT'),
    ('status', 'UPDATE'), ('remarks', 'UPDATE')),
  live AS (
    SELECT a.attname::text AS col, x.privilege_type::text AS priv
    FROM pg_catalog.pg_attribute a
    CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
    WHERE a.attrelid = 'public.document_requests'::pg_catalog.regclass
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
      AND x.grantee = 'authenticated'::regrole),
  diff AS (
    (SELECT 'missing ' || col || ' ' || priv AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || col || ' ' || priv FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'documents_rules: column grants on document_requests differ: %; rolled back', v_bad;
  END IF;
END
$$;

-- Ask PostgREST to reload its schema cache (sent when the transaction commits).
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state before this file)
-- ------------------------------------------
-- Drops the trigger and the function, puts document_requests back to "authenticated SELECT
-- only" (the state after grants_clearance.sql). document_types is left as it is (this file
-- only revoked anon / PUBLIC there, which hardening2.sql section C had already done).
-- The SEQUENCE grants before this file were never written down: compare with the SAVED
-- output of diagnostic (a) and grant back exactly what it showed. The commented GRANT
-- below is Supabase's usual default; use it only if diagnostic (a) showed exactly that.
-- Requests processed while the trigger existed keep their status and processed_*; their
-- audit rows stay.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS require_document_status_flow ON public.document_requests;
-- DROP FUNCTION IF EXISTS private.require_document_status_flow();
--
-- REVOKE ALL ON public.document_requests FROM PUBLIC, anon, authenticated;
-- GRANT SELECT ON public.document_requests TO authenticated;
--
-- -- Sequence: as in the saved diagnostic (a), for example:
-- -- GRANT USAGE, SELECT, UPDATE ON SEQUENCE public.document_ticket_seq TO anon, authenticated;
--
-- NOTIFY pgrst, 'reload schema';
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: ACLs of the two tables (with column ACLs) and of the sequence.
--    SAVE the "before" output; the ROLLBACK needs the sequence part of it.
-- select c.relname, c.relkind::text, c.relacl::text as acl,
--        (select string_agg(a.attname || '=' || a.attacl::text, '; ' order by a.attnum)
--           from pg_attribute a
--          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attacl is not null) as column_acls
-- from pg_class c
-- where c.relnamespace = 'public'::regnamespace
--   and c.relname in ('document_requests', 'document_types', 'document_ticket_seq')
-- order by 1;
--
-- b) BEFORE and AFTER: triggers on document_requests in firing order. After:
--    guard_immutable_columns, require_document_status_flow (BEFORE); audit_log (AFTER).
-- select t.tgname,
--        case when (t.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
--        t.tgenabled, t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t
-- where t.tgrelid = 'public.document_requests'::regclass and not t.tgisinternal
-- order by case when (t.tgtype::int & 2) = 2 then 0 else 1 end, t.tgname;
--
-- c) BEFORE: the ticket DEFAULT, the constraints and the policies the file relies on.
-- select a.attname, pg_get_expr(d.adbin, d.adrelid) as default_expr
-- from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
-- where d.adrelid = 'public.document_requests'::regclass order by a.attnum;
-- select conname, contype, pg_get_constraintdef(oid) from pg_constraint
-- where conrelid = 'public.document_requests'::regclass order by 1;
-- select tablename, policyname, cmd, permissive, roles, qual, with_check from pg_policies
-- where schemaname = 'public' and tablename in ('document_requests', 'document_types') order by 1, 2;
--
-- d) AFTER: the requests by status, and requests that are not Pending but were never
--    stamped (seed or SQL-editor data; the trigger does not back-fill them).
-- select status, count(*), count(*) filter (where processed_by is null) as without_processed_by
-- from public.document_requests group by status order by status;
--
-- e) AFTER: the latest document request changes in the audit log.
-- select l.log_id, l.created_at, l.action, l.record_id as request_id, l.actor_id,
--        l.old_data ->> 'status' as old_status, l.new_data ->> 'status' as new_status,
--        l.new_data ->> 'ticket_number' as ticket
-- from public.audit_logs l where l.table_name = 'document_requests'
-- order by l.log_id desc limit 20;
