-- ==========================================
-- FINAL CLEARANCE REQUIRES EVERY ITEM CLEARED (GitHub issue #63, issue 24)
-- ==========================================
-- REQ-REG-03, REQ-ADM-03, Use Case "Verify All Departments and Finance Cleared". Sprint 3
-- plan item S3-4. Runs AFTER hardening.sql, hardening2.sql (A, B, C), views_extend.sql,
-- grants_clearance.sql, trigger_dept_approval.sql and trigger_finance_autoclear.sql (all
-- live since 2026-10-11).
--
-- WHAT IT DOES
--   A BEFORE UPDATE trigger on public.clearances rejects the approval of a clearance
--   (approved_at or approved_by going from NULL to a value) while any clearance_items row
--   of that clearance is still pending (cleared_at IS NULL), the Financial item (the
--   Cashier's Office) included. A clearance with no items at all is rejected too.
--   When every item is cleared the approval goes through as before, and the existing
--   audit_log trigger (hardening2.sql B) writes its audit row.
--   Before this file, clearances_registrar_approve (hardening.sql) only checked the role
--   and approved_by = the caller, so the Registrar could approve with items still pending.
--   Who may approve does NOT change: only the Registrar, through that policy.
--
-- DESIGN DECISIONS
--   1. When it fires (the WHEN clause of the trigger, repeated inside the function):
--        (OLD.approved_at IS NULL AND NEW.approved_at IS NOT NULL)
--        OR (OLD.approved_by IS NULL AND NEW.approved_by IS NOT NULL)
--      - Setting only ONE of the two is checked as well. approved_at alone is what makes
--        v_clearances.status 'Approved'; approved_by alone records "the Registrar signed
--        it". Either one is a step of approving, so neither may be set while an item is
--        pending (the issue: "rejects setting approved_at or approved_by"). For an API
--        user, setting only approved_at leaves approved_by NULL, which the policy rejects
--        anyway (WITH CHECK approved_by = the caller) when every item is cleared.
--      - Changing an ALREADY approved clearance is NOT checked: approved_at value -> other
--        value (a timestamp correction) and approved_by value -> other value. The status
--        does not change, the approval decision was made earlier (when every item was
--        cleared, if it was made after this trigger existed). It cannot be used to get
--        around the rule: a clearance that is not approved has approved_at NULL, and
--        setting it is NULL -> value, which is checked.
--      - Un-approving (approved_at and / or approved_by back to NULL) is NOT checked:
--        taking an approval back never needs every item cleared. Through the API the
--        policy still requires approved_by = the caller, so the Registrar can only set
--        approved_at back to NULL (keeping approved_by = self); postgres can clear both.
--        Re-approving afterwards is NULL -> value again, which is checked.
--      - UPDATE only. INSERT is not checked: authenticated can only insert
--        (student_id, term_id) (grants_clearance.sql) and clearances_student_request
--        requires approved_by and approved_at to be NULL. At INSERT time a clearance has
--        no items yet (trg_clearances_create_items creates them AFTER the insert), so a
--        check there could only ever say "0 items". Only the table owner (SQL editor,
--        seed) can insert an approved clearance; diagnostic (d) lists any approved
--        clearance with pending items, however it got there.
--   2. Zero items: REJECTED. "Every item cleared" must not be vacuously true. Every
--      clearance normally gets one item per department from trg_clearances_create_items
--      (private.create_clearance_items()); a clearance without items is a data anomaly,
--      and approving it would skip every department and the Cashier. The message starts
--      with the same "pending items:" prefix (see 3).
--   3. Error: RAISE EXCEPTION with SQLSTATE 'P0001' (raise_exception) and the stable
--      message prefix "pending items:", the same style as "active hold:" in
--      trigger_dept_approval.sql:
--        pending items: clearance <id> cannot be approved while <M> of <T> items are not cleared
--        pending items: clearance <id> cannot be approved because it has no clearance items
--      DETAIL lists the pending departments ("pending departments: CCS (item 12), ...",
--      departments.code and the clearance_item_id, in item order). HINT says what to do.
--      PostgREST returns it as HTTP 400 with code "P0001", so the app can recognise it by
--      code = 'P0001' AND the message starting with "pending items:". Not 42501 (that is
--      "permission denied"; PostgREST turns it into 401/403 and it would be confused with
--      RLS and grant errors) and not 23514 (check_violation, confused with CHECK
--      constraints).
--   4. SECURITY DEFINER, SET search_path TO '', every name schema-qualified. The trigger
--      runs as the caller, and RLS on clearance_items limits what the caller sees. The
--      Registrar sees every item today (clearance_items_read), but a SECURITY INVOKER count
--      would silently depend on that policy: if it ever became narrower, the items the
--      caller cannot see would be ignored and a clearance with hidden pending items could
--      be approved. As SECURITY DEFINER (owner postgres, the owner of the
--      tables, no FORCE RLS; safety check (h)) it counts every item of the clearance. It
--      only reads; what it returns to the caller is "blocked" plus the pending
--      departments of a clearance the caller is already allowed to update (RLS USING
--      filters the rows before any trigger fires, so nobody can probe other clearances).
--   5. Every role: the rule applies to API users AND to postgres / the server role / SQL
--      editor fixes (same as require_no_active_hold, issue 22; unlike
--      guard_immutable_columns, which only restricts API users). A clearance with a
--      pending item must not be approved by anybody; clear the items first. An
--      intentional exception is possible only in a reviewed change by the table owner
--      (ALTER TABLE public.clearances DISABLE TRIGGER require_all_items_cleared, fix,
--      ENABLE TRIGGER).
--   6. Non-Registrar roles stay blocked by the policy, not by this trigger:
--      clearances_registrar_approve is the only UPDATE policy on clearances (safety check
--      (g)); its USING is "role = Registrar", so for a Student, Cashier or Department user
--      the row is filtered out BEFORE any trigger fires and the UPDATE changes 0 rows,
--      with or without pending items. This trigger never widens or narrows who may
--      approve.
--   7. Name and firing order. PostgreSQL fires all BEFORE ROW triggers in alphabetical
--      (byte) order of their names, then RLS WITH CHECK and constraints, then the row is
--      written, then the AFTER ROW triggers by name. On public.clearances that is:
--        UPDATE: guard_immutable_columns (BEFORE) -> require_all_items_cleared (BEFORE)
--                -> RLS WITH CHECK -> write -> audit_log (AFTER)
--        INSERT: write -> audit_log (AFTER) -> trg_clearances_create_items (AFTER)
--                (this trigger is UPDATE only and does not fire)
--      "require_all_items_cleared" sorts after "guard_immutable_columns" ('g' < 'r'), so an
--      API user's attempt to change student_id / term_id is rejected first (42501 "cannot
--      be changed"). A rejected approval stops the statement before the write, so
--      audit_log (AFTER) writes no row for it; a successful approval is audited exactly as
--      before (actor = the Registrar). Side effect of BEFORE triggers running before RLS
--      WITH CHECK: a Registrar whose update would ALSO fail WITH CHECK (approved_by NULL)
--      gets the "pending items" error instead of the RLS error when an item is pending.
--      Both reject the update. That is why TC-18 (regression_after_grants.sql) now uses a
--      clearance whose items are all cleared.
--   8. Interaction with the other triggers: none on the same statement. The trigger only
--      reads clearance_items and departments. require_no_active_hold (issue 22) and
--      finance_autoclear (issue 23) change clearance_items, never clearances, so they
--      cannot fire this trigger; this trigger writes nothing, so it cannot fire them.
--   9. Grants: like the other trigger functions (hardening2.sql section C,
--      trigger_dept_approval.sql, trigger_finance_autoclear.sql): no PUBLIC and no anon
--      EXECUTE, explicit EXECUTE for authenticated. A trigger function cannot be called
--      directly anyway ("trigger functions can only be called as triggers"). No table
--      grant changes.
--  10. No back-fill: clearances that are ALREADY approved while an item is pending (approved
--      before this trigger, or an item un-cleared after the approval) are not changed.
--      Diagnostic (d) lists them; the Registrar decides whether to un-approve them.
--
-- KNOWN LIMITS (not done here, on purpose)
--   - Un-clearing an item AFTER the approval is not blocked (this trigger is on
--     clearances; clearance_items_dept_update still lets a department set cleared_at back
--     to NULL with cleared_by = self, TC-47). The clearance then stays approved with a
--     pending item. Diagnostic (d) lists such clearances. Blocking that (or
--     un-approving automatically) is a separate decision for the Registrar's flow.
--   - Race: an item un-cleared in another transaction that has not committed yet is not
--     seen (READ COMMITTED), so an approval and an un-clear committing at the same moment
--     can leave an approved clearance with a pending item. That is the same end state as
--     the previous point, which is allowed anyway, so locking the items here would not
--     establish a stronger rule. Diagnostic (d).
--   - Only the EXISTING items count. A department added after a clearance was created has
--     no item on that clearance and is not required. Diagnostic (e) lists clearances that
--     have no item for some department.
--   - No index on clearance_items (clearance_id); the table is tiny and the count runs
--     once per approval. Add one in a separate change if it ever grows.
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (CREATE OR REPLACE, DROP TRIGGER IF EXISTS, idempotent grants).
-- CREATE TRIGGER takes a short lock on clearances; well under a second.
--   - Before running: run diagnostics (a), (c), (d) and (e) at the bottom and SAVE the
--     output.
--   - Rehearse first: docs/database/trigger_final_clearance_rehearsal.sql runs this change
--     and all tests (TC-62 to TC-70) in ONE rolled-back transaction with one result row
--     (TC-62R).
-- Test afterwards: Part L of docs/issue-12-testing-guide.md (TC-62 to TC-70, SQL in
-- docs/database/trigger_final_clearance_test.sql, or the test part of the rehearsal file on
-- its own), then TC-37 and TC-39 (Part I, docs/database/grants_clearance_test.sql), Parts J
-- and K, and docs/database/regression_after_grants.sql again (TC-18, TC-19, TC-37 and TC-39
-- were adjusted for this rule; see Part L).
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: RUN on the live database on 2026-10-11 after a rolled-back rehearsal; TC-62 to TC-70 pass live.


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.require_all_items_cleared()');
BEGIN
  -- a) The tables exist.
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('clearances'), ('clearance_items'), ('departments'), ('audit_logs')) AS e(t)
  WHERE pg_catalog.to_regclass('public.' || e.t) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_final_clearance: missing table(s) public.%; stop', v_bad;
  END IF;

  -- b) The columns the trigger and the function read exist with the expected types
  --    (format_type with a NULL typmod: "character varying", not "character varying(n)").
  SELECT string_agg(e.t || '.' || e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('clearances', 'clearance_id', 'bigint'),
    ('clearances', 'approved_at', 'timestamp with time zone'),
    ('clearances', 'approved_by', 'uuid'),
    ('clearance_items', 'clearance_item_id', 'bigint'),
    ('clearance_items', 'clearance_id', 'bigint'),
    ('clearance_items', 'department_id', 'bigint'),
    ('clearance_items', 'cleared_at', 'timestamp with time zone'),
    ('departments', 'department_id', 'bigint'),
    ('departments', 'code', 'character varying')) AS e(t, col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.t)
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_final_clearance: missing column or other type: %; stop', v_bad;
  END IF;

  -- c) RLS is enabled on clearances (decision 6 relies on clearances_registrar_approve).
  IF NOT (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
          WHERE c.oid = 'public.clearances'::pg_catalog.regclass) THEN
    RAISE EXCEPTION 'trigger_final_clearance: row level security is not enabled on public.clearances; stop';
  END IF;

  -- d) The function is absent (first run) or is this file's trigger function (re-run).
  IF v_fn IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
                          <> 'pg_catalog.trigger'::pg_catalog.regtype THEN
    RAISE EXCEPTION 'trigger_final_clearance: private.require_all_items_cleared() exists and is not a trigger function; stop and review';
  END IF;

  -- e) No trigger named require_all_items_cleared anywhere calls a different function.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname = 'require_all_items_cleared' AND NOT t.tgisinternal
               AND (v_fn IS NULL OR t.tgfoid <> v_fn)) THEN
    RAISE EXCEPTION 'trigger_final_clearance: a different trigger named require_all_items_cleared already exists; stop and review';
  END IF;

  -- f) The triggers on clearances are exactly guard_immutable_columns (BEFORE,
  --    hardening.sql), audit_log (AFTER, hardening2.sql B) and trg_clearances_create_items
  --    (AFTER, calls private.create_clearance_items()), all enabled, plus this file's
  --    trigger on a re-run. Anything else: stop (the firing order in the header would no
  --    longer be the whole picture). tgtype bit 2 = BEFORE.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearances'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns' AND (t.tgtype::integer & 2) = 2
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'audit_log' AND (t.tgtype::integer & 2) = 0
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'trg_clearances_create_items' AND (t.tgtype::integer & 2) = 0
              AND t.tgfoid = pg_catalog.to_regprocedure('private.create_clearance_items()'))
          OR (t.tgname = 'require_all_items_cleared' AND v_fn IS NOT NULL AND t.tgfoid = v_fn));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_final_clearance: unexpected trigger(s) on clearances (or not the expected function / timing): %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('audit_log'), ('trg_clearances_create_items')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.clearances'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_final_clearance: trigger(s) missing or disabled on clearances: %; stop', v_bad;
  END IF;

  -- g) The only UPDATE (or ALL) policy on clearances is the hardened
  --    clearances_registrar_approve: PERMISSIVE, TO authenticated, Registrar in USING and
  --    WITH CHECK, approved_by = active_uid() with no "IS NULL" escape (hardening.sql).
  SELECT string_agg(p.policyname, ', ') INTO v_bad
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = 'clearances' AND p.cmd IN ('UPDATE', 'ALL')
    AND p.policyname <> 'clearances_registrar_approve';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_final_clearance: other UPDATE policies on clearances: %; stop and review (header, decision 6)', v_bad;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
                 WHERE p.schemaname = 'public' AND p.tablename = 'clearances'
                   AND p.policyname = 'clearances_registrar_approve' AND p.cmd = 'UPDATE'
                   AND p.permissive = 'PERMISSIVE' AND p.roles = ARRAY['authenticated']::name[]
                   AND position('''Registrar''' IN coalesce(p.qual, '')) > 0
                   AND position('''Registrar''' IN coalesce(p.with_check, '')) > 0
                   AND position('active_uid' IN coalesce(p.with_check, '')) > 0
                   AND position('IS NULL' IN upper(coalesce(p.with_check, ''))) = 0) THEN
    RAISE EXCEPTION 'trigger_final_clearance: clearances_registrar_approve is missing or not the hardened version (hardening.sql); stop';
  END IF;

  -- h) SECURITY DEFINER only sees every row if its owner (the role running this file)
  --    bypasses RLS on the tables it reads: owner of the tables without FORCE ROW LEVEL
  --    SECURITY, or a role with BYPASSRLS.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.clearance_items'::pg_catalog.regclass, 'public.departments'::pg_catalog.regclass)
    AND NOT (SELECT r.rolbypassrls FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
    AND NOT (c.relowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
             AND NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_final_clearance: % (running as %) would not bypass RLS on %; run as the table owner (postgres); stop', current_user, current_user, v_bad;
  END IF;
END
$$;

-- ------------------------------------------
-- 2. The trigger function
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.require_all_items_cleared()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_total   bigint;
  v_pending bigint;
  v_list    text;
BEGIN
  IF TG_OP <> 'UPDATE' OR TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW'
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'clearances' THEN
    RAISE EXCEPTION 'private.require_all_items_cleared must be a BEFORE UPDATE FOR EACH ROW trigger on public.clearances';
  END IF;

  -- Only the step "not approved -> approved" is checked (same test as the WHEN clause).
  IF NOT ((OLD.approved_at IS NULL AND NEW.approved_at IS NOT NULL)
          OR (OLD.approved_by IS NULL AND NEW.approved_by IS NOT NULL)) THEN
    RETURN NEW;
  END IF;

  -- Every item of this clearance (all departments, the Financial item included).
  SELECT pg_catalog.count(*),
         pg_catalog.count(*) FILTER (WHERE ci.cleared_at IS NULL),
         pg_catalog.string_agg(COALESCE(d.code::text, 'department_id ' || ci.department_id::text)
                                 || ' (item ' || ci.clearance_item_id::text || ')',
                               ', ' ORDER BY ci.clearance_item_id) FILTER (WHERE ci.cleared_at IS NULL)
    INTO v_total, v_pending, v_list
  FROM public.clearance_items ci
  LEFT JOIN public.departments d ON d.department_id = ci.department_id
  WHERE ci.clearance_id = OLD.clearance_id;

  IF v_total = 0 THEN
    RAISE EXCEPTION 'pending items: clearance % cannot be approved because it has no clearance items', OLD.clearance_id
      USING ERRCODE = 'P0001',
            DETAIL = 'pending departments: none recorded (0 items); every department must have a cleared item',
            HINT = 'Create the clearance items (one per department, as private.create_clearance_items() does), have them cleared, then approve.';
  END IF;

  IF v_pending > 0 THEN
    RAISE EXCEPTION 'pending items: clearance % cannot be approved while % of % items are not cleared', OLD.clearance_id, v_pending, v_total
      USING ERRCODE = 'P0001',
            DETAIL = pg_catalog.format('pending departments: %s', v_list),
            HINT = 'Every department and the Cashier must clear their item first (clearance_items.cleared_at), then approve.';
  END IF;

  RETURN NEW;
END
$function$;

-- Same grant style as the other trigger functions (hardening2.sql section C).
REVOKE EXECUTE ON FUNCTION private.require_all_items_cleared() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.require_all_items_cleared() TO authenticated;

-- ------------------------------------------
-- 3. The trigger (fires after guard_immutable_columns, before RLS WITH CHECK and
--    audit_log; see header 7)
-- ------------------------------------------
DROP TRIGGER IF EXISTS require_all_items_cleared ON public.clearances;
CREATE TRIGGER require_all_items_cleared BEFORE UPDATE ON public.clearances
  FOR EACH ROW
  WHEN ((OLD.approved_at IS NULL AND NEW.approved_at IS NOT NULL)
        OR (OLD.approved_by IS NULL AND NEW.approved_by IS NOT NULL))
  EXECUTE FUNCTION private.require_all_items_cleared();

-- ------------------------------------------
-- 4. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.require_all_items_cleared()');
  v_bad text;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'trigger_final_clearance: function not created; rolled back';
  END IF;

  -- a) Function: SECURITY DEFINER, empty search_path.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.oid = v_fn AND p.prosecdef
                   AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']) THEN
    RAISE EXCEPTION 'trigger_final_clearance: function is not SECURITY DEFINER with an empty search_path; rolled back';
  END IF;

  -- b) Grants: no PUBLIC entry in the ACL, anon cannot execute, authenticated can.
  IF (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
      FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
     OR pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'trigger_final_clearance: function grants are not PUBLIC none / anon none / authenticated EXECUTE; rolled back';
  END IF;

  -- c) Trigger: BEFORE UPDATE FOR EACH ROW (tgtype 1 ROW + 2 BEFORE + 16 UPDATE = 19),
  --    enabled (origin), with the WHEN clause, calling the function.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.clearances'::pg_catalog.regclass
                   AND t.tgname = 'require_all_items_cleared' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn AND t.tgtype = 19 AND t.tgenabled = 'O'
                   AND t.tgqual IS NOT NULL) THEN
    RAISE EXCEPTION 'trigger_final_clearance: trigger require_all_items_cleared missing or not BEFORE UPDATE ROW enabled with WHEN; rolled back';
  END IF;

  -- d) Exactly the 4 expected triggers on clearances now.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearances'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, guard_immutable_columns, require_all_items_cleared, trg_clearances_create_items' THEN
    RAISE EXCEPTION 'trigger_final_clearance: triggers on clearances are [%]; rolled back', v_bad;
  END IF;

  -- e) Firing order of the BEFORE triggers on clearances (by name): the guard first.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearances'::pg_catalog.regclass AND NOT t.tgisinternal
    AND (t.tgtype::integer & 2) = 2;
  IF v_bad IS DISTINCT FROM 'guard_immutable_columns, require_all_items_cleared' THEN
    RAISE EXCEPTION 'trigger_final_clearance: BEFORE triggers on clearances are [%]; rolled back', v_bad;
  END IF;
END
$$;

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state after trigger_finance_autoclear.sql)
-- ------------------------------------------
-- Removes the trigger and its function; nothing else was changed. Clearances approved
-- while the trigger existed stay approved; their audit rows stay in audit_logs.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS require_all_items_cleared ON public.clearances;
-- DROP FUNCTION IF EXISTS private.require_all_items_cleared();
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: triggers on clearances in firing order (BEFORE by name, then AFTER
--    by name). After: guard_immutable_columns, require_all_items_cleared (BEFORE);
--    audit_log, trg_clearances_create_items (AFTER).
-- select t.tgname,
--        case when (t.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
--        t.tgenabled, t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t
-- where t.tgrelid = 'public.clearances'::regclass and not t.tgisinternal
-- order by case when (t.tgtype::int & 2) = 2 then 0 else 1 end, t.tgname;
--
-- b) AFTER: the function's properties and grants.
-- select p.oid::regprocedure as function, pg_get_userbyid(p.proowner) as owner,
--        p.prosecdef as security_definer, p.proconfig, p.proacl::text as acl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
-- from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()');
--
-- c) BEFORE and AFTER: clearances that are not (fully) approved and that the trigger
--    blocks from approval: at least one pending item, or no item at all.
-- select c.clearance_id, c.student_id, c.term_id, c.approved_at, c.approved_by,
--        count(ci.clearance_item_id) as total_items,
--        count(ci.clearance_item_id) filter (where ci.cleared_at is null) as pending_items,
--        string_agg(d.code, ', ' order by d.code) filter (where ci.cleared_at is null) as pending_departments
-- from public.clearances c
-- left join public.clearance_items ci on ci.clearance_id = c.clearance_id
-- left join public.departments d on d.department_id = ci.department_id
-- where c.approved_at is null or c.approved_by is null
-- group by c.clearance_id, c.student_id, c.term_id, c.approved_at, c.approved_by
-- having count(ci.clearance_item_id) = 0
--     or count(ci.clearance_item_id) filter (where ci.cleared_at is null) > 0
-- order by 1;
--
-- d) BEFORE and AFTER: clearances that are ALREADY approved (approved_at set) while an item
--    is pending or no item exists (approved before this trigger, inserted approved by the
--    owner, or an item un-cleared after the approval). The trigger does not change them;
--    the Registrar decides whether to un-approve them.
-- select c.clearance_id, c.student_id, c.term_id, c.approved_at, c.approved_by,
--        count(ci.clearance_item_id) as total_items,
--        count(ci.clearance_item_id) filter (where ci.cleared_at is null) as pending_items,
--        string_agg(d.code, ', ' order by d.code) filter (where ci.cleared_at is null) as pending_departments
-- from public.clearances c
-- left join public.clearance_items ci on ci.clearance_id = c.clearance_id
-- left join public.departments d on d.department_id = ci.department_id
-- where c.approved_at is not null
-- group by c.clearance_id, c.student_id, c.term_id, c.approved_at, c.approved_by
-- having count(ci.clearance_item_id) = 0
--     or count(ci.clearance_item_id) filter (where ci.cleared_at is null) > 0
-- order by 1;
--
-- e) BEFORE and AFTER: clearances without an item for some department (KNOWN LIMITS: only
--    existing items count, so these departments are not required for the approval).
-- select c.clearance_id, c.student_id, c.term_id,
--        string_agg(d.code, ', ' order by d.code) as departments_without_item
-- from public.clearances c
-- cross join public.departments d
-- where not exists (select 1 from public.clearance_items ci
--                   where ci.clearance_id = c.clearance_id and ci.department_id = d.department_id)
-- group by c.clearance_id, c.student_id, c.term_id
-- order by 1;
--
-- f) AFTER: the latest approvals in the audit log (actor = the Registrar).
-- select l.log_id, l.created_at, l.record_id as clearance_id, l.actor_id,
--        l.old_data ->> 'approved_at' as old_approved_at,
--        l.new_data ->> 'approved_at' as new_approved_at,
--        l.new_data ->> 'approved_by' as new_approved_by
-- from public.audit_logs l
-- where l.table_name = 'clearances' and l.action = 'UPDATE'
-- order by l.log_id desc limit 20;
