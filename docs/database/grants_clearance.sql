-- ==========================================
-- CLEARANCE SLICE: DATA API GRANTS, LEAST PRIVILEGE (GitHub issue #60, issue 21)
-- ==========================================
-- SEC-02, Sprint 3 plan item S3-1. Runs AFTER hardening.sql, hardening2.sql (A, B, C)
-- and views_extend.sql (all live since 2026-10-10).
--
-- EXPOSED BY THIS FILE (to the role authenticated ONLY; RLS then limits each user to
-- their own rows, see the per-grant notes in section 2):
--
--   Reads (SELECT):
--     public.v_clearances, public.v_clearance_items, public.v_active_holds,
--     public.charges, public.payments, public.audit_logs
--     (public.profiles is already exposed and is NOT changed by this file.
--      clearances, clearance_items and academic_holds keep the SELECT they already had
--      since hardening2.sql section C; an UPDATE ... WHERE and a RETURNING need it.)
--
--   Writes (column-level, nothing else):
--     public.clearances       INSERT (student_id, term_id)
--                             UPDATE (approved_by, approved_at)
--     public.clearance_items  UPDATE (cleared_at, cleared_by, remarks)
--     public.academic_holds   INSERT (student_id, department_id, reason, placed_by)
--                             UPDATE (lifted_by, lifted_at)
--     public.payments         INSERT (charge_id, amount_paid, paid_at, receipt_number, recorded_by)
--     public.charges          UPDATE (amount, due_date, status)
--
--   Never granted here: DELETE on anything; TRUNCATE / REFERENCES / TRIGGER / MAINTAIN on
--   anything; INSERT on charges and clearance_items; UPDATE on payments; any write on
--   audit_logs or on a view; ANYTHING to anon. The server role (Supabase's server-side
--   API role) is not touched. Every other table keeps exactly the grants hardening2.sql
--   section C left (authenticated SELECT, plus profiles as it was).
--
-- Afterwards (section 3, repeat of the anon part of hardening2.sql section C): anon has
-- no privilege on any table or view in schema public (including profiles INSERT /
-- UPDATE / DELETE), and anon and authenticated have no TRUNCATE / REFERENCES / TRIGGER /
-- MAINTAIN anywhere in public. Section 4 checks all of this and rolls everything back
-- if any check fails.
--
-- ------------------------------------------
-- DASHBOARD "EXPOSE" STEP: NOT NEEDED (read this before running)
-- ------------------------------------------
-- Do NOT expose the tables in the Supabase dashboard (Integrations, Data API, Settings)
-- for this change. The GRANTs in this file are what the Data API needs. Reasoning, from
-- grants_snapshot_2026-10-10.txt:
--   - PostgREST exposes SCHEMAS (public is exposed), not single tables. Whether a request
--     on a table works is decided by the GRANTs of the request's role (anon or
--     authenticated) and then by RLS.
--   - The dashboard toggle is itself a set of GRANTs: profiles, the only "exposed" table
--     ("1 of 27"), was the only one with full rights for anon, authenticated AND the
--     server role (arwd...), while the 26 "not exposed" tables still had SELECT for
--     authenticated and anon. Toggling a table therefore grants SELECT / INSERT / UPDATE
--     / DELETE to all three roles, which is broader than this file (anon gets full
--     rights, authenticated gets DELETE). That is why section 3 exists.
-- Uncertain, stated plainly:
--   - The exact rule the dashboard uses to count a table as "exposed" is not documented
--     in this repo. It probably looks at the server role, which this file does not
--     change, so the dashboard will most likely still say "1 of 27". That is cosmetic;
--     do not "fix" it by toggling.
--   - It is not yet verified through the real API (only in SQL). After running, check
--     with the signed-in app (TC-40 in Part I of docs/issue-12-testing-guide.md). If
--     the API answers PGRST205 ("Could not find the table ... in the schema cache") for
--     one of these objects even after the schema reload at the end of this file, expose
--     only that object in the dashboard and then run this WHOLE file again: it is
--     re-runnable and removes what the toggle added for anon and authenticated (the
--     server role would keep the toggle's rights; tell the Backend team).
--   - If anybody toggles one of these tables in the dashboard LATER, run this file again.
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable: section 2 starts from REVOKE ALL on the 9 objects, so the
-- result is the same however often it runs. GRANT / REVOKE take a short lock on each
-- table; well under a second on this data.
--   - Before running: run diagnostic (a) at the bottom and SAVE the output (exact ACLs
--     before; the ROLLBACK block must return to it).
--   - Requires PostgreSQL 17 or later (MAINTAIN); the live project is 17 (hardening2.sql
--     section C used MAINTAIN). The first check stops on an older server.
--   - Check the output for "WARNING: no privileges could be revoked/granted": it means a
--     grant was made by another role and is still there; the checks in section 4 then
--     stop the run.
-- Test BEFORE the live run (TC-34R): the top of docs/database/grants_clearance_test.sql
-- explains how to run sections 1 to 4 of this file together with a test block inside
-- one transaction that ends in ROLLBACK. Test AFTER: Part I of
-- docs/issue-12-testing-guide.md (TC-34 to TC-39), then TC-12 to TC-33 again (Parts C,
-- F, G, H).
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: NOT RUN on the live database yet. Not tested on a local PostgreSQL either (none
-- was available when this file was written); the rehearsal block is the first test.


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
-- The column grants in section 2 are only least privilege TOGETHER WITH the live RLS
-- policies and the immutable-column triggers. If any of those is not exactly as
-- expected (missing, an extra write policy, an older policy text from before
-- hardening.sql / hardening2.sql section A), stop instead of guessing.
DO $$
DECLARE
  v_bad text;
BEGIN
  IF current_setting('server_version_num')::int < 170000 THEN
    RAISE EXCEPTION 'grants_clearance: PostgreSQL 17+ required (MAINTAIN); found %', current_setting('server_version');
  END IF;

  -- a) The 9 objects exist with the expected kind.
  SELECT string_agg(e.name, ', ') INTO v_bad
  FROM (VALUES ('clearances', 'r'), ('clearance_items', 'r'), ('academic_holds', 'r'),
               ('payments', 'r'), ('charges', 'r'), ('audit_logs', 'r'),
               ('v_clearances', 'v'), ('v_clearance_items', 'v'), ('v_active_holds', 'v')) AS e(name, kind)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                    WHERE c.relnamespace = 'public'::regnamespace
                      AND c.relname = e.name AND c.relkind::text = e.kind);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: missing or wrong kind: %; stop', v_bad;
  END IF;

  -- b) RLS is enabled on the 6 tables (granting writes without RLS would open them).
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace
    AND c.relname IN ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges', 'audit_logs')
    AND NOT c.relrowsecurity;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: RLS is not enabled on %; stop', v_bad;
  END IF;

  -- c) The 3 views are security_invoker (otherwise they run as the owner and skip RLS).
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace
    AND c.relname IN ('v_clearances', 'v_clearance_items', 'v_active_holds')
    AND NOT coalesce(c.reloptions @> ARRAY['security_invoker=true'], false);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: view(s) not security_invoker: %; stop', v_bad;
  END IF;

  -- d) The policies on the 6 tables are exactly the live set (rls.sql, with the 3
  --    policies replaced by hardening.sql and holds_dept_place by hardening2.sql A):
  --    all PERMISSIVE, all TO authenticated, nothing more, nothing less.
  WITH expected(tablename, policyname, cmd) AS (VALUES
    ('academic_holds', 'holds_dept_lift', 'UPDATE'),
    ('academic_holds', 'holds_dept_place', 'INSERT'),
    ('academic_holds', 'holds_read', 'SELECT'),
    ('audit_logs', 'audit_admin_read', 'SELECT'),
    ('charges', 'charges_cashier_update', 'UPDATE'),
    ('charges', 'charges_cashier_write', 'INSERT'),
    ('charges', 'charges_read', 'SELECT'),
    ('clearance_items', 'clearance_items_dept_update', 'UPDATE'),
    ('clearance_items', 'clearance_items_read', 'SELECT'),
    ('clearances', 'clearances_read', 'SELECT'),
    ('clearances', 'clearances_registrar_approve', 'UPDATE'),
    ('clearances', 'clearances_student_request', 'INSERT'),
    ('payments', 'payments_cashier_insert', 'INSERT'),
    ('payments', 'payments_read', 'SELECT')),
  live AS (
    SELECT p.tablename::text, p.policyname::text, p.cmd::text
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public'
      AND p.tablename IN ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges', 'audit_logs')
      AND p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[]),
  diff AS (
    (SELECT 'missing ' || tablename || '.' || policyname || ' ' || cmd AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || tablename || '.' || policyname || ' ' || cmd FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x)
    UNION ALL
    (SELECT 'not permissive / not TO authenticated: ' || p.tablename || '.' || p.policyname
     FROM pg_catalog.pg_policies p
     WHERE p.schemaname = 'public'
       AND p.tablename IN ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges', 'audit_logs')
       AND NOT (p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[])))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: policies differ from the reviewed set: %; stop', v_bad;
  END IF;

  -- e) The hardened versions are live: no "who did it IS NULL" escape (hardening.sql
  --    finding 1) and the program-department check on holds (hardening2.sql A).
  SELECT string_agg(p.tablename || '.' || p.policyname, ', ') INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public'
    AND ((p.policyname IN ('clearances_registrar_approve', 'clearance_items_dept_update', 'holds_dept_lift')
          AND (p.with_check IS NULL OR position('IS NULL' IN upper(p.with_check)) > 0
               OR position('active_uid' IN p.with_check) = 0))
      OR (p.policyname = 'holds_dept_place'
          AND position('student_in_my_program_department' IN coalesce(p.with_check, '')) = 0));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: pre-hardening policy text found on %; run hardening.sql / hardening2.sql A first; stop', v_bad;
  END IF;

  -- f) The immutable-column triggers (hardening.sql) are present and enabled on the 4
  --    tables that get UPDATE. The column grants already block those columns; the
  --    triggers stay as the second layer.
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('clearances'), ('clearance_items'), ('academic_holds'), ('charges')) AS e(t)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid = ('public.' || e.t)::regclass AND t.tgname = 'guard_immutable_columns'
      AND NOT t.tgisinternal AND t.tgenabled <> 'D'
      AND t.tgfoid = 'private.guard_immutable_columns()'::pg_catalog.regprocedure);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: guard_immutable_columns trigger missing or disabled on %; stop', v_bad;
  END IF;

  -- g) audit_logs is append-only (hardening2.sql B); this file only grants SELECT on it.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.audit_logs'::regclass AND t.tgname = 'audit_logs_readonly'
                   AND t.tgenabled = 'A') THEN
    RAISE EXCEPTION 'grants_clearance: audit_logs_readonly trigger missing or not ENABLE ALWAYS; stop';
  END IF;
END
$$;

-- ------------------------------------------
-- 2. Grants on the 9 objects (authenticated only)
-- ------------------------------------------
-- Start from nothing on these 9 objects, so the result does not depend on what was there
-- (for example a dashboard toggle). REVOKE on a table also removes its column grants.
-- Then authenticated gets back the SELECT it had (hardening2.sql section C) plus the
-- writes below. Rows are limited per role by RLS; the column lists limit WHAT a writer
-- can set. Column choice per table = the columns the write policy and the
-- guard_immutable_columns trigger leave changeable, minus the ones that have a correct
-- default and no flow that needs to set them.
REVOKE ALL ON public.clearances, public.clearance_items, public.academic_holds,
              public.payments, public.charges, public.audit_logs,
              public.v_clearances, public.v_clearance_items, public.v_active_holds
  FROM PUBLIC, anon, authenticated;

-- Reads. RLS (and security_invoker for the views) decides the rows:
--   clearances / v_clearances        clearances_read: own student; Registrar, Admin;
--                                    Cashier, Department for clearances with an item of
--                                    their department
--   clearance_items / v_clearance_items  clearance_items_read: Registrar, Admin; Cashier,
--                                    Department for their department; own student
--   academic_holds / v_active_holds  holds_read: own student; Registrar, Admin;
--                                    Department for their department
--   charges                          charges_read: own student; Cashier
--   payments                         payments_read: Cashier; own student (via charges)
--   audit_logs                       audit_admin_read: Admin only
GRANT SELECT ON public.clearances, public.clearance_items, public.academic_holds,
                public.payments, public.charges, public.audit_logs,
                public.v_clearances, public.v_clearance_items, public.v_active_holds
  TO authenticated;

-- clearances INSERT (student_id, term_id). Policy clearances_student_request: only a
-- Student, only for themself (student_id = active_uid), approved_by and approved_at
-- must be NULL. So the student only ever sets student_id and term_id; approved_* are
-- left out (NULL by default, which the policy requires anyway); clearance_id is an
-- identity column (GENERATED ALWAYS, no sequence grant needed); created_at is left out
-- so it keeps DEFAULT now() and a request cannot be back-dated. The AFTER INSERT
-- trigger trg_clearances_create_items (private.create_clearance_items, SECURITY
-- DEFINER) creates the clearance_items rows as the owner, so no INSERT on
-- clearance_items is needed.
GRANT INSERT (student_id, term_id) ON public.clearances TO authenticated;

-- clearances UPDATE (approved_by, approved_at). Policy clearances_registrar_approve
-- (hardening.sql): only the Registrar, and approved_by must be the caller. student_id
-- and term_id are locked by guard_immutable_columns; created_at has no flow that
-- changes it. So only the approval pair is updatable.
GRANT UPDATE (approved_by, approved_at) ON public.clearances TO authenticated;

-- clearance_items UPDATE (cleared_at, cleared_by, remarks). Policy
-- clearance_items_dept_update (hardening.sql): Cashier or Department, only items of
-- their own department, cleared_by must be the caller. clearance_id and department_id
-- are locked by guard_immutable_columns. No INSERT (created by the trigger above) and
-- no DELETE policy.
GRANT UPDATE (cleared_at, cleared_by, remarks) ON public.clearance_items TO authenticated;

-- academic_holds INSERT (student_id, department_id, reason, placed_by). Policy
-- holds_dept_place (hardening2.sql A): only a Department user, department_id = their
-- department, placed_by = the caller, lifted_by and lifted_at NULL, and the student's
-- program belongs to that department. lifted_* are left out (NULL by default, required
-- anyway); placed_at is left out so it keeps DEFAULT now() (the Holds screen shows
-- "today"; no back-dating). hold_id is an identity column.
GRANT INSERT (student_id, department_id, reason, placed_by) ON public.academic_holds TO authenticated;

-- academic_holds UPDATE (lifted_by, lifted_at). Policy holds_dept_lift (hardening.sql):
-- only a Department user of the hold's department, lifted_by must be the caller.
-- guard_immutable_columns locks every other column (student_id, department_id,
-- placed_by, placed_at, reason), so the column grant and the trigger list agree.
GRANT UPDATE (lifted_by, lifted_at) ON public.academic_holds TO authenticated;

-- payments INSERT (charge_id, amount_paid, paid_at, receipt_number, recorded_by).
-- Policy payments_cashier_insert: only the Cashier, recorded_by must be the caller.
-- paid_at IS included: the Cashier's payment form (components/cashier/PaymentsView.tsx)
-- has a date field, so a payment received earlier can be recorded with its real date
-- (RLS does not restrict this date; if back-dating should be forbidden, drop paid_at
-- here and let DEFAULT now() apply). payment_id is an identity column. No UPDATE and no
-- DELETE: there is no policy for either, and a payment is corrected with a new row.
GRANT INSERT (charge_id, amount_paid, paid_at, receipt_number, recorded_by) ON public.payments TO authenticated;

-- charges UPDATE (amount, due_date, status). Policy charges_cashier_update: Cashier
-- only. student_id, term_id and fee_type_id are locked by guard_immutable_columns;
-- hardening.sql leaves amount and due_date changeable on purpose (correct a mistyped
-- amount, extend a due date) and status must change (Unpaid -> Cleared / Waived).
-- charges INSERT is NOT granted although the policy charges_cashier_write exists: the
-- issue does not list it and no screen creates charges yet (add
-- GRANT INSERT (student_id, term_id, fee_type_id, amount, due_date, status) ON public.charges TO authenticated;
-- in a later, reviewed change when one does).
GRANT UPDATE (amount, due_date, status) ON public.charges TO authenticated;

-- ------------------------------------------
-- 3. Repeat the anon part of hardening2.sql section C (after the exposure)
-- ------------------------------------------
-- Exposing a table in the Supabase Data API restores its default rights, including
-- anon's (this is how profiles got anon INSERT / UPDATE / DELETE). This section runs on
-- EVERY table and view in public, not only the 9 above, so it also cleans up after any
-- toggle done earlier. It is stricter than section C: REVOKE ALL instead of SELECT
-- only, so anon is left with no privilege of any kind (column grants included). PUBLIC
-- had no table grants in the snapshot; it is listed so a stray PUBLIC grant cannot give
-- anon access either.
REVOKE INSERT, UPDATE, DELETE ON public.profiles FROM anon;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon;

-- TRUNCATE ignores RLS and row triggers; nobody needs REFERENCES or TRIGGER; MAINTAIN
-- (PostgreSQL 17: VACUUM, ANALYZE, REINDEX, CLUSTER, LOCK) is not shown by
-- information_schema but is in the ACLs. Same statements as section C.
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM authenticated, anon;
REVOKE MAINTAIN ON ALL TABLES IN SCHEMA public FROM authenticated, anon;

-- ------------------------------------------
-- 4. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
BEGIN
  -- a) anon: no privilege of any kind on any table or view in public.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'p', 'f')
    AND (has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
         OR has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: anon still has a privilege on %; rolled back', v_bad;
  END IF;

  -- b) authenticated: no TRUNCATE / REFERENCES / TRIGGER / MAINTAIN anywhere in public.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'p', 'f')
    AND (has_table_privilege('authenticated', c.oid, 'TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
         OR has_any_column_privilege('authenticated', c.oid, 'REFERENCES'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: authenticated has TRUNCATE/REFERENCES/TRIGGER/MAINTAIN on %; rolled back', v_bad;
  END IF;

  -- c) The 9 objects: authenticated has SELECT, and NO table-level INSERT, UPDATE or
  --    DELETE (writes are column-level only, DELETE nowhere).
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace
    AND c.relname IN ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges', 'audit_logs',
                      'v_clearances', 'v_clearance_items', 'v_active_holds')
    AND (NOT has_table_privilege('authenticated', c.oid, 'SELECT')
         OR has_table_privilege('authenticated', c.oid, 'INSERT, UPDATE, DELETE'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: wrong table-level grants for authenticated on %; rolled back', v_bad;
  END IF;

  -- d) The column grants of authenticated on the 9 objects are exactly the 21 above.
  WITH expected(t, col, priv) AS (VALUES
    ('clearances', 'student_id', 'INSERT'), ('clearances', 'term_id', 'INSERT'),
    ('clearances', 'approved_by', 'UPDATE'), ('clearances', 'approved_at', 'UPDATE'),
    ('clearance_items', 'cleared_at', 'UPDATE'), ('clearance_items', 'cleared_by', 'UPDATE'),
    ('clearance_items', 'remarks', 'UPDATE'),
    ('academic_holds', 'student_id', 'INSERT'), ('academic_holds', 'department_id', 'INSERT'),
    ('academic_holds', 'reason', 'INSERT'), ('academic_holds', 'placed_by', 'INSERT'),
    ('academic_holds', 'lifted_by', 'UPDATE'), ('academic_holds', 'lifted_at', 'UPDATE'),
    ('payments', 'charge_id', 'INSERT'), ('payments', 'amount_paid', 'INSERT'),
    ('payments', 'paid_at', 'INSERT'), ('payments', 'receipt_number', 'INSERT'),
    ('payments', 'recorded_by', 'INSERT'),
    ('charges', 'amount', 'UPDATE'), ('charges', 'due_date', 'UPDATE'), ('charges', 'status', 'UPDATE')),
  live AS (
    SELECT c.relname::text AS t, a.attname::text AS col, x.privilege_type::text AS priv
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    CROSS JOIN LATERAL aclexplode(a.attacl) x
    WHERE c.relnamespace = 'public'::regnamespace
      AND c.relname IN ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges', 'audit_logs',
                        'v_clearances', 'v_clearance_items', 'v_active_holds')
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
      AND x.grantee = 'authenticated'::regrole),
  diff AS (
    (SELECT 'missing ' || t || '.' || col || ' ' || priv AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || t || '.' || col || ' ' || priv FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: column grants differ: %; rolled back', v_bad;
  END IF;

  -- e) Nothing else lost: authenticated still reads every table and view in public
  --    (TC-27 auth_select_all) and still has its profiles rights (unchanged here).
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'p', 'f')
    AND NOT has_table_privilege('authenticated', c.oid, 'SELECT');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'grants_clearance: authenticated lost SELECT on %; rolled back', v_bad;
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.profiles', 'INSERT, UPDATE') THEN
    RAISE EXCEPTION 'grants_clearance: authenticated lost its profiles rights; rolled back';
  END IF;
END
$$;

-- Ask PostgREST to reload its schema cache (sent when the transaction commits).
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state after hardening2.sql section C and views_extend.sql)
-- ------------------------------------------
-- Before this file the 9 objects had: authenticated SELECT only, nothing for anon
-- (hardening2.sql section C; views_extend.sql kept the view grants). Section 3 of this
-- file only REVOKEs what section C had already revoked, so there is nothing to give back
-- for anon or for the other tables: undoing it would mean re-opening anon, which is not
-- wanted. Compare with the saved output of diagnostic (a) afterwards; if it shows more
-- (for example the server role's leftover Dxtm, which this file never touches), nothing
-- needs to be done for those.
-- If the tables were toggled in the dashboard, toggle them back there first, then run
-- this block (the toggle may also remove authenticated SELECT, which this block grants
-- back).
--
-- BEGIN;
--
-- REVOKE ALL ON public.clearances, public.clearance_items, public.academic_holds,
--               public.payments, public.charges, public.audit_logs,
--               public.v_clearances, public.v_clearance_items, public.v_active_holds
--   FROM PUBLIC, anon, authenticated;
-- GRANT SELECT ON public.clearances, public.clearance_items, public.academic_holds,
--                 public.payments, public.charges, public.audit_logs,
--                 public.v_clearances, public.v_clearance_items, public.v_active_holds
--   TO authenticated;
-- NOTIFY pgrst, 'reload schema';
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: exact table / view ACLs and column ACLs of the 9 objects (and
--    profiles for reference). Save the "before" output; the ROLLBACK must return to it.
-- select c.relname, c.relkind::text, c.relacl::text as acl,
--        (select string_agg(a.attname || '=' || a.attacl::text, '; ' order by a.attnum)
--           from pg_attribute a
--          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attacl is not null) as column_acls
-- from pg_class c
-- where c.relnamespace = 'public'::regnamespace
--   and c.relname in ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges',
--                     'audit_logs', 'v_clearances', 'v_clearance_items', 'v_active_holds', 'profiles')
-- order by 1;
--
-- b) AFTER: effective privileges per role on the 9 objects (true = allowed). INSERT and
--    UPDATE here are table-level; column-level writes show in (c).
-- select c.relname, r.rolname,
--        has_table_privilege(r.rolname, c.oid, 'SELECT') as sel,
--        has_table_privilege(r.rolname, c.oid, 'INSERT') as ins_table,
--        has_table_privilege(r.rolname, c.oid, 'UPDATE') as upd_table,
--        has_table_privilege(r.rolname, c.oid, 'DELETE') as del,
--        has_any_column_privilege(r.rolname, c.oid, 'INSERT') as ins_any_column,
--        has_any_column_privilege(r.rolname, c.oid, 'UPDATE') as upd_any_column,
--        has_table_privilege(r.rolname, c.oid, 'TRUNCATE, REFERENCES, TRIGGER, MAINTAIN') as dxtm
-- from pg_class c cross join (values ('anon'::name), ('authenticated'::name)) as r(rolname)
-- where c.relnamespace = 'public'::regnamespace
--   and c.relname in ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges',
--                     'audit_logs', 'v_clearances', 'v_clearance_items', 'v_active_holds')
-- order by 1, 2;
--
-- c) AFTER: column grants (explicit grants only; expect the 21 rows listed in the header,
--    all for authenticated):
-- select table_name, column_name, privilege_type, grantee
-- from information_schema.column_privileges
-- where table_schema = 'public' and grantee in ('anon', 'authenticated')
--   and privilege_type in ('INSERT', 'UPDATE')
--   and table_name in ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges',
--                      'audit_logs', 'v_clearances', 'v_clearance_items', 'v_active_holds')
-- order by 1, 3, 2;
--   Note: information_schema.column_privileges also lists a column when the role has the
--   privilege on the whole table, so a table-level SELECT shows up for every column;
--   the filter above keeps INSERT / UPDATE only.
--
-- d) The policies the grants rely on (compare with check 1d):
-- select tablename, policyname, cmd, permissive, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'public'
--   and tablename in ('clearances', 'clearance_items', 'academic_holds', 'payments', 'charges', 'audit_logs')
-- order by 1, 2;
--
-- e) Default privileges for tables created LATER (not changed here; see hardening2.sql
--    notes):
-- select pg_get_userbyid(d.defaclrole) as owner, d.defaclnamespace::regnamespace as schema,
--        d.defaclobjtype, d.defaclacl
-- from pg_default_acl d order by 1, 2, 3;
--
-- f) Sequences in public (not changed here; PostgREST does not expose sequences, but
--    anon may still have default USAGE / SELECT on them, for example document_ticket_seq):
-- select c.relname, c.relacl::text from pg_class c
-- where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' order by 1;


-- ==========================================
-- NOTES FOR THE PM (not done here, on purpose)
-- ==========================================
-- - DELETE stays revoked on all 9 objects. authenticated still has DELETE on profiles
--   from before (profiles_admin_write, Admin only through RLS); this file does not change
--   profiles for authenticated.
-- - The clearance_items "reject with remarks" flow on the Department screen: under the
--   live policy any UPDATE must set cleared_by = the caller, so saving remarks alone
--   fails (hardening.sql, finding 1 notes). The grant allows the remarks column; the
--   policy decision is separate.
-- - The server role still has no SELECT / INSERT / UPDATE / DELETE on these tables
--   (snapshot: Dxtm only). Server-side code with the server key will need its own,
--   separate grants.
-- - Supabase default privileges (diagnostic e) still give new tables anon rights; repeat
--   section 3 after adding tables, or change them in a separate decision.
