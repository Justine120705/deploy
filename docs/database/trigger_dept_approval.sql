-- ==========================================
-- DEPARTMENT APPROVAL REQUIRES NO ACTIVE HOLD (GitHub issue #61, issue 22)
-- ==========================================
-- REQ-DPT-03, SDLC 7.7 risk table, Use Case "Check Active Holds". Sprint 3 plan item S3-2.
-- Runs AFTER hardening.sql, hardening2.sql (A, B, C), views_extend.sql and
-- grants_clearance.sql (all live since 2026-10-11).
--
-- WHAT IT DOES
--   A BEFORE UPDATE trigger on public.clearance_items rejects the step "pending ->
--   cleared" (cleared_at NULL -> NOT NULL) of an item while the student of that item's
--   clearance has an ACTIVE hold (academic_holds.lifted_at IS NULL) of the SAME
--   department as the item (academic_holds.department_id = clearance_items.department_id).
--     - A hold of another department does not block the item.
--     - The Cashier's item (the Financial department) is only blocked by a hold of the
--       Financial department itself; a Department (academic) hold never blocks it.
--   Before this file, clearance_items_dept_update (hardening.sql) only checked the role,
--   the department and cleared_by, so a department could approve an item while its own
--   hold was still active.
--
-- DESIGN DECISIONS
--   1. When it fires: only when NEW.cleared_at IS NOT NULL AND OLD.cleared_at IS NULL
--      (the WHEN clause of the trigger, repeated inside the function). So these are NOT
--      checked and keep working while a hold is active:
--        - editing remarks (or cleared_by) of an item that is already cleared;
--        - un-clearing (cleared_at back to NULL; the RLS policy decides whether the
--          caller may do that, the trigger does not);
--        - changing cleared_at of an item that is ALREADY cleared to another non-NULL
--          time (a timestamp correction). Reason: the approval decision was made before
--          the hold existed; a hold placed later does not undo an approval, and the
--          item's status (derived from cleared_at in v_clearance_items) does not change.
--          It cannot be used to get around the rule: to approve a pending item it must
--          go NULL -> NOT NULL, which is checked, and un-clearing then re-clearing is
--          also NULL -> NOT NULL on the second step.
--   2. Error: RAISE EXCEPTION with SQLSTATE 'P0001' (raise_exception) and a stable
--      message prefix "active hold:". PostgREST returns it as HTTP 400 with
--      code "P0001", so the app (issue 21) can recognise it by code = 'P0001' AND the
--      message starting with "active hold:". DETAIL carries hold_id and department_id,
--      HINT says what to do. Not 42501 (that is "permission denied"; PostgREST turns it
--      into 401/403 and it would be confused with RLS and grant errors) and not 23514
--      (check_violation would be confused with table CHECK constraints). The reason text
--      of the hold is NOT in the message.
--   3. SECURITY DEFINER, SET search_path TO '', every name schema-qualified. The trigger
--      runs as the caller, and RLS applies to the caller: holds_read lets a Department
--      user read only its own department's holds, and the Cashier reads NO holds at all,
--      so a SECURITY INVOKER function would never see a Financial hold for the Cashier.
--      As SECURITY DEFINER (owner postgres, the owner of the tables, no FORCE RLS) it sees
--      every hold and every clearance. It only reads; the only thing it returns to the
--      caller is "blocked" (plus hold_id in DETAIL) for an item the caller is already
--      allowed to update (RLS USING filters the rows before any trigger fires, so a user
--      cannot probe other departments' items). Safety check (f) stops if the owner would
--      not bypass RLS.
--   4. Every role: the rule applies to API users AND to postgres / the server role / SQL
--      editor fixes (unlike guard_immutable_columns, which only restricts API users).
--      A clearance with an active hold must not be cleared by anybody; lift the hold
--      first. An intentional exception is possible only in a reviewed change by the
--      table owner (ALTER TABLE ... DISABLE TRIGGER require_no_active_hold, fix, ENABLE).
--      UPDATE only: authenticated has no INSERT on clearance_items (grants_clearance.sql)
--      and private.create_clearance_items() inserts items with cleared_at NULL; only the
--      owner (seed.sql) can insert an already-cleared item.
--   5. NULL handling: an item whose clearance has no student (cannot happen: FK and NOT
--      NULL) finds no hold and passes. lifted_at IS NULL is the only test for "active"
--      (a hold with lifted_at set, even in the future, is lifted). The department of the
--      item is NEW.department_id; for API users guard_immutable_columns (which fires
--      first, see 6) guarantees it equals OLD.department_id.
--   6. Name and firing order. PostgreSQL fires all BEFORE ROW triggers in alphabetical
--      (byte) order of their names, then RLS WITH CHECK and constraints, then the row is
--      written, then the AFTER ROW triggers. On clearance_items that is:
--        guard_immutable_columns (BEFORE)  -> require_no_active_hold (BEFORE)
--        -> RLS WITH CHECK -> write -> audit_log (AFTER)
--      "require_no_active_hold" sorts after "guard_immutable_columns" ('g' < 'r'), so an
--      API user's attempt to move the item to another clearance or department is
--      rejected first and the hold check always sees the item's real department and
--      clearance. A rejected approval stops the statement before the write, so
--      audit_log (AFTER) writes no row for it; a successful approval is audited exactly
--      as before. Side effect of BEFORE triggers running before RLS WITH CHECK: a caller
--      whose update would ALSO fail WITH CHECK (for example cleared_by NULL) gets the
--      "active hold" error instead of the RLS error. Both reject the update.
--   7. Grants: like the other trigger functions (hardening2.sql section C): no PUBLIC and
--      no anon EXECUTE, explicit EXECUTE for authenticated. A trigger function cannot be
--      called directly anyway ("trigger functions can only be called as triggers").
--
-- KNOWN LIMITS (not done here, on purpose)
--   - Race: a hold placed in another transaction that has not committed yet is not seen
--     (READ COMMITTED). If both commit at the same moment the item can end up cleared
--     with a hold placed a few milliseconds earlier. Closing that would need a lock taken
--     by both the hold insert and the approval; not worth it for this data and UI.
--     Diagnostic (d) lists such items.
--   - Through the API nobody can place a Financial hold today (holds_dept_place is
--     Department only and checks the student's program department; the Financial
--     department has no programs). The Financial branch is enforced for holds placed by
--     SQL, and for any later flow that lets the Cashier place holds.
--   - Already-cleared items with an active hold of the same department (cleared before
--     this trigger existed, or before the hold) stay cleared. Diagnostic (d) lists them.
--   - No index on academic_holds (student_id, department_id); the table is tiny. Add
--     one in a separate change if it ever grows.
--
-- How to run: Supabase SQL editor, as postgres (the owner of the tables). Copy from
-- "BEGIN;" to "COMMIT;" inclusive into a new tab and run that tab as a whole (never a
-- partial selection). One transaction: any error, including a failed check, rolls back
-- everything. Re-runnable (CREATE OR REPLACE, DROP TRIGGER IF EXISTS, idempotent grants).
-- CREATE TRIGGER takes a short lock on clearance_items; well under a second.
--   - Before running: run diagnostics (a) and (c) at the bottom and SAVE the output.
--   - Rehearse first: docs/database/trigger_dept_approval_rehearsal.sql runs this change
--     and all tests (TC-41 to TC-48) in ONE rolled-back transaction with one result row.
-- Test afterwards: Part J of docs/issue-12-testing-guide.md (TC-41 to TC-48, SQL in
-- docs/database/trigger_dept_approval_test.sql), then TC-37 (Part I) and the regression
-- docs/database/regression_after_grants.sql again.
-- Undo: the ROLLBACK block after COMMIT.
--
-- Status: RUN on the live database on 2026-10-11 after a rolled-back rehearsal; TC-41 to TC-48 pass live.


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.require_no_active_hold()');
BEGIN
  -- a) The tables exist.
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('clearance_items'), ('clearances'), ('academic_holds'), ('audit_logs')) AS e(t)
  WHERE pg_catalog.to_regclass('public.' || e.t) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_dept_approval: missing table(s) public.%; stop', v_bad;
  END IF;

  -- b) The columns the function reads exist with the expected types.
  SELECT string_agg(e.t || '.' || e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('clearance_items', 'clearance_item_id', 'bigint'),
    ('clearance_items', 'clearance_id', 'bigint'),
    ('clearance_items', 'department_id', 'bigint'),
    ('clearance_items', 'cleared_at', 'timestamp with time zone'),
    ('clearances', 'clearance_id', 'bigint'),
    ('clearances', 'student_id', 'uuid'),
    ('academic_holds', 'hold_id', 'bigint'),
    ('academic_holds', 'student_id', 'uuid'),
    ('academic_holds', 'department_id', 'bigint'),
    ('academic_holds', 'lifted_at', 'timestamp with time zone')) AS e(t, col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.t)
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, a.atttypmod) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_dept_approval: missing column or other type: %; stop', v_bad;
  END IF;

  -- c) The function is absent (first run) or is this file's trigger function (re-run).
  IF v_fn IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
                          <> 'pg_catalog.trigger'::pg_catalog.regtype THEN
    RAISE EXCEPTION 'trigger_dept_approval: private.require_no_active_hold() exists and is not a trigger function; stop and review';
  END IF;

  -- d) No trigger named require_no_active_hold anywhere calls a different function.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname = 'require_no_active_hold' AND NOT t.tgisinternal
               AND (v_fn IS NULL OR t.tgfoid <> v_fn)) THEN
    RAISE EXCEPTION 'trigger_dept_approval: a different trigger named require_no_active_hold already exists; stop and review';
  END IF;

  -- e) The triggers on clearance_items are exactly guard_immutable_columns (BEFORE UPDATE,
  --    hardening.sql) and audit_log (AFTER, hardening2.sql B), both enabled, plus this
  --    file's trigger on a re-run. Anything else: stop (the firing order in the header
  --    would no longer be the whole picture).
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'audit_log'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'require_no_active_hold' AND v_fn IS NOT NULL AND t.tgfoid = v_fn));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_dept_approval: unexpected trigger(s) on clearance_items: %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('audit_log')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_dept_approval: trigger(s) missing or disabled on clearance_items: %; stop', v_bad;
  END IF;

  -- f) SECURITY DEFINER only sees every row if its owner (the role running this file)
  --    bypasses RLS on clearances and academic_holds: owner of the tables without FORCE
  --    ROW LEVEL SECURITY, or a role with BYPASSRLS.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.clearances'::pg_catalog.regclass, 'public.academic_holds'::pg_catalog.regclass)
    AND NOT (SELECT r.rolbypassrls FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
    AND NOT (c.relowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
             AND NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_dept_approval: % (running as %) would not bypass RLS on %; run as the table owner (postgres); stop', current_user, current_user, v_bad;
  END IF;
END
$$;

-- ------------------------------------------
-- 2. The trigger function
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.require_no_active_hold()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_student uuid;
  v_hold    bigint;
BEGIN
  IF TG_OP <> 'UPDATE' OR TG_WHEN <> 'BEFORE' OR TG_LEVEL <> 'ROW'
     OR TG_TABLE_SCHEMA <> 'public' OR TG_TABLE_NAME <> 'clearance_items' THEN
    RAISE EXCEPTION 'private.require_no_active_hold must be a BEFORE UPDATE FOR EACH ROW trigger on public.clearance_items';
  END IF;

  -- Only the step "pending -> cleared" is checked (same test as the trigger's WHEN clause).
  IF NEW.cleared_at IS NULL OR OLD.cleared_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.student_id INTO v_student
  FROM public.clearances c
  WHERE c.clearance_id = NEW.clearance_id;

  SELECT h.hold_id INTO v_hold
  FROM public.academic_holds h
  WHERE h.student_id = v_student
    AND h.department_id = NEW.department_id
    AND h.lifted_at IS NULL
  ORDER BY h.hold_id
  LIMIT 1;

  IF v_hold IS NOT NULL THEN
    RAISE EXCEPTION 'active hold: clearance item % cannot be cleared while the student has an active hold of the same department', NEW.clearance_item_id
      USING ERRCODE = 'P0001',
            DETAIL = pg_catalog.format('hold_id %s, department_id %s', v_hold, NEW.department_id),
            HINT = 'Lift the hold first (academic_holds.lifted_at), then clear the item.';
  END IF;

  RETURN NEW;
END
$function$;

-- Same grant style as the other trigger functions (hardening2.sql section C).
REVOKE EXECUTE ON FUNCTION private.require_no_active_hold() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.require_no_active_hold() TO authenticated;

-- ------------------------------------------
-- 3. The trigger (fires after guard_immutable_columns, before audit_log; see header 6)
-- ------------------------------------------
DROP TRIGGER IF EXISTS require_no_active_hold ON public.clearance_items;
CREATE TRIGGER require_no_active_hold BEFORE UPDATE ON public.clearance_items
  FOR EACH ROW
  WHEN (NEW.cleared_at IS NOT NULL AND OLD.cleared_at IS NULL)
  EXECUTE FUNCTION private.require_no_active_hold();

-- ------------------------------------------
-- 4. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.require_no_active_hold()');
  v_bad text;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'trigger_dept_approval: function not created; rolled back';
  END IF;

  -- a) Function: SECURITY DEFINER, empty search_path.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.oid = v_fn AND p.prosecdef
                   AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']) THEN
    RAISE EXCEPTION 'trigger_dept_approval: function is not SECURITY DEFINER with an empty search_path; rolled back';
  END IF;

  -- b) Grants: no PUBLIC entry in the ACL, anon cannot execute, authenticated can.
  IF (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
      FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
     OR pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'trigger_dept_approval: function grants are not PUBLIC none / anon none / authenticated EXECUTE; rolled back';
  END IF;

  -- c) Trigger: BEFORE UPDATE FOR EACH ROW (tgtype 1 ROW + 2 BEFORE + 16 UPDATE = 19),
  --    enabled (origin), with the WHEN clause, calling the function.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass
                   AND t.tgname = 'require_no_active_hold' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn AND t.tgtype = 19 AND t.tgenabled = 'O'
                   AND t.tgqual IS NOT NULL) THEN
    RAISE EXCEPTION 'trigger_dept_approval: trigger require_no_active_hold missing or not BEFORE UPDATE ROW enabled with WHEN; rolled back';
  END IF;

  -- d) Exactly the 3 expected triggers on clearance_items now.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, guard_immutable_columns, require_no_active_hold' THEN
    RAISE EXCEPTION 'trigger_dept_approval: triggers on clearance_items are [%]; rolled back', v_bad;
  END IF;
END
$$;

COMMIT;


-- ------------------------------------------
-- ROLLBACK (back to the state after grants_clearance.sql)
-- ------------------------------------------
-- Removes the trigger and its function; nothing else was changed. Items cleared while
-- the trigger existed stay cleared; their audit rows stay in audit_logs.
--
-- BEGIN;
--
-- DROP TRIGGER IF EXISTS require_no_active_hold ON public.clearance_items;
-- DROP FUNCTION IF EXISTS private.require_no_active_hold();
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time and send the output back)
-- ==========================================
-- Nothing here changes the database.
--
-- a) BEFORE and AFTER: triggers on clearance_items in firing order (BEFORE by name,
--    then AFTER by name). After: guard_immutable_columns, require_no_active_hold, audit_log.
-- select t.tgname,
--        case when (t.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
--        t.tgenabled, t.tgfoid::regprocedure as function, pg_get_triggerdef(t.oid) as definition
-- from pg_trigger t
-- where t.tgrelid = 'public.clearance_items'::regclass and not t.tgisinternal
-- order by case when (t.tgtype::int & 2) = 2 then 0 else 1 end, t.tgname;
--
-- b) AFTER: the function's properties and grants.
-- select p.oid::regprocedure as function, pg_get_userbyid(p.proowner) as owner,
--        p.prosecdef as security_definer, p.proconfig, p.proacl::text as acl,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
-- from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()');
--
-- c) BEFORE and AFTER: pending items that the trigger blocks (the student has an active
--    hold of the item's department). These cannot be cleared until the hold is lifted.
-- select ci.clearance_item_id, ci.clearance_id, c.student_id, d.code as department,
--        h.hold_id, h.placed_at
-- from public.clearance_items ci
-- join public.clearances c on c.clearance_id = ci.clearance_id
-- join public.departments d on d.department_id = ci.department_id
-- join public.academic_holds h on h.student_id = c.student_id
--                             and h.department_id = ci.department_id and h.lifted_at is null
-- where ci.cleared_at is null
-- order by 1, h.hold_id;
--
-- d) Already-cleared items whose student has an active hold of the same department
--    (cleared before the hold, before this trigger, or in the race in the header). The
--    trigger does not change them; the department decides whether to un-clear them.
-- select ci.clearance_item_id, ci.cleared_at, h.hold_id, h.placed_at,
--        (h.placed_at > ci.cleared_at) as hold_placed_after_approval
-- from public.clearance_items ci
-- join public.clearances c on c.clearance_id = ci.clearance_id
-- join public.academic_holds h on h.student_id = c.student_id
--                             and h.department_id = ci.department_id and h.lifted_at is null
-- where ci.cleared_at is not null
-- order by 1, h.hold_id;
