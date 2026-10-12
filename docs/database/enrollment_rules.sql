-- ==========================================
-- ENROLLMENT: DATABASE RULES AND GRANTS (GitHub issue #94, Sprint 4 issue 38)
-- ==========================================
-- REQ-STU-05 (student submits an online enrollment), REQ-REG-04 (Registrar approves or
-- rejects it), SEC-02, REQ-ADM-03 (audit). Runs AFTER hardening.sql, hardening2.sql (A, B,
-- C), grants_clearance.sql and the clearance triggers (all live). Independent of
-- login_lockout.sql and of the grades / documents rules (other tables), but run it after
-- them if they are queued, so the execution order stays the order of the README.
--
-- WHAT IT DOES
--   1. Unique keys (only if missing; live has the first one per the issue):
--        enrollments (student_id, term_id)            -> uq_enrollments_student_term
--        enrollment_items (enrollment_id, section_id) -> uq_enrollment_items_enrollment_section
--      A key is created only when no equivalent unique index exists; the file stops if the
--      data already has duplicates (safety check (h)).
--   2. BEFORE INSERT OR UPDATE trigger require_enrollment_rules on public.enrollments
--      (function private.require_enrollment_rules(), SECURITY DEFINER):
--        - a new enrollment must be Pending; reviewed_by / reviewed_at are forced to NULL;
--        - one enrollment per student per term (friendly error before the unique key);
--        - status flow Pending -> Approved | Rejected; Approved and Rejected are FINAL
--          (any later UPDATE of the row is refused, every role);
--        - on the decision the DATABASE sets reviewed_at = now() and reviewed_by = the
--          signed-in caller (auth.uid()), whatever the client sent;
--        - approval needs at least one section, every section of the enrollment's term,
--          and a free seat in every section (seats taken = items of OTHER Approved
--          enrollments; Pending ones do not count). The section rows are locked first, so
--          two approvals that share a section run one after the other.
--   3. BEFORE INSERT OR UPDATE OR DELETE trigger require_enrollment_item_rules on
--      public.enrollment_items (function private.require_enrollment_item_rules(), SECURITY
--      DEFINER): items only while the enrollment is Pending (add AND remove), the section
--      must belong to the enrollment's term, no section twice, an item cannot move to
--      another enrollment. The enrollment row is locked first, so an item cannot slip in
--      while the Registrar approves.
--   4. Grants for role authenticated (column-level, least privilege; anon gets nothing):
--        enrollments       SELECT; INSERT (student_id, term_id, year_level);
--                          UPDATE (status, reviewed_by, reviewed_at, remarks); no DELETE
--        enrollment_items  SELECT; INSERT (enrollment_id, section_id); DELETE (own Pending
--                          only, by the existing policy and the trigger)
--      RLS policies are NOT changed (the 6 live policies already express who; check (d)).
--
-- DESIGN DECISIONS
--   1. Status flow. CHECK on enrollments.status allows Pending, Approved, Rejected (schema).
--      Allowed: INSERT as Pending; Pending -> Pending (only the owner can do something
--      useful with it, e.g. fix year_level; reviewed_* stay NULL); Pending -> Approved;
--      Pending -> Rejected. Refused: every UPDATE of an Approved or Rejected row, by every
--      role, including a remarks-only change and a no-op ("enrollment locked:"). Reasons:
--      grades (issue #92) hang on Approved enrollment items, so un-approving would orphan
--      grades; a rejected enrollment re-opened silently would bypass the review. An
--      intentional correction is a reviewed change by the table owner (ALTER TABLE
--      public.enrollments DISABLE TRIGGER require_enrollment_rules, fix, ENABLE TRIGGER).
--      Consequence (PM decision, see NOTES): with one enrollment per student per term, a
--      Rejected student cannot submit again for that term.
--   2. Who reviews. Policy enrollments_registrar_review (USING Registrar, WITH CHECK
--      Registrar AND reviewed_by = active_uid()) is unchanged. The trigger runs BEFORE the
--      RLS WITH CHECK and sets reviewed_by = auth.uid() on the decision, so the Registrar's
--      screen may send reviewed_by or leave it out, and a spoofed value is replaced. For
--      the owner (SQL editor, no JWT) auth.uid() is NULL: the value given in the UPDATE is
--      kept and must not be NULL ("reviewer required:"). A Registrar's Pending -> Pending
--      update (e.g. remarks only) ends with reviewed_by NULL and is therefore refused by
--      the policy (42501 "new row violates row-level security"): the screen only sends a
--      decision.
--   3. reviewed_at always comes from the database: now() (transaction time) on the
--      decision, NULL while Pending. The grant still includes reviewed_by and reviewed_at
--      because the issue lists them and an UPDATE that names them would otherwise fail with
--      "permission denied"; whatever is sent is overwritten. (PM may narrow the grant to
--      (status, remarks); see NOTES.)
--   4. Capacity. Counted at APPROVAL only, never at submission (a student may pick a full
--      section; the Registrar's approval then fails with "section full:"). Seats taken =
--      enrollment_items of enrollments with status Approved, excluding the enrollment being
--      approved. Concurrency: the approving UPDATE already holds the enrollment row; the
--      trigger then locks the enrollment's section rows FOR NO KEY UPDATE in section_id
--      order (no deadlock between two approvals; does not block students adding items,
--      whose foreign-key check takes only KEY SHARE). Under READ COMMITTED the count runs
--      after the lock, so it sees every approval committed before it.
--   5. Same term. Checked when an item is added (the section's term_id must equal the
--      enrollment's term_id) and again at approval (a section moved to another term by the
--      Admin afterwards blocks the approval with "wrong term:").
--   6. Items only while Pending: INSERT, UPDATE and DELETE of enrollment_items need the
--      enrollment to be Pending, for every role (the policies already require it for the
--      student; the trigger adds the owner and closes the race with an approval: it locks
--      the enrollment row FOR NO KEY UPDATE, the same lock level the approving UPDATE
--      takes, so they run one after the other and the later one sees the new status).
--   7. No probing. Both triggers run BEFORE RLS WITH CHECK, so a friendly error could tell
--      a student something about ANOTHER student's enrollment. The enrollment trigger only
--      runs the "enrollment exists" check, and the item trigger only runs its checks, when
--      the caller is the owner (no JWT), the student who owns the enrollment, or the
--      Registrar (who may read every enrollment). Anyone else gets no detail: the row goes
--      on to RLS, which rejects it (42501). The status, review and capacity rules on
--      UPDATE always run: RLS USING has already limited the rows to the Registrar.
--   8. Errors: RAISE with SQLSTATE 'P0001' and a stable message prefix (same style as
--      "active hold:" and "pending items:"). PostgREST returns HTTP 400, code "P0001";
--      the app matches the prefix:
--        enrollment exists:   second enrollment for the same student and term (INSERT)
--        invalid status:      INSERT with a status other than Pending (owner only; the
--                             student has no grant on status)
--        enrollment locked:   UPDATE of an Approved / Rejected enrollment; add, remove or
--                             move an item of a non-Pending enrollment
--        reviewer required:   decision without a reviewer (owner without reviewed_by)
--        wrong term:          section of another term (item INSERT, or at approval)
--        duplicate section:   the same section twice in one enrollment
--        no items:            approval of an enrollment without sections
--        section full:        approval while a section has no seat left (DETAIL lists the
--                             full sections: "full sections: CS-1A (section 7, 40 of 40
--                             seats taken), ...")
--      The unique keys can still answer 23505 (unique_violation) when two requests race
--      (both pass the trigger, the second insert hits the key). Grants answer 42501
--      "permission denied"; RLS answers 42501 "new row violates row-level security".
--   9. SECURITY DEFINER, SET search_path TO '', names schema-qualified: the counts must see
--      every row (other students' approved items for capacity) regardless of the caller's
--      RLS, and the locks need UPDATE rights the student does not have. Owner = postgres
--      (owner of the tables, no FORCE RLS; safety check (g)). EXECUTE: not PUBLIC, not
--      anon, authenticated (same style as the other trigger functions).
--  10. Firing order (BEFORE by name, then RLS WITH CHECK and constraints, the write, AFTER):
--        enrollments UPDATE: guard_immutable_columns -> require_enrollment_rules -> RLS
--                            WITH CHECK -> CHECK / unique -> write -> audit_log (AFTER)
--        enrollments INSERT: require_enrollment_rules -> RLS WITH CHECK -> write -> audit_log
--        enrollment_items:   require_enrollment_item_rules -> RLS WITH CHECK (INSERT) ->
--                            write -> audit_log (AFTER)
--      "require_..." sorts after "guard_..." ('g' < 'r'), so an API change of student_id /
--      term_id is still refused first by the guard (42501 "cannot be changed"). A refused
--      change writes no audit row; an accepted one is audited by the existing audit_log
--      triggers (actor = auth.uid(): the student or the Registrar).
--  11. Grants are rebuilt on the 2 tables only (REVOKE ALL, then GRANT), so a dashboard
--      toggle that re-added full rights is undone. Other tables are not touched. DELETE on
--      enrollment_items IS granted although the issue lists only INSERT: the live policy
--      enrollment_items_student_remove already allows a student to remove a section of
--      their own Pending enrollment, and the student enrollment screen (#101) needs it to
--      fix a wrong pick before the review. Drop that one GRANT if the PM decides against.
--
-- KNOWN LIMITS (not done here, on purpose)
--   - No back-fill: existing rows that break a rule (e.g. seed data approved before this
--     file) are not changed. Diagnostic (e) lists them.
--   - A student may submit for any term (no "current term only" rule); the screen offers
--     the current term. A student may pick two sections of the same subject. Both are PM
--     decisions (NOTES).
--   - Seats left cannot be shown to a student by a plain query (RLS hides other students'
--     items). Diagnostic (f) shows them as the owner; a SECURITY DEFINER read function for
--     the screen would be a separate change.
--   - No index on enrollment_items (section_id); the capacity count is tiny and runs once
--     per approval. The unique key covers lookups by enrollment_id.
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (CREATE OR REPLACE, DROP TRIGGER IF EXISTS, keys only if missing,
-- grants rebuilt from REVOKE ALL).
--   - Before running: run diagnostics (a), (b), (c), (d) and (e) at the bottom and SAVE
--     the output ((c) is what the ROLLBACK block must return to).
--   - Rehearse first: docs/database/enrollment_rules_rehearsal.sql runs this change and all
--     tests (TC-109 to TC-122) in ONE rolled-back transaction with one result row (TC-109R).
-- Test afterwards: docs/database/enrollment_rules_test.sql (TC-109 to TC-122, the same as
-- the test part of the rehearsal), then docs/database/regression_after_grants.sql (TC-12 to
-- TC-33) again.
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: NOT RUN YET (written 2026-10-12 without a local PostgreSQL).


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad  text;
  v_fn_e regprocedure := pg_catalog.to_regprocedure('private.require_enrollment_rules()');
  v_fn_i regprocedure := pg_catalog.to_regprocedure('private.require_enrollment_item_rules()');
BEGIN
  IF current_setting('server_version_num')::int < 170000 THEN
    RAISE EXCEPTION 'enrollment_rules: PostgreSQL 17+ expected (REVOKE ALL includes MAINTAIN); found %', current_setting('server_version');
  END IF;

  -- a) The tables exist.
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('enrollments'), ('enrollment_items'), ('sections'), ('terms'), ('students'),
               ('profiles'), ('audit_logs')) AS e(t)
  WHERE pg_catalog.to_regclass('public.' || e.t) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: missing table(s) public.%; stop', v_bad;
  END IF;

  -- b) The columns the triggers and grants use exist with the expected types
  --    (format_type with a NULL typmod).
  SELECT string_agg(e.t || '.' || e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('enrollments', 'enrollment_id', 'bigint'),
    ('enrollments', 'student_id', 'uuid'),
    ('enrollments', 'term_id', 'bigint'),
    ('enrollments', 'year_level', 'smallint'),
    ('enrollments', 'status', 'character varying'),
    ('enrollments', 'submitted_at', 'timestamp with time zone'),
    ('enrollments', 'reviewed_by', 'uuid'),
    ('enrollments', 'reviewed_at', 'timestamp with time zone'),
    ('enrollments', 'remarks', 'character varying'),
    ('enrollment_items', 'enrollment_item_id', 'bigint'),
    ('enrollment_items', 'enrollment_id', 'bigint'),
    ('enrollment_items', 'section_id', 'bigint'),
    ('sections', 'section_id', 'bigint'),
    ('sections', 'term_id', 'bigint'),
    ('sections', 'section_code', 'character varying'),
    ('sections', 'capacity', 'smallint')) AS e(t, col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.t)
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: missing column or other type: %; stop', v_bad;
  END IF;

  -- c) RLS is enabled on both tables (the grants below rely on it).
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.enrollments'::pg_catalog.regclass, 'public.enrollment_items'::pg_catalog.regclass)
    AND NOT c.relrowsecurity;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: row level security is not enabled on %; stop', v_bad;
  END IF;

  -- d) The policies on the 2 tables are exactly the 6 live ones (rls.sql), all PERMISSIVE
  --    and TO authenticated, with the parts the grants rely on.
  WITH expected(tablename, policyname, cmd) AS (VALUES
    ('enrollments', 'enrollments_read', 'SELECT'),
    ('enrollments', 'enrollments_registrar_review', 'UPDATE'),
    ('enrollments', 'enrollments_student_submit', 'INSERT'),
    ('enrollment_items', 'enrollment_items_read', 'SELECT'),
    ('enrollment_items', 'enrollment_items_student_add', 'INSERT'),
    ('enrollment_items', 'enrollment_items_student_remove', 'DELETE')),
  live AS (
    SELECT p.tablename::text, p.policyname::text, p.cmd::text
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename IN ('enrollments', 'enrollment_items')
      AND p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[]),
  diff AS (
    (SELECT 'missing ' || tablename || '.' || policyname || ' ' || cmd AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || tablename || '.' || policyname || ' ' || cmd FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x)
    UNION ALL
    (SELECT 'not permissive / not TO authenticated: ' || p.tablename || '.' || p.policyname
     FROM pg_catalog.pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename IN ('enrollments', 'enrollment_items')
       AND NOT (p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[])))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: policies differ from the reviewed set: %; stop', v_bad;
  END IF;

  SELECT string_agg(p.policyname, ', ') INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public'
    AND ((p.policyname = 'enrollments_registrar_review'
          AND NOT (position('''Registrar''' IN coalesce(p.qual, '')) > 0
                   AND position('''Registrar''' IN coalesce(p.with_check, '')) > 0
                   AND position('reviewed_by' IN coalesce(p.with_check, '')) > 0
                   AND position('active_uid' IN coalesce(p.with_check, '')) > 0
                   AND position('IS NULL' IN upper(coalesce(p.with_check, ''))) = 0))
      OR (p.policyname = 'enrollments_student_submit'
          AND NOT (position('''Student''' IN coalesce(p.with_check, '')) > 0
                   AND position('''Pending''' IN coalesce(p.with_check, '')) > 0
                   AND position('active_uid' IN coalesce(p.with_check, '')) > 0))
      OR (p.policyname = 'enrollment_items_student_add'
          AND NOT (position('''Pending''' IN coalesce(p.with_check, '')) > 0
                   AND position('active_uid' IN coalesce(p.with_check, '')) > 0))
      OR (p.policyname = 'enrollment_items_student_remove'
          AND NOT (position('''Pending''' IN coalesce(p.qual, '')) > 0
                   AND position('active_uid' IN coalesce(p.qual, '')) > 0)));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: policy text differs from rls.sql on %; stop and review', v_bad;
  END IF;

  -- e) The functions are absent (first run) or are trigger functions (re-run); no trigger
  --    with one of this file's names calls a different function.
  IF (v_fn_e IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn_e)
                             <> 'pg_catalog.trigger'::pg_catalog.regtype)
     OR (v_fn_i IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn_i)
                                <> 'pg_catalog.trigger'::pg_catalog.regtype) THEN
    RAISE EXCEPTION 'enrollment_rules: private.require_enrollment_rules() or private.require_enrollment_item_rules() exists and is not a trigger function; stop and review';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE NOT t.tgisinternal
               AND ((t.tgname = 'require_enrollment_rules' AND (v_fn_e IS NULL OR t.tgfoid <> v_fn_e))
                 OR (t.tgname = 'require_enrollment_item_rules' AND (v_fn_i IS NULL OR t.tgfoid <> v_fn_i)))) THEN
    RAISE EXCEPTION 'enrollment_rules: a different trigger named require_enrollment_rules / require_enrollment_item_rules already exists; stop and review';
  END IF;

  -- f) Triggers: guard_immutable_columns (BEFORE, hardening.sql) on enrollments and
  --    audit_log (AFTER, hardening2.sql B) on both tables exist and are enabled. The only
  --    BEFORE triggers are the guard and this file's own (re-run): another BEFORE trigger
  --    would change the firing order in the header, so stop. Other AFTER triggers are
  --    allowed (listed by diagnostic (a)). tgtype bit 2 = BEFORE.
  SELECT string_agg(e.t || '.' || e.n, ', ') INTO v_bad
  FROM (VALUES ('enrollments', 'guard_immutable_columns', 'private.guard_immutable_columns()', 2),
               ('enrollments', 'audit_log', 'private.audit_log()', 0),
               ('enrollment_items', 'audit_log', 'private.audit_log()', 0)) AS e(t, n, fn, before_bit)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = ('public.' || e.t)::pg_catalog.regclass AND t.tgname = e.n
                      AND NOT t.tgisinternal AND t.tgenabled <> 'D'
                      AND t.tgfoid = pg_catalog.to_regprocedure(e.fn)
                      AND (t.tgtype::integer & 2) = e.before_bit);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: trigger(s) missing, disabled or not the expected function / timing: %; stop', v_bad;
  END IF;

  SELECT string_agg(t.tgrelid::pg_catalog.regclass::text || '.' || t.tgname, ', '
                    ORDER BY t.tgrelid::pg_catalog.regclass::text, t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid IN ('public.enrollments'::pg_catalog.regclass, 'public.enrollment_items'::pg_catalog.regclass)
    AND NOT t.tgisinternal AND (t.tgtype::integer & 2) = 2
    AND NOT ((t.tgrelid = 'public.enrollments'::pg_catalog.regclass AND t.tgname = 'guard_immutable_columns')
          OR (t.tgrelid = 'public.enrollments'::pg_catalog.regclass AND t.tgname = 'require_enrollment_rules')
          OR (t.tgrelid = 'public.enrollment_items'::pg_catalog.regclass AND t.tgname = 'require_enrollment_item_rules'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: unexpected BEFORE trigger(s): %; stop and review (header, decision 10)', v_bad;
  END IF;

  -- g) SECURITY DEFINER only sees every row if its owner (the role running this file)
  --    bypasses RLS on the tables it reads: owner without FORCE RLS, or BYPASSRLS.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.enrollments'::pg_catalog.regclass, 'public.enrollment_items'::pg_catalog.regclass,
                  'public.sections'::pg_catalog.regclass)
    AND NOT (SELECT r.rolbypassrls FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
    AND NOT (c.relowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
             AND NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: % would not bypass RLS on %; run as the table owner (postgres); stop', current_user, v_bad;
  END IF;

  -- h) No duplicates that would stop a missing unique key from being created.
  IF EXISTS (SELECT 1 FROM public.enrollments e GROUP BY e.student_id, e.term_id HAVING pg_catalog.count(*) > 1) THEN
    RAISE EXCEPTION 'enrollment_rules: a student has more than one enrollment in a term (diagnostic (e)); stop and fix the data first';
  END IF;
  IF EXISTS (SELECT 1 FROM public.enrollment_items i GROUP BY i.enrollment_id, i.section_id HAVING pg_catalog.count(*) > 1) THEN
    RAISE EXCEPTION 'enrollment_rules: an enrollment has the same section twice (diagnostic (e)); stop and fix the data first';
  END IF;
END
$$;

-- ------------------------------------------
-- 2. Unique keys (only if no equivalent unique index exists)
-- ------------------------------------------
-- "Equivalent" = a unique, non-partial, non-expression index on exactly these two columns
-- (any order, any name, e.g. a constraint created outside this repo).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    WHERE i.indrelid = 'public.enrollments'::pg_catalog.regclass AND i.indisunique
      AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts = 2
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
             FROM pg_catalog.unnest(i.indkey::int2[]) AS k(attnum)
             JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum)
          = ARRAY['student_id', 'term_id']) THEN
    ALTER TABLE public.enrollments
      ADD CONSTRAINT uq_enrollments_student_term UNIQUE (student_id, term_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    WHERE i.indrelid = 'public.enrollment_items'::pg_catalog.regclass AND i.indisunique
      AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts = 2
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
             FROM pg_catalog.unnest(i.indkey::int2[]) AS k(attnum)
             JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum)
          = ARRAY['enrollment_id', 'section_id']) THEN
    ALTER TABLE public.enrollment_items
      ADD CONSTRAINT uq_enrollment_items_enrollment_section UNIQUE (enrollment_id, section_id);
  END IF;
END
$$;

-- ------------------------------------------
-- 3. Trigger function on enrollments
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.require_enrollment_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid      uuid := auth.uid();
  v_existing bigint;
  v_total    bigint;
  v_wrong    text;
  v_nfull    bigint;
  v_full     text;
BEGIN
  IF TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW' OR TG_OP NOT IN ('INSERT', 'UPDATE')
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'enrollments' THEN
    RAISE EXCEPTION 'private.require_enrollment_rules must be a BEFORE INSERT OR UPDATE FOR EACH ROW trigger on public.enrollments';
  END IF;

  -- INSERT: a new enrollment is Pending, not reviewed, and the only one of the student in
  -- that term.
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IS DISTINCT FROM 'Pending' THEN
      RAISE EXCEPTION 'invalid status: a new enrollment must be Pending, not %', COALESCE(NEW.status::text, 'NULL')
        USING ERRCODE = 'P0001',
              HINT = 'Insert the enrollment as Pending; the Registrar approves or rejects it afterwards.';
    END IF;
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;

    -- Friendly check only for a caller allowed to know (decision 7); the unique key
    -- catches everything else and races (23505).
    IF v_uid IS NULL OR NEW.student_id = v_uid OR private.current_role_name() = 'Registrar' THEN
      SELECT e.enrollment_id INTO v_existing
      FROM public.enrollments e
      WHERE e.student_id = NEW.student_id AND e.term_id = NEW.term_id
      ORDER BY e.enrollment_id
      LIMIT 1;
      IF v_existing IS NOT NULL THEN
        RAISE EXCEPTION 'enrollment exists: the student already has an enrollment for term %', NEW.term_id
          USING ERRCODE = 'P0001',
                DETAIL = pg_catalog.format('existing enrollment: %s', v_existing),
                HINT = 'One enrollment per student per term: add or remove sections on the existing enrollment while it is Pending.';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE. Approved and Rejected are final for every role.
  IF OLD.status::text <> 'Pending' THEN
    RAISE EXCEPTION 'enrollment locked: enrollment % is % and can no longer be changed', OLD.enrollment_id, OLD.status
      USING ERRCODE = 'P0001',
            HINT = 'Approved and Rejected are final. A correction needs a reviewed change by the table owner.';
  END IF;

  -- Still Pending: nothing reviewed yet.
  IF NEW.status::text = 'Pending' THEN
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    RETURN NEW;
  END IF;

  -- The decision (Pending -> Approved / Rejected): the database records who and when.
  NEW.reviewed_at := now();
  IF v_uid IS NOT NULL THEN
    NEW.reviewed_by := v_uid;
  END IF;
  IF NEW.reviewed_by IS NULL THEN
    RAISE EXCEPTION 'reviewer required: enrollment % cannot be set to % without a reviewer', OLD.enrollment_id, NEW.status
      USING ERRCODE = 'P0001',
            HINT = 'Sign in as the Registrar, or (owner only) set reviewed_by in the same UPDATE.';
  END IF;

  IF NEW.status::text = 'Approved' THEN
    -- Lock the enrollment's sections in a fixed order, so two approvals that share a
    -- section run one after the other (decision 4).
    PERFORM 1
    FROM public.sections s
    WHERE s.section_id IN (SELECT ei.section_id FROM public.enrollment_items ei
                           WHERE ei.enrollment_id = OLD.enrollment_id)
    ORDER BY s.section_id
    FOR NO KEY UPDATE OF s;

    SELECT pg_catalog.count(*),
           pg_catalog.string_agg(pg_catalog.format('%s (section %s, term %s)', s.section_code, s.section_id, s.term_id),
                                 ', ' ORDER BY s.section_id) FILTER (WHERE s.term_id IS DISTINCT FROM NEW.term_id)
      INTO v_total, v_wrong
    FROM public.enrollment_items ei
    JOIN public.sections s ON s.section_id = ei.section_id
    WHERE ei.enrollment_id = OLD.enrollment_id;

    IF v_total = 0 THEN
      RAISE EXCEPTION 'no items: enrollment % cannot be approved because it has no sections', OLD.enrollment_id
        USING ERRCODE = 'P0001',
              HINT = 'The student adds at least one section of the term first.';
    END IF;

    IF v_wrong IS NOT NULL THEN
      RAISE EXCEPTION 'wrong term: enrollment % cannot be approved because a section belongs to another term', OLD.enrollment_id
        USING ERRCODE = 'P0001',
              DETAIL = pg_catalog.format('sections of another term: %s', v_wrong),
              HINT = 'Every section must belong to the enrollment''s term.';
    END IF;

    -- Seats taken = items of OTHER Approved enrollments in the same section.
    SELECT pg_catalog.count(*),
           pg_catalog.string_agg(pg_catalog.format('%s (section %s, %s of %s seats taken)',
                                                   s.section_code, s.section_id, x.taken, s.capacity),
                                 ', ' ORDER BY s.section_id)
      INTO v_nfull, v_full
    FROM public.enrollment_items ei
    JOIN public.sections s ON s.section_id = ei.section_id
    CROSS JOIN LATERAL (
      SELECT pg_catalog.count(*) AS taken
      FROM public.enrollment_items oi
      JOIN public.enrollments oe ON oe.enrollment_id = oi.enrollment_id
      WHERE oi.section_id = s.section_id
        AND oe.status::text = 'Approved'
        AND oe.enrollment_id <> OLD.enrollment_id) x
    WHERE ei.enrollment_id = OLD.enrollment_id
      AND x.taken >= s.capacity;

    IF v_nfull > 0 THEN
      RAISE EXCEPTION 'section full: enrollment % cannot be approved because % of its % sections have no seat left', OLD.enrollment_id, v_nfull, v_total
        USING ERRCODE = 'P0001',
              DETAIL = pg_catalog.format('full sections: %s', v_full),
              HINT = 'Ask the student to pick another section, or have the Admin raise the section capacity.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

REVOKE EXECUTE ON FUNCTION private.require_enrollment_rules() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.require_enrollment_rules() TO authenticated;

-- ------------------------------------------
-- 4. Trigger function on enrollment_items
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.require_enrollment_item_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid      uuid := auth.uid();
  v_student  uuid;
  v_term     bigint;
  v_status   text;
  v_sec_term bigint;
  v_sec_code text;
  v_dup      bigint;
BEGIN
  IF TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW'
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'enrollment_items' THEN
    RAISE EXCEPTION 'private.require_enrollment_item_rules must be a BEFORE INSERT OR UPDATE OR DELETE FOR EACH ROW trigger on public.enrollment_items';
  END IF;

  -- UPDATE / DELETE: the item's current enrollment must be Pending. (RLS USING has already
  -- limited the rows: a student reaches only items of their own Pending enrollment.)
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    SELECT e.status::text INTO v_status
    FROM public.enrollments e
    WHERE e.enrollment_id = OLD.enrollment_id
    FOR NO KEY UPDATE OF e;
    IF FOUND AND v_status <> 'Pending' THEN
      RAISE EXCEPTION 'enrollment locked: enrollment % is % and its sections can no longer be changed', OLD.enrollment_id, v_status
        USING ERRCODE = 'P0001',
              HINT = 'Sections can be added or removed only while the enrollment is Pending.';
    END IF;
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    IF NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id THEN
      RAISE EXCEPTION 'enrollment locked: a section of enrollment % cannot be moved to another enrollment', OLD.enrollment_id
        USING ERRCODE = 'P0001',
              HINT = 'Remove the item and add a new one to the other enrollment.';
    END IF;
  END IF;

  -- INSERT / UPDATE: the (new) enrollment, locked so an approval cannot run in between.
  SELECT e.student_id, e.term_id, e.status::text INTO v_student, v_term, v_status
  FROM public.enrollments e
  WHERE e.enrollment_id = NEW.enrollment_id
  FOR NO KEY UPDATE OF e;
  IF NOT FOUND THEN
    RETURN NEW;  -- the foreign key reports the missing enrollment
  END IF;

  -- Not the caller's enrollment: no detail, RLS decides (decision 7).
  IF v_uid IS NOT NULL AND v_student IS DISTINCT FROM v_uid
     AND private.current_role_name() IS DISTINCT FROM 'Registrar' THEN
    RETURN NEW;
  END IF;

  IF v_status <> 'Pending' THEN
    RAISE EXCEPTION 'enrollment locked: enrollment % is % and its sections can no longer be changed', NEW.enrollment_id, v_status
      USING ERRCODE = 'P0001',
            HINT = 'Sections can be added or removed only while the enrollment is Pending.';
  END IF;

  SELECT s.term_id, s.section_code::text INTO v_sec_term, v_sec_code
  FROM public.sections s
  WHERE s.section_id = NEW.section_id;
  IF NOT FOUND THEN
    RETURN NEW;  -- the foreign key reports the missing section
  END IF;

  IF v_sec_term IS DISTINCT FROM v_term THEN
    RAISE EXCEPTION 'wrong term: section % (%) belongs to term %, enrollment % is for term %', NEW.section_id, v_sec_code, v_sec_term, NEW.enrollment_id, v_term
      USING ERRCODE = 'P0001',
            HINT = 'Pick a section of the enrollment''s term.';
  END IF;

  SELECT ei.enrollment_item_id INTO v_dup
  FROM public.enrollment_items ei
  WHERE ei.enrollment_id = NEW.enrollment_id AND ei.section_id = NEW.section_id
    AND ei.enrollment_item_id <> NEW.enrollment_item_id
  LIMIT 1;
  IF v_dup IS NOT NULL THEN
    RAISE EXCEPTION 'duplicate section: section % (%) is already in enrollment %', NEW.section_id, v_sec_code, NEW.enrollment_id
      USING ERRCODE = 'P0001',
            DETAIL = pg_catalog.format('existing item: %s', v_dup),
            HINT = 'Each section can be added once.';
  END IF;

  RETURN NEW;
END
$function$;

REVOKE EXECUTE ON FUNCTION private.require_enrollment_item_rules() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.require_enrollment_item_rules() TO authenticated;

-- ------------------------------------------
-- 5. The triggers (see header, decision 10, for the firing order)
-- ------------------------------------------
DROP TRIGGER IF EXISTS require_enrollment_rules ON public.enrollments;
CREATE TRIGGER require_enrollment_rules BEFORE INSERT OR UPDATE ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION private.require_enrollment_rules();

DROP TRIGGER IF EXISTS require_enrollment_item_rules ON public.enrollment_items;
CREATE TRIGGER require_enrollment_item_rules BEFORE INSERT OR UPDATE OR DELETE ON public.enrollment_items
  FOR EACH ROW EXECUTE FUNCTION private.require_enrollment_item_rules();

-- ------------------------------------------
-- 6. Grants on the 2 tables (authenticated only; rebuilt from nothing)
-- ------------------------------------------
REVOKE ALL ON public.enrollments, public.enrollment_items FROM PUBLIC, anon, authenticated;

-- Reads. RLS decides the rows: enrollments_read / enrollment_items_read = own student, or
-- the Registrar (everything). SELECT is also needed for UPDATE ... WHERE and RETURNING.
GRANT SELECT ON public.enrollments, public.enrollment_items TO authenticated;

-- Student submits. Policy enrollments_student_submit: only a Student, only for themself,
-- status Pending, reviewed_* NULL. status, reviewed_*, remarks and submitted_at are left
-- out: status keeps DEFAULT 'Pending', submitted_at keeps DEFAULT now() (no back-dating).
-- enrollment_id is an identity column (GENERATED ALWAYS, no sequence grant needed).
GRANT INSERT (student_id, term_id, year_level) ON public.enrollments TO authenticated;

-- Registrar decides. Policy enrollments_registrar_review: only the Registrar, reviewed_by
-- = the caller. The trigger overwrites reviewed_by / reviewed_at (decisions 2 and 3).
-- student_id / term_id are also locked by guard_immutable_columns. No DELETE.
GRANT UPDATE (status, reviewed_by, reviewed_at, remarks) ON public.enrollments TO authenticated;

-- Student picks sections. Policy enrollment_items_student_add: own Pending enrollment.
GRANT INSERT (enrollment_id, section_id) ON public.enrollment_items TO authenticated;

-- Student removes a section. Policy enrollment_items_student_remove: own Pending
-- enrollment (decision 11; drop this line if the PM decides against).
GRANT DELETE ON public.enrollment_items TO authenticated;

-- ------------------------------------------
-- 7. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_fn_e regprocedure := pg_catalog.to_regprocedure('private.require_enrollment_rules()');
  v_fn_i regprocedure := pg_catalog.to_regprocedure('private.require_enrollment_item_rules()');
  v_bad  text;
BEGIN
  IF v_fn_e IS NULL OR v_fn_i IS NULL THEN
    RAISE EXCEPTION 'enrollment_rules: function(s) not created; rolled back';
  END IF;

  -- a) Functions: SECURITY DEFINER, empty search_path; grants PUBLIC none, anon none,
  --    authenticated EXECUTE.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
             WHERE p.oid IN (v_fn_e, v_fn_i)
               AND NOT (p.prosecdef AND p.proconfig && ARRAY['search_path=""', 'search_path='''''])) THEN
    RAISE EXCEPTION 'enrollment_rules: a function is not SECURITY DEFINER with an empty search_path; rolled back';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
             WHERE p.oid IN (v_fn_e, v_fn_i)
               AND (p.proacl IS NULL
                    OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
                    OR pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                    OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION 'enrollment_rules: function grants are not PUBLIC none / anon none / authenticated EXECUTE; rolled back';
  END IF;

  -- b) Triggers: enrollments BEFORE INSERT OR UPDATE ROW (1 + 2 + 4 + 16 = 23),
  --    enrollment_items BEFORE INSERT OR DELETE OR UPDATE ROW (1 + 2 + 4 + 8 + 16 = 31),
  --    both enabled (origin).
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.enrollments'::pg_catalog.regclass
                   AND t.tgname = 'require_enrollment_rules' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn_e AND t.tgtype = 23 AND t.tgenabled = 'O')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.enrollment_items'::pg_catalog.regclass
                      AND t.tgname = 'require_enrollment_item_rules' AND NOT t.tgisinternal
                      AND t.tgfoid = v_fn_i AND t.tgtype = 31 AND t.tgenabled = 'O') THEN
    RAISE EXCEPTION 'enrollment_rules: trigger require_enrollment_rules / require_enrollment_item_rules missing or not the expected type; rolled back';
  END IF;

  -- c) BEFORE triggers in firing order.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.enrollments'::pg_catalog.regclass AND NOT t.tgisinternal
    AND (t.tgtype::integer & 2) = 2;
  IF v_bad IS DISTINCT FROM 'guard_immutable_columns, require_enrollment_rules' THEN
    RAISE EXCEPTION 'enrollment_rules: BEFORE triggers on enrollments are [%]; rolled back', v_bad;
  END IF;
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.enrollment_items'::pg_catalog.regclass AND NOT t.tgisinternal
    AND (t.tgtype::integer & 2) = 2;
  IF v_bad IS DISTINCT FROM 'require_enrollment_item_rules' THEN
    RAISE EXCEPTION 'enrollment_rules: BEFORE triggers on enrollment_items are [%]; rolled back', v_bad;
  END IF;

  -- d) Both unique keys exist.
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('enrollments', ARRAY['student_id', 'term_id']),
               ('enrollment_items', ARRAY['enrollment_id', 'section_id'])) AS e(t, cols)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    WHERE i.indrelid = ('public.' || e.t)::pg_catalog.regclass AND i.indisunique
      AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts = 2
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
             FROM pg_catalog.unnest(i.indkey::int2[]) AS k(attnum)
             JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum) = e.cols);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: unique key missing on %; rolled back', v_bad;
  END IF;

  -- e) anon: no privilege of any kind on the 2 tables. authenticated: SELECT, no
  --    table-level INSERT / UPDATE, DELETE on enrollment_items only, no TRUNCATE /
  --    REFERENCES / TRIGGER / MAINTAIN.
  IF has_table_privilege('anon', 'public.enrollments', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR has_table_privilege('anon', 'public.enrollment_items', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR has_any_column_privilege('anon', 'public.enrollments', 'SELECT, INSERT, UPDATE, REFERENCES')
     OR has_any_column_privilege('anon', 'public.enrollment_items', 'SELECT, INSERT, UPDATE, REFERENCES') THEN
    RAISE EXCEPTION 'enrollment_rules: anon still has a privilege on enrollments / enrollment_items; rolled back';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.enrollments', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.enrollment_items', 'SELECT')
     OR has_table_privilege('authenticated', 'public.enrollments', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR has_table_privilege('authenticated', 'public.enrollment_items', 'INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR NOT has_table_privilege('authenticated', 'public.enrollment_items', 'DELETE') THEN
    RAISE EXCEPTION 'enrollment_rules: table-level grants for authenticated are not SELECT (+ DELETE on enrollment_items); rolled back';
  END IF;

  -- f) The column grants of authenticated are exactly the 9 above.
  WITH expected(t, col, priv) AS (VALUES
    ('enrollments', 'student_id', 'INSERT'), ('enrollments', 'term_id', 'INSERT'),
    ('enrollments', 'year_level', 'INSERT'),
    ('enrollments', 'status', 'UPDATE'), ('enrollments', 'reviewed_by', 'UPDATE'),
    ('enrollments', 'reviewed_at', 'UPDATE'), ('enrollments', 'remarks', 'UPDATE'),
    ('enrollment_items', 'enrollment_id', 'INSERT'), ('enrollment_items', 'section_id', 'INSERT')),
  live AS (
    SELECT c.relname::text AS t, a.attname::text AS col, x.privilege_type::text AS priv
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
    WHERE c.oid IN ('public.enrollments'::pg_catalog.regclass, 'public.enrollment_items'::pg_catalog.regclass)
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
      AND x.grantee = 'authenticated'::regrole),
  diff AS (
    (SELECT 'missing ' || t || '.' || col || ' ' || priv AS d FROM (SELECT * FROM expected EXCEPT SELECT * FROM live) m)
    UNION ALL
    (SELECT 'unexpected ' || t || '.' || col || ' ' || priv FROM (SELECT * FROM live EXCEPT SELECT * FROM expected) x))
  SELECT string_agg(d, '; ') INTO v_bad FROM diff;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'enrollment_rules: column grants differ: %; rolled back', v_bad;
  END IF;
END
$$;

-- Ask PostgREST to reload its schema cache (sent when the transaction commits).
NOTIFY pgrst, 'reload schema';

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state before this file)
-- ------------------------------------------
-- Removes both triggers and functions and gives the 2 tables back the grants they had
-- after hardening2.sql section C (authenticated SELECT only, nothing for anon). Compare
-- with the saved diagnostic (c) afterwards. The unique keys: drop them ONLY if the saved
-- diagnostic (b) showed that they did not exist before (then this file created them under
-- these names). Rows written while the rules existed stay; their audit rows stay.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS require_enrollment_rules ON public.enrollments;
-- DROP TRIGGER IF EXISTS require_enrollment_item_rules ON public.enrollment_items;
-- DROP FUNCTION IF EXISTS private.require_enrollment_rules();
-- DROP FUNCTION IF EXISTS private.require_enrollment_item_rules();
-- REVOKE ALL ON public.enrollments, public.enrollment_items FROM PUBLIC, anon, authenticated;
-- GRANT SELECT ON public.enrollments, public.enrollment_items TO authenticated;
-- -- only if diagnostic (b) BEFORE showed no such key:
-- -- ALTER TABLE public.enrollments DROP CONSTRAINT IF EXISTS uq_enrollments_student_term;
-- -- ALTER TABLE public.enrollment_items DROP CONSTRAINT IF EXISTS uq_enrollment_items_enrollment_section;
-- NOTIFY pgrst, 'reload schema';
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: triggers on enrollments and enrollment_items in firing order.
--    After: enrollments guard_immutable_columns, require_enrollment_rules (BEFORE),
--    audit_log (AFTER); enrollment_items require_enrollment_item_rules (BEFORE), audit_log
--    (AFTER).
-- select t.tgrelid::regclass as table_name, t.tgname,
--        case when (t.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
--        t.tgenabled, t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t
-- where t.tgrelid in ('public.enrollments'::regclass, 'public.enrollment_items'::regclass)
--   and not t.tgisinternal
-- order by 1, case when (t.tgtype::int & 2) = 2 then 0 else 1 end, t.tgname;
--
-- b) BEFORE and AFTER: every CHECK, UNIQUE, PRIMARY KEY and FOREIGN KEY constraint and every
--    unique index on the tables the rules touch. The live database has CHECK constraints
--    that are not in schema.sql (for example ck_clearances_approval); read these before
--    changing test data or the triggers.
-- select c.conrelid::regclass as table_name, c.conname, c.contype, pg_get_constraintdef(c.oid) as definition
-- from pg_constraint c
-- where c.conrelid in ('public.enrollments'::regclass, 'public.enrollment_items'::regclass,
--                      'public.sections'::regclass, 'public.terms'::regclass)
-- union all
-- select i.indrelid::regclass, ic.relname, 'index', pg_get_indexdef(i.indexrelid)
-- from pg_index i join pg_class ic on ic.oid = i.indexrelid
-- where i.indisunique and not i.indisprimary
--   and i.indrelid in ('public.enrollments'::regclass, 'public.enrollment_items'::regclass,
--                      'public.sections'::regclass, 'public.terms'::regclass)
-- order by 1, 3, 2;
--
-- c) BEFORE and AFTER: exact ACLs and column ACLs of the 2 tables. Save the "before"
--    output; the ROLLBACK must return to it.
-- select c.relname, c.relacl::text as acl,
--        (select string_agg(a.attname || '=' || a.attacl::text, '; ' order by a.attnum)
--           from pg_attribute a
--          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attacl is not null) as column_acls
-- from pg_class c
-- where c.oid in ('public.enrollments'::regclass, 'public.enrollment_items'::regclass)
-- order by 1;
--
-- d) The policies the grants rely on (compare with check 1d):
-- select tablename, policyname, cmd, permissive, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'public' and tablename in ('enrollments', 'enrollment_items')
-- order by 1, 2;
--
-- e) BEFORE and AFTER: existing rows that the new rules would refuse (not changed by this
--    file, no back-fill). Every row is one finding.
-- select 'two enrollments in one term' as finding, e.student_id::text as who, e.term_id::text as what
-- from public.enrollments e group by e.student_id, e.term_id having count(*) > 1
-- union all
-- select 'same section twice', i.enrollment_id::text, i.section_id::text
-- from public.enrollment_items i group by i.enrollment_id, i.section_id having count(*) > 1
-- union all
-- select 'section of another term', i.enrollment_id::text, 'section ' || s.section_id || ' term ' || s.term_id || ' <> ' || e.term_id
-- from public.enrollment_items i
-- join public.enrollments e on e.enrollment_id = i.enrollment_id
-- join public.sections s on s.section_id = i.section_id
-- where s.term_id <> e.term_id
-- union all
-- select 'over capacity (Approved)', s.section_id::text, count(*) || ' of ' || s.capacity
-- from public.sections s
-- join public.enrollment_items i on i.section_id = s.section_id
-- join public.enrollments e on e.enrollment_id = i.enrollment_id and e.status = 'Approved'
-- group by s.section_id, s.capacity having count(*) > s.capacity
-- union all
-- select 'decided without reviewer', e.enrollment_id::text, e.status || ' ' || coalesce(e.reviewed_by::text, 'NULL') || ' ' || coalesce(e.reviewed_at::text, 'NULL')
-- from public.enrollments e
-- where e.status <> 'Pending' and (e.reviewed_by is null or e.reviewed_at is null)
-- union all
-- select 'Pending but reviewed', e.enrollment_id::text, coalesce(e.reviewed_by::text, 'NULL') || ' ' || coalesce(e.reviewed_at::text, 'NULL')
-- from public.enrollments e
-- where e.status = 'Pending' and (e.reviewed_by is not null or e.reviewed_at is not null)
-- union all
-- select 'Approved without sections', e.enrollment_id::text, e.term_id::text
-- from public.enrollments e
-- where e.status = 'Approved' and not exists (select 1 from public.enrollment_items i where i.enrollment_id = e.enrollment_id)
-- order by 1, 2, 3;
--
-- f) Seats per section (owner view; the student cannot count other students' items).
-- select s.section_id, s.term_id, s.section_code, s.capacity,
--        count(*) filter (where e.status = 'Approved') as approved,
--        count(*) filter (where e.status = 'Pending') as pending,
--        s.capacity - count(*) filter (where e.status = 'Approved') as seats_left
-- from public.sections s
-- left join public.enrollment_items i on i.section_id = s.section_id
-- left join public.enrollments e on e.enrollment_id = i.enrollment_id
-- group by s.section_id, s.term_id, s.section_code, s.capacity
-- order by s.term_id, s.section_code;
--
-- g) AFTER: the latest enrollment changes in the audit log.
-- select l.log_id, l.created_at, l.table_name, l.action, l.record_id, l.actor_id,
--        l.old_data ->> 'status' as old_status, l.new_data ->> 'status' as new_status,
--        l.new_data ->> 'reviewed_by' as reviewed_by, l.new_data ->> 'reviewed_at' as reviewed_at
-- from public.audit_logs l
-- where l.table_name in ('enrollments', 'enrollment_items')
-- order by l.log_id desc limit 20;


-- ==========================================
-- NOTES FOR THE PM (decisions, not done here)
-- ==========================================
-- - Rejected is final and there is one enrollment per student per term, so a rejected
--   student cannot submit again for that term. Alternatives: allow Rejected -> Pending
--   (the student re-submits) or let the Registrar delete a rejected enrollment. Needs a
--   decision; this file keeps "final".
-- - DELETE on enrollment_items for students (decision 11): keep or drop.
-- - Narrow the Registrar grant to UPDATE (status, remarks) (decision 3): the database sets
--   reviewed_by / reviewed_at anyway.
-- - Current term only for new enrollments; one section per subject; remarks required on
--   Rejected: none enforced here.
-- - The Admin cannot read enrollments (enrollments_read: own student or Registrar). An
--   Admin dashboard count (#105) needs a policy change or a definer function.
-- - Resetting demo data (e.g. Ben's Pending enrollment) on an Approved / Rejected row needs
--   the trigger disabled by the owner for that change.
