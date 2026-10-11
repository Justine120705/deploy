-- ==========================================
-- FINANCE ITEM CLEARS AUTOMATICALLY WHEN THE CHARGES ARE SETTLED (GitHub issue #62, issue 23)
-- ==========================================
-- REQ-CSH-03, DFD process 4.0 (dashed trigger arrow), Activity Diagram. Sprint 3 plan item
-- S3-3. Runs AFTER hardening.sql, hardening2.sql (A, B, C), views_extend.sql,
-- grants_clearance.sql and trigger_dept_approval.sql (all live since 2026-10-11).
--
-- WHAT IT DOES
--   When every charge of a student for a term is settled (status 'Cleared' or 'Waived'),
--   the Financial item (departments.department_type = 'Financial', the Cashier's Office)
--   of that student's clearance for that term is cleared automatically:
--   cleared_at = now(), cleared_by = the Cashier who tagged the last charge.
--   One trigger function, private.finance_autoclear(), used by two triggers:
--     - finance_autoclear            AFTER INSERT OR UPDATE OF status, student_id, term_id
--                                    ON public.charges, WHEN NEW.status is settled
--                                    (the Cashier tags a charge);
--     - finance_autoclear_on_create  AFTER INSERT ON public.clearance_items,
--                                    WHEN NEW.cleared_at IS NULL (the clearance is created
--                                    after the charges were already settled).
--
-- DESIGN DECISIONS
--   1. "Settled" = charges.status IN ('Cleared', 'Waived'). These are the only values
--      besides 'Unpaid' (CHECK constraint in schema.sql; safety check (c) stops if the
--      live CHECK differs). Amounts and payments are NOT compared: the status is the
--      Cashier's decision (a Waived charge can be partly paid; the seed has 20,000 of
--      45,000 collected). One charge that is not settled (today only 'Unpaid') keeps the
--      item pending.
--   2. Zero charges: NOT auto-cleared. A student with no charge for the term may simply
--      not have been billed yet; clearing the Cashier's item then would be a silent
--      "nothing owed" decision nobody made. The Cashier clears such an item by hand (the
--      normal flow, clearance_items_dept_update). Only charges of the SAME term as the
--      clearance count.
--   3. Which writes on charges fire it: INSERT, and UPDATE OF status, student_id, term_id,
--      only when the NEW status is settled (trigger WHEN clause; an Unpaid write never
--      calls the function). amount, due_date and fee_type_id do not change whether the
--      set is settled, so they are not in the column list (an UPDATE that sets amount AND
--      status still fires, because status is in its SET list).
--      - The evaluation is state-based: re-saving the status of a settled charge (for
--        example "set status = status") evaluates again. That is how the Cashier finishes
--        a case that was skipped (decision 6) without any extra tool.
--      - DELETE is not included: authenticated has no DELETE on charges and there is no
--        DELETE policy; a delete is an owner correction in the SQL editor, after which the
--        Cashier clears by hand or re-saves a charge (diagnostic (c) lists the candidates).
--      - student_id / term_id can only be changed by the table owner (column grants and
--        guard_immutable_columns); only the NEW student and term are evaluated, the old
--        ones are not (diagnostic (c)).
--   4. Who is recorded (cleared_by):
--      - Charge path: auth.uid(). In Supabase auth.uid() reads the request's JWT claims
--        (the GUCs request.jwt.claim.sub / request.jwt.claims), not current_user, so
--        inside this SECURITY DEFINER function (current_user = postgres) it is still the
--        API caller who tagged the charge. It is used only if it is an ACTIVE profile with
--        the role 'Cashier' (the only role charges_cashier_update lets write charges).
--        For postgres in the SQL editor, the server role or any call without a user JWT,
--        auth.uid() is NULL: then NOTHING is auto-cleared. Reason: hardening.sql finding 1
--        ("who did it" is never NULL) and the FK on cleared_by; an SQL-editor fix is not a
--        Cashier decision. The Cashier then clears by hand or re-saves the status.
--      - Creation path: the caller is the student requesting the clearance, who must not
--        appear as the person who cleared the Cashier's item. cleared_by is the actor of
--        the NEWEST audit_logs row on public.charges for that student and term in which a
--        charge became settled (INSERT with a settled status, or UPDATE that changed the
--        status to a settled value). That actor must still be an active Cashier; if it is
--        NULL (SQL editor, seed) or not an active Cashier, nothing is auto-cleared. This
--        relies on the audit trigger on charges (hardening2.sql B, append-only), which
--        safety check (g) requires to be present and enabled. No audit row (charges set
--        before 2026-10-10, seed data) = no auto-clear.
--   5. The creation path is a SMALL SEPARATE AFTER INSERT trigger on clearance_items, not
--      a rewrite of private.create_clearance_items():
--      - create_clearance_items() is the live-exported function (private_functions.sql,
--        verbatim) behind trg_clearances_create_items; changing it would mix two concerns
--        and touch the student's request path for every department;
--      - a trigger on clearance_items covers EVERY way an item is created (that trigger,
--        owner inserts, a future flow), not only that one function;
--      - AFTER (not BEFORE) INSERT, and the clear is a separate UPDATE: the same UPDATE as
--        the charge path, so require_no_active_hold (issue 22) checks it a second time and
--        audit_log records it as an UPDATE (old cleared_at NULL), exactly like a manual
--        clear; the INSERT audit row stays the "created pending" record.
--      - WHEN (NEW.cleared_at IS NULL): an item inserted already cleared (owner, seed) is
--        left alone. The Financial check is inside the function (a WHEN clause cannot read
--        departments).
--   6. Active Financial hold (interaction with require_no_active_hold, issue 22): the
--      auto-clear SKIPS the item (it stays pending) when the student has an active hold
--      (lifted_at IS NULL) of the item's department. Without this, require_no_active_hold
--      would RAISE inside the Cashier's charge update (or the student's clearance
--      request) and abort it. So tagging a charge and requesting a clearance never fail
--      because of this trigger. The UPDATE has the hold test in its WHERE clause; a hold
--      committed by another transaction in the instant between that test and
--      require_no_active_hold's own query would still make require_no_active_hold raise,
--      so that one error (SQLSTATE P0001, message "active hold:%") is caught and the item
--      stays pending; every other error is re-raised. After the hold is lifted the Cashier
--      clears by hand or re-saves a charge status (decision 3).
--   7. Already-cleared Financial item: never overwritten (the UPDATE only matches
--      cleared_at IS NULL), so cleared_at / cleared_by of a manual or earlier clear stay.
--      remarks are never touched.
--   8. A charge goes back to 'Unpaid': NOT auto-un-cleared (the WHEN clause does not even
--      call the function). What hardening.sql blocks, exactly: nothing on charges (the
--      Cashier may set status back to 'Unpaid': charges_cashier_update checks the role
--      only and status is in the column grant); on clearance_items every API update must
--      set cleared_by = the caller, so "un-clearing" by setting cleared_by NULL is
--      rejected, while cleared_at NULL with cleared_by = the caller is still allowed
--      (TC-47). Reasons not to auto-un-clear: the Registrar may already have approved the
--      clearance on the strength of that item; an automatic un-clear would have to write
--      a cleared_by that is not a person's decision (hardening.sql finding 1); a revert is
--      often a correction, which should be looked at by a person; and the audit trail
--      stays simple (one clear, made by a Cashier). The Cashier decides: un-clear by hand
--      (cleared_at NULL, cleared_by = self) if needed. Diagnostic (d) lists cleared
--      Financial items whose student now has an Unpaid charge for that term.
--   9. SECURITY DEFINER, SET search_path TO '', every name schema-qualified. The trigger
--      runs inside the caller's statement, and RLS would hide what it needs: the Cashier
--      reads no academic_holds and no audit_logs, a student reads no audit_logs and only
--      their own charges. As SECURITY DEFINER (owner postgres, the owner of the tables, no
--      FORCE RLS; safety check (i)) it sees every row. The only write it makes is
--      cleared_at / cleared_by on pending Financial items of the student and term of the
--      row the caller was already allowed to write; it returns nothing to the caller.
--      guard_immutable_columns lets the nested UPDATE through (it only restricts
--      current_user authenticated / anon; inside the definer it is postgres), and the
--      nested UPDATE only changes cleared_at and cleared_by anyway.
--  10. Firing order and recursion (PostgreSQL: all BEFORE ROW triggers by name, then RLS
--      WITH CHECK and constraints, then the write, then the AFTER ROW triggers by name,
--      which are queued and fire at the end of the statement):
--        public.charges (Cashier's UPDATE):
--          guard_immutable_columns (BEFORE) -> RLS WITH CHECK -> write
--          -> audit_log (AFTER) -> finance_autoclear (AFTER)
--             -> nested UPDATE public.clearance_items:
--                guard_immutable_columns (BEFORE) -> require_no_active_hold (BEFORE)
--                -> write -> audit_log (AFTER)
--        public.clearance_items (INSERT, e.g. from trg_clearances_create_items):
--          write -> audit_log (AFTER) -> finance_autoclear_on_create (AFTER)
--             -> nested UPDATE of that same row (as above)
--      "audit_log" sorts before "finance_autoclear..." ('a' < 'f'), so the charge's (or
--      the item's INSERT) audit row is always written before the item's UPDATE audit row.
--      A rejected charge update (guard, RLS) stops before the write, so nothing fires.
--      Statement-level effect: a multi-row charge UPDATE queues its AFTER triggers until
--      all rows are written, so the first queued call already sees every new status.
--      No recursion: the nested UPDATE on clearance_items fires no INSERT trigger and no
--      trigger on charges; finance_autoclear_on_create is INSERT only. The audit row of
--      the item's UPDATE has actor_id = auth.uid(): the Cashier on the charge path, the
--      requesting student on the creation path (new_data.cleared_by is the Cashier).
--  11. Grants: like the other trigger functions (hardening2.sql section C,
--      trigger_dept_approval.sql): no PUBLIC and no anon EXECUTE, explicit EXECUTE for
--      authenticated. A trigger function cannot be called directly ("trigger functions can
--      only be called as triggers"). No table grant changes: the Cashier keeps UPDATE
--      (amount, due_date, status) on charges, nobody gets INSERT on charges or
--      clearance_items; the definer function does the clearance_items update.
--  12. No back-fill: items that are pending today although their charges are all settled
--      stay pending (the change cannot know who should be recorded). Diagnostic (c) lists
--      them; the Cashier clears them by hand or re-saves a charge status.
--
-- KNOWN LIMITS (not done here, on purpose)
--   - Race: two Cashiers tagging the last two Unpaid charges of the same student in two
--     transactions that overlap each see the other charge still Unpaid (READ COMMITTED),
--     so neither auto-clears and the item stays pending (fail safe). Locking all of the
--     student's charges inside the trigger would risk deadlocks between those two
--     transactions; not worth it for one cashier's office. Diagnostic (c) lists such
--     items; re-saving a charge status clears them.
--   - The creation path reads audit_logs without an index on (table_name, record_id); the
--     table is small and the lookup runs once per created clearance. Add an index in a
--     separate change if it ever grows.
--   - More than one Financial department: every pending Financial item of the clearance
--     is auto-cleared by the same rule (the seed has exactly one, CSH).
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (CREATE OR REPLACE, DROP TRIGGER IF EXISTS, idempotent grants).
-- CREATE TRIGGER takes a short lock on charges and on clearance_items; well under a second.
--   - Before running: run diagnostics (a), (c) and (d) at the bottom and SAVE the output.
--   - Rehearse first: docs/database/trigger_finance_autoclear_rehearsal.sql runs this
--     change and all tests (TC-49 to TC-61) in ONE rolled-back transaction with one result
--     row.
-- Test afterwards: Part K of docs/issue-12-testing-guide.md (TC-49 to TC-61, SQL in
-- docs/database/trigger_finance_autoclear_test.sql, or the test part of the rehearsal
-- file on its own), then TC-37 (Part I), Part J and docs/database/regression_after_grants.sql
-- again.
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: RUN on the live database on 2026-10-11 after a rolled-back rehearsal; TC-49 to TC-61 pass live.
-- has been run.


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.finance_autoclear()');
BEGIN
  -- a) The tables exist.
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('charges'), ('clearance_items'), ('clearances'), ('departments'),
               ('academic_holds'), ('audit_logs'), ('profiles'), ('roles')) AS e(t)
  WHERE pg_catalog.to_regclass('public.' || e.t) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: missing table(s) public.%; stop', v_bad;
  END IF;

  -- b) The columns the function reads or writes exist with the expected types.
  SELECT string_agg(e.t || '.' || e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('charges', 'charge_id', 'bigint'),
    ('charges', 'student_id', 'uuid'),
    ('charges', 'term_id', 'bigint'),
    ('charges', 'status', 'character varying'),
    ('clearance_items', 'clearance_item_id', 'bigint'),
    ('clearance_items', 'clearance_id', 'bigint'),
    ('clearance_items', 'department_id', 'bigint'),
    ('clearance_items', 'cleared_at', 'timestamp with time zone'),
    ('clearance_items', 'cleared_by', 'uuid'),
    ('clearances', 'clearance_id', 'bigint'),
    ('clearances', 'student_id', 'uuid'),
    ('clearances', 'term_id', 'bigint'),
    ('departments', 'department_id', 'bigint'),
    ('departments', 'department_type', 'character varying'),
    ('academic_holds', 'student_id', 'uuid'),
    ('academic_holds', 'department_id', 'bigint'),
    ('academic_holds', 'lifted_at', 'timestamp with time zone'),
    ('audit_logs', 'log_id', 'bigint'),
    ('audit_logs', 'actor_id', 'uuid'),
    ('audit_logs', 'action', 'character varying'),
    ('audit_logs', 'table_name', 'character varying'),
    ('audit_logs', 'record_id', 'character varying'),
    ('audit_logs', 'old_data', 'jsonb'),
    ('audit_logs', 'new_data', 'jsonb'),
    ('profiles', 'profile_id', 'uuid'),
    ('profiles', 'role_id', 'smallint'),
    ('profiles', 'is_active', 'boolean'),
    ('roles', 'role_id', 'smallint'),
    ('roles', 'role_name', 'character varying')) AS e(t, col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.t)
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: missing column or other type: %; stop', v_bad;
  END IF;

  -- c) The data the rule depends on: the status CHECK on charges allows exactly Unpaid,
  --    Cleared and Waived (schema.sql), a Financial department and the role Cashier exist.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                 WHERE k.conrelid = 'public.charges'::pg_catalog.regclass AND k.contype = 'c'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%status%'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%''Unpaid''%'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%''Cleared''%'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%''Waived''%')
     OR EXISTS (SELECT 1 FROM public.charges ch
                WHERE ch.status::text NOT IN ('Unpaid', 'Cleared', 'Waived')) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: charges.status is not limited to Unpaid / Cleared / Waived; stop and review the rule';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments d WHERE d.department_type = 'Financial') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: no department with department_type Financial; stop';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles r WHERE r.role_name = 'Cashier') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: no role named Cashier; stop';
  END IF;

  -- d) auth.uid() exists and returns uuid (it is how the Cashier is recognised).
  IF pg_catalog.to_regprocedure('auth.uid()') IS NULL
     OR (SELECT p.prorettype FROM pg_catalog.pg_proc p
         WHERE p.oid = pg_catalog.to_regprocedure('auth.uid()')) <> 'pg_catalog.uuid'::pg_catalog.regtype THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: auth.uid() missing or not returning uuid; stop';
  END IF;

  -- e) The function is absent (first run) or is this file's trigger function (re-run).
  IF v_fn IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
                          <> 'pg_catalog.trigger'::pg_catalog.regtype THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: private.finance_autoclear() exists and is not a trigger function; stop and review';
  END IF;

  -- f) No trigger named finance_autoclear / finance_autoclear_on_create anywhere calls a
  --    different function.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname IN ('finance_autoclear', 'finance_autoclear_on_create') AND NOT t.tgisinternal
               AND (v_fn IS NULL OR t.tgfoid <> v_fn)) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: a different trigger named finance_autoclear(_on_create) already exists; stop and review';
  END IF;

  -- g) The triggers on charges are exactly guard_immutable_columns (BEFORE UPDATE,
  --    hardening.sql) and audit_log (AFTER, hardening2.sql B; the creation path reads its
  --    rows), both enabled, plus this file's trigger on a re-run.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'audit_log'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'finance_autoclear' AND v_fn IS NOT NULL AND t.tgfoid = v_fn));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: unexpected trigger(s) on charges: %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('audit_log')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger(s) missing or disabled on charges: %; stop', v_bad;
  END IF;

  -- h) The triggers on clearance_items are exactly guard_immutable_columns (hardening.sql),
  --    require_no_active_hold (trigger_dept_approval.sql) and audit_log (hardening2.sql B),
  --    all enabled, plus this file's trigger on a re-run. On clearances,
  --    trg_clearances_create_items (calls private.create_clearance_items()) is enabled.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'require_no_active_hold'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.require_no_active_hold()'))
          OR (t.tgname = 'audit_log'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'finance_autoclear_on_create' AND v_fn IS NOT NULL AND t.tgfoid = v_fn));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: unexpected trigger(s) on clearance_items: %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('require_no_active_hold'), ('audit_log')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger(s) missing or disabled on clearance_items: %; stop', v_bad;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.clearances'::pg_catalog.regclass
                   AND t.tgname = 'trg_clearances_create_items' AND NOT t.tgisinternal
                   AND t.tgenabled <> 'D'
                   AND t.tgfoid = pg_catalog.to_regprocedure('private.create_clearance_items()')) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trg_clearances_create_items missing or disabled on clearances; stop and review';
  END IF;

  -- i) SECURITY DEFINER only sees every row if its owner (the role running this file)
  --    bypasses RLS on the tables it reads and writes: owner of the tables without FORCE
  --    ROW LEVEL SECURITY, or a role with BYPASSRLS.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.charges'::pg_catalog.regclass, 'public.clearance_items'::pg_catalog.regclass,
                  'public.clearances'::pg_catalog.regclass, 'public.departments'::pg_catalog.regclass,
                  'public.academic_holds'::pg_catalog.regclass, 'public.audit_logs'::pg_catalog.regclass,
                  'public.profiles'::pg_catalog.regclass, 'public.roles'::pg_catalog.regclass)
    AND NOT (SELECT r.rolbypassrls FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
    AND NOT (c.relowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
             AND NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: % (running as %) would not bypass RLS on %; run as the table owner (postgres); stop', current_user, current_user, v_bad;
  END IF;
END
$$;

-- ------------------------------------------
-- 2. The trigger function (one function, two triggers)
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.finance_autoclear()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_student uuid;
  v_term    bigint;
  v_item    bigint;
  v_actor   uuid;
BEGIN
  IF TG_WHEN <> 'AFTER' OR TG_LEVEL <> 'ROW' OR TG_TABLE_SCHEMA <> 'public'
     OR NOT ((TG_TABLE_NAME = 'charges' AND TG_OP IN ('INSERT', 'UPDATE'))
             OR (TG_TABLE_NAME = 'clearance_items' AND TG_OP = 'INSERT')) THEN
    RAISE EXCEPTION 'private.finance_autoclear must be an AFTER INSERT OR UPDATE FOR EACH ROW trigger on public.charges or an AFTER INSERT FOR EACH ROW trigger on public.clearance_items';
  END IF;

  IF TG_TABLE_NAME = 'charges' THEN
    -- Same test as the trigger's WHEN clause: only a settled charge can complete the set.
    IF NEW.status::text NOT IN ('Cleared', 'Waived') THEN
      RETURN NULL;
    END IF;
    v_student := NEW.student_id;
    v_term    := NEW.term_id;
    v_item    := NULL;   -- every pending Financial item of that student and term

    -- The caller who tagged this charge, only if an active Cashier (header, decision 4).
    -- auth.uid() reads the request's JWT claims, so it is the API caller here too.
    SELECT p.profile_id INTO v_actor
    FROM public.profiles p
    JOIN public.roles r ON r.role_id = p.role_id
    WHERE p.profile_id = auth.uid() AND p.is_active AND r.role_name = 'Cashier';
  ELSE
    -- Same test as the trigger's WHEN clause, then: only the Financial item.
    IF NEW.cleared_at IS NOT NULL THEN
      RETURN NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.departments d
                   WHERE d.department_id = NEW.department_id AND d.department_type = 'Financial') THEN
      RETURN NULL;
    END IF;

    SELECT c.student_id, c.term_id INTO v_student, v_term
    FROM public.clearances c
    WHERE c.clearance_id = NEW.clearance_id;
    v_item := NEW.clearance_item_id;

    -- The Cashier who tagged the last charge: the actor of the newest audit row in which a
    -- charge of this student and term became settled; only if still an active Cashier.
    SELECT p.profile_id INTO v_actor
    FROM (SELECT l.actor_id
          FROM public.audit_logs l
          JOIN public.charges ch ON l.record_id = ch.charge_id::text
          WHERE l.table_name = 'charges'
            AND ch.student_id = v_student AND ch.term_id = v_term
            AND l.action IN ('INSERT', 'UPDATE')
            AND (l.new_data ->> 'status') IN ('Cleared', 'Waived')
            AND (l.action = 'INSERT' OR (l.old_data ->> 'status') IS DISTINCT FROM (l.new_data ->> 'status'))
          ORDER BY l.log_id DESC
          LIMIT 1) last_tag
    JOIN public.profiles p ON p.profile_id = last_tag.actor_id
    JOIN public.roles r ON r.role_id = p.role_id
    WHERE p.is_active AND r.role_name = 'Cashier';
  END IF;

  -- No Cashier to record (SQL editor, server role, seed, no audit row): leave it pending.
  IF v_actor IS NULL OR v_student IS NULL OR v_term IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    UPDATE public.clearance_items ci
    SET cleared_at = pg_catalog.now(), cleared_by = v_actor
    FROM public.clearances c, public.departments d
    WHERE c.clearance_id = ci.clearance_id
      AND d.department_id = ci.department_id
      AND c.student_id = v_student
      AND c.term_id = v_term
      AND d.department_type = 'Financial'
      AND ci.cleared_at IS NULL                                   -- decision 7
      AND (v_item IS NULL OR ci.clearance_item_id = v_item)
      -- at least one charge for that term (decision 2) ...
      AND EXISTS (SELECT 1 FROM public.charges ch
                  WHERE ch.student_id = v_student AND ch.term_id = v_term)
      -- ... and every one of them settled (decision 1)
      AND NOT EXISTS (SELECT 1 FROM public.charges ch
                      WHERE ch.student_id = v_student AND ch.term_id = v_term
                        AND ch.status::text NOT IN ('Cleared', 'Waived'))
      -- no active hold of the item's department (decision 6)
      AND NOT EXISTS (SELECT 1 FROM public.academic_holds h
                      WHERE h.student_id = v_student
                        AND h.department_id = ci.department_id
                        AND h.lifted_at IS NULL);
  EXCEPTION WHEN raise_exception THEN
    -- Only the race of decision 6 (a hold committed a moment ago): leave the item pending.
    IF SQLERRM NOT LIKE 'active hold:%' THEN
      RAISE;
    END IF;
  END;

  RETURN NULL;
END
$function$;

-- Same grant style as the other trigger functions (hardening2.sql section C).
REVOKE EXECUTE ON FUNCTION private.finance_autoclear() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.finance_autoclear() TO authenticated;

-- ------------------------------------------
-- 3. The triggers (both fire after audit_log of their table; see header 10)
-- ------------------------------------------
DROP TRIGGER IF EXISTS finance_autoclear ON public.charges;
CREATE TRIGGER finance_autoclear AFTER INSERT OR UPDATE OF status, student_id, term_id ON public.charges
  FOR EACH ROW
  WHEN (NEW.status::text IN ('Cleared', 'Waived'))
  EXECUTE FUNCTION private.finance_autoclear();

DROP TRIGGER IF EXISTS finance_autoclear_on_create ON public.clearance_items;
CREATE TRIGGER finance_autoclear_on_create AFTER INSERT ON public.clearance_items
  FOR EACH ROW
  WHEN (NEW.cleared_at IS NULL)
  EXECUTE FUNCTION private.finance_autoclear();

-- ------------------------------------------
-- 4. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.finance_autoclear()');
  v_bad text;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: function not created; rolled back';
  END IF;

  -- a) Function: SECURITY DEFINER, empty search_path.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.oid = v_fn AND p.prosecdef
                   AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: function is not SECURITY DEFINER with an empty search_path; rolled back';
  END IF;

  -- b) Grants: no PUBLIC entry in the ACL, anon cannot execute, authenticated can.
  IF (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
      FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
     OR pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: function grants are not PUBLIC none / anon none / authenticated EXECUTE; rolled back';
  END IF;

  -- c) Trigger on charges: AFTER INSERT OR UPDATE FOR EACH ROW (tgtype 1 ROW + 4 INSERT +
  --    16 UPDATE = 21; AFTER has no bit), enabled (origin), with the WHEN clause, on the
  --    columns status, student_id, term_id only, calling the function.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass
                   AND t.tgname = 'finance_autoclear' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn AND t.tgtype = 21 AND t.tgenabled = 'O'
                   AND t.tgqual IS NOT NULL
                   AND (SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
                          FROM pg_catalog.pg_attribute a
                         WHERE a.attrelid = t.tgrelid AND a.attnum = ANY (t.tgattr))
                       = 'status,student_id,term_id') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger finance_autoclear missing or not AFTER INSERT OR UPDATE OF status, student_id, term_id ROW enabled with WHEN; rolled back';
  END IF;

  -- d) Trigger on clearance_items: AFTER INSERT FOR EACH ROW (1 + 4 = 5), enabled, WHEN.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass
                   AND t.tgname = 'finance_autoclear_on_create' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn AND t.tgtype = 5 AND t.tgenabled = 'O'
                   AND t.tgqual IS NOT NULL) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger finance_autoclear_on_create missing or not AFTER INSERT ROW enabled with WHEN; rolled back';
  END IF;

  -- e) Exactly the expected triggers on both tables now.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, finance_autoclear, guard_immutable_columns' THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: triggers on charges are [%]; rolled back', v_bad;
  END IF;

  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, finance_autoclear_on_create, guard_immutable_columns, require_no_active_hold' THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: triggers on clearance_items are [%]; rolled back', v_bad;
  END IF;
END
$$;

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state after trigger_dept_approval.sql)
-- ------------------------------------------
-- Removes both triggers and the function; nothing else was changed. Items auto-cleared
-- while the triggers existed stay cleared (with the Cashier as cleared_by); their audit
-- rows stay in audit_logs.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS finance_autoclear ON public.charges;
-- DROP TRIGGER IF EXISTS finance_autoclear_on_create ON public.clearance_items;
-- DROP FUNCTION IF EXISTS private.finance_autoclear();
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: triggers on charges and clearance_items in firing order (BEFORE by
--    name, then AFTER by name). After: charges guard_immutable_columns, audit_log,
--    finance_autoclear; clearance_items guard_immutable_columns, require_no_active_hold,
--    audit_log, finance_autoclear_on_create.
-- select c.relname as table_name, t.tgname,
--        case when (t.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
--        t.tgenabled, t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t join pg_class c on c.oid = t.tgrelid
-- where t.tgrelid in ('public.charges'::regclass, 'public.clearance_items'::regclass) and not t.tgisinternal
-- order by 1, case when (t.tgtype::int & 2) = 2 then 0 else 1 end, t.tgname;
--
-- b) AFTER: the function's properties and grants.
-- select p.oid::regprocedure as function, pg_get_userbyid(p.proowner) as owner,
--        p.prosecdef as security_definer, p.proconfig, p.proacl::text as acl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
-- from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()');
--
-- c) BEFORE and AFTER: pending Financial items whose student has at least one charge for
--    that term and all of them settled. The change does NOT back-fill these (header 12);
--    after it, they appear only when the auto-clear skipped (active Financial hold, no
--    Cashier as the last tagger, the race in KNOWN LIMITS). The Cashier clears them by
--    hand or re-saves a charge status.
-- select ci.clearance_item_id, c.clearance_id, c.student_id, c.term_id, d.code as department,
--        (select count(*) from public.charges ch where ch.student_id = c.student_id and ch.term_id = c.term_id) as charges,
--        exists (select 1 from public.academic_holds h where h.student_id = c.student_id
--                  and h.department_id = ci.department_id and h.lifted_at is null) as active_financial_hold
-- from public.clearance_items ci
-- join public.clearances c on c.clearance_id = ci.clearance_id
-- join public.departments d on d.department_id = ci.department_id
-- where d.department_type = 'Financial' and ci.cleared_at is null
--   and exists (select 1 from public.charges ch where ch.student_id = c.student_id and ch.term_id = c.term_id)
--   and not exists (select 1 from public.charges ch where ch.student_id = c.student_id and ch.term_id = c.term_id
--                     and ch.status not in ('Cleared', 'Waived'))
-- order by 1;
--
-- d) BEFORE and AFTER: cleared Financial items whose student has an Unpaid charge for that
--    term (a charge went back to Unpaid, or the item was cleared by hand earlier). The
--    trigger never un-clears (header 8); the Cashier reviews these.
-- select ci.clearance_item_id, c.student_id, c.term_id, ci.cleared_at, ci.cleared_by,
--        (select string_agg(ch.charge_id::text, ', ' order by ch.charge_id) from public.charges ch
--          where ch.student_id = c.student_id and ch.term_id = c.term_id and ch.status = 'Unpaid') as unpaid_charges
-- from public.clearance_items ci
-- join public.clearances c on c.clearance_id = ci.clearance_id
-- join public.departments d on d.department_id = ci.department_id
-- where d.department_type = 'Financial' and ci.cleared_at is not null
--   and exists (select 1 from public.charges ch where ch.student_id = c.student_id and ch.term_id = c.term_id
--                 and ch.status = 'Unpaid')
-- order by 1;
--
-- e) AFTER: the latest clears of Financial items in the audit log (manual and automatic).
--    On the charge path actor = new cleared_by (the Cashier); on the creation path the
--    actor is the requesting student and new cleared_by is the Cashier.
-- select l.log_id, l.created_at, l.record_id as clearance_item_id, l.actor_id,
--        l.new_data ->> 'cleared_by' as new_cleared_by,
--        (l.actor_id::text = l.new_data ->> 'cleared_by') as actor_is_cleared_by
-- from public.audit_logs l
-- join public.clearance_items ci on ci.clearance_item_id::text = l.record_id
-- join public.departments d on d.department_id = ci.department_id and d.department_type = 'Financial'
-- where l.table_name = 'clearance_items' and l.action = 'UPDATE'
--   and l.old_data ->> 'cleared_at' is null and l.new_data ->> 'cleared_at' is not null
-- order by l.log_id desc limit 20;
