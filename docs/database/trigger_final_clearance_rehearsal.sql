-- ==========================================
-- REHEARSAL: trigger_final_clearance.sql + TC-62 to TC-70 in ONE rolled-back transaction
-- ==========================================
-- GitHub issue #63 (issue 24). One paste, one run, ONE result row, nothing committed.
-- This is TC-62R in Part L of docs/issue-12-testing-guide.md.
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file (from
-- "begin;" to "rollback;") and click Run on the whole tab, never a selection. If the
-- script stops with an error, run "rollback;" as its own query and send the error back.
--
-- What it does:
--   1. begin;
--   2. the body of docs/database/trigger_final_clearance.sql (everything between its
--      "BEGIN;" and "COMMIT;" lines, copied verbatim: safety checks, function, grants,
--      trigger, checks after the change). A "trigger_final_clearance: ..." error here
--      means the live state is not what the file assumes: do NOT run the file live.
--   3. TC-62 to TC-70 (docs/database/trigger_final_clearance_test.sql), combined. Every
--      case creates its own throwaway term and clearance for Student 1 as postgres, and
--      first lifts every active hold of Student 1, so the cases do not depend on each
--      other. Each result is stored with set_config('app.rNN', ...).
--   4. One final row: one cell per case, each ending in "-> OK" or "-> FAIL", plus
--      "all_ok". Compare with Part L of docs/issue-12-testing-guide.md. (Booleans inside
--      the cells may print as t / f.)
--   5. rollback; (the trigger, the function, the grants and all test data disappear)
--
-- RUNNING ONLY THE TESTS (after the change is live): the test part starts at the line
-- "-- TESTS START HERE" (line 292 of this file; its "begin;" is line 299) and is
-- self-contained: copy from the "begin;" line right below that marker to the end of the
-- file into a new tab and run it. It ends in rollback, so it changes nothing.
--
-- Every statement that is expected to fail runs inside a do block with an exception
-- handler, so the transaction is never aborted by an expected error.
--
-- Status: run 2026-10-11 on the live project (rolled back): all_ok true (after fixing TC-68 and TC-69, see the test file).

begin;

-- ==========================================
-- 1. The change (body of trigger_final_clearance.sql, verbatim)
-- ==========================================

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



-- ==========================================
-- TESTS START HERE (TC-62 to TC-70)
-- ==========================================
-- To run ONLY the tests once trigger_final_clearance.sql is live: copy from the next
-- line ("begin;") to the end of this file into a new tab and run that tab as a whole.
-- In the full rehearsal the next line is a second BEGIN inside the open transaction;
-- PostgreSQL only answers "WARNING: there is already a transaction in progress" and
-- carries on (nothing is committed either way; the file ends in rollback).
begin;

-- ==========================================
-- 2. Accounts and ids used by every case (as postgres, no user JWT)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.reg',  coalesce((select id::text from auth.users where email = 'registrar@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.dept', coalesce((select id::text from auth.users where email = 'dept@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.mydept', coalesce((select min(department_id)::text from public.department_staff
  where profile_id::text = current_setting('app.dept')), ''), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.reg'), current_setting('app.cash'),
            current_setting('app.dept'), current_setting('app.adm'), current_setting('app.fin'),
            current_setting('app.mydept'))
     or current_setting('app.mydept') = current_setting('app.fin')
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.reg') and p.is_active and r.role_name = 'Registrar')
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier')
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.dept') and p.is_active and r.role_name = 'Department') then
    raise exception 'TC setup: seed account, student or department missing, or a seed account is not active with its role (s1 [%], reg [%], cash [%], dept [%], adm [%], fin [%], mydept [%])',
      current_setting('app.s1'), current_setting('app.reg'), current_setting('app.cash'),
      current_setting('app.dept'), current_setting('app.adm'), current_setting('app.fin'),
      current_setting('app.mydept');
  end if;
end $$;

-- Every case below creates its OWN throwaway term and clearance, and first lifts every
-- active hold of Student 1, so the cases do not depend on each other. After each
-- impersonated step the script goes back to postgres and clears request.jwt.claims
-- ("postgres" = no user JWT, auth.uid() NULL).

-- ==========================================
-- 3. TC-62: installed as intended (catalog)
-- ==========================================
select set_config('app.r62', (select format('order [%s], trigger [%s], secdef %s, config [%s], owner %s, owner_bypasses_rls %s, registrar_policy_ok %s, other_update_policies [%s] -> %s',
    x.clearances_order, x.clearances_trigger, x.secdef, x.config, x.owner, x.bypass, x.policy_ok, x.other_policies,
    case when x.clearances_order = 'guard_immutable_columns (BEFORE) > require_all_items_cleared (BEFORE) > audit_log (AFTER) > trg_clearances_create_items (AFTER)'
          and x.clearances_trigger = 'O, type 19, when true'
          and x.secdef and x.config in ('search_path=""', 'search_path=''''') and x.bypass
          and x.policy_ok and x.other_policies = ''
         then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(tg.tgname::text || ' (' || case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end || ')', ' > '
                       order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.clearances'::regclass and not tg.tgisinternal) as clearances_order,
    (select tg.tgenabled::text || ', type ' || tg.tgtype || ', when ' || case when tg.tgqual is not null then 'true' else 'false' end
       from pg_trigger tg
      where tg.tgrelid = 'public.clearances'::regclass and tg.tgname = 'require_all_items_cleared'
        and tg.tgfoid = to_regprocedure('private.require_all_items_cleared()')) as clearances_trigger,
    (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) as secdef,
    (select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) as config,
    (select pg_get_userbyid(p.proowner)::text from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) as owner,
    coalesce((select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
                from pg_class c
                cross join pg_proc p
                join pg_roles r on r.oid = p.proowner
               where p.oid = to_regprocedure('private.require_all_items_cleared()')
                 and c.oid in ('public.clearance_items'::regclass, 'public.departments'::regclass)), false) as bypass,
    exists (select 1 from pg_policies p
             where p.schemaname = 'public' and p.tablename = 'clearances'
               and p.policyname = 'clearances_registrar_approve' and p.cmd = 'UPDATE'
               and position('''Registrar''' in coalesce(p.qual, '')) > 0
               and position('active_uid' in coalesce(p.with_check, '')) > 0
               and position('IS NULL' in upper(coalesce(p.with_check, ''))) = 0) as policy_ok,
    coalesce((select string_agg(p.policyname::text, ', ') from pg_policies p
               where p.schemaname = 'public' and p.tablename = 'clearances' and p.cmd in ('UPDATE', 'ALL')
                 and p.policyname <> 'clearances_registrar_approve'), '') as other_policies) x), true);

-- ==========================================
-- 4. TC-63 (a): one department item pending, Registrar and postgres are blocked
-- ==========================================
-- reset and arrange (as postgres, no user JWT): Student 1 without active holds, a new
-- throwaway term, a clearance for Student 1 in it with one pending item per department
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2081-2082', '1st', '2081-08-01', '2082-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.total', (select count(*)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint), true);
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null
  and clearance_item_id <> current_setting('app.item_dept')::bigint;
select set_config('app.t63_expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
select set_config('app.t63_expect_detail', 'pending departments: ' || (select code from public.departments
  where department_id = current_setting('app.mydept')::bigint) || ' (item ' || current_setting('app.item_dept') || ')', true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint; v_detail text;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t63_reg', 'rows ' || n, true);
  perform set_config('app.t63_detail', '', true);
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  perform set_config('app.t63_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
  perform set_config('app.t63_detail', coalesce(v_detail, ''), true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = current_setting('app.reg')::uuid, approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t63_pg', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.t63_pg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
select set_config('app.r63', format('registrar [%s], detail [%s], postgres [%s], still_not_approved %s, audit_rows %s -> %s',
  current_setting('app.t63_reg'), current_setting('app.t63_detail'), current_setting('app.t63_pg'),
  coalesce((select approved_at is null and approved_by is null from public.clearances
             where clearance_id = current_setting('app.clr')::bigint), false),
  (select count(*) from public.audit_logs
    where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
      and record_id = current_setting('app.clr')),
  case when left(current_setting('app.t63_reg'), length(current_setting('app.t63_expect'))) = current_setting('app.t63_expect')
        and current_setting('app.t63_detail') = current_setting('app.t63_expect_detail')
        and left(current_setting('app.t63_pg'), length(current_setting('app.t63_expect'))) = current_setting('app.t63_expect')
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
        and (select count(*) from public.audit_logs
              where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
                and record_id = current_setting('app.clr')) = 0
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 5. TC-64 (b): only the Financial item pending, the Registrar is blocked
-- ==========================================
-- reset and arrange (as postgres, no user JWT): Student 1 without active holds, a new
-- throwaway term, a clearance for Student 1 in it with one pending item per department
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2083-2084', '1st', '2083-08-01', '2084-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.total', (select count(*)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint), true);
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null
  and clearance_item_id <> current_setting('app.item_fin')::bigint;
select set_config('app.t64_expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
select set_config('app.t64_expect_detail', 'pending departments: ' || (select code from public.departments
  where department_id = current_setting('app.fin')::bigint) || ' (item ' || current_setting('app.item_fin') || ')', true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint; v_detail text;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t64_reg', 'rows ' || n, true);
  perform set_config('app.t64_detail', '', true);
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  perform set_config('app.t64_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
  perform set_config('app.t64_detail', coalesce(v_detail, ''), true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r64', format('registrar [%s], detail [%s], financial_item_pending %s, still_not_approved %s -> %s',
  current_setting('app.t64_reg'), current_setting('app.t64_detail'),
  coalesce((select cleared_at is null from public.clearance_items
             where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  coalesce((select approved_at is null and approved_by is null from public.clearances
             where clearance_id = current_setting('app.clr')::bigint), false),
  case when left(current_setting('app.t64_reg'), length(current_setting('app.t64_expect'))) = current_setting('app.t64_expect')
        and current_setting('app.t64_detail') = current_setting('app.t64_expect_detail')
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 6. TC-65 (c): every item cleared, the Registrar approves, one audit row
-- ==========================================
-- reset and arrange (as postgres, no user JWT): Student 1 without active holds, a new
-- throwaway term, a clearance for Student 1 in it with one pending item per department
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2085-2086', '1st', '2085-08-01', '2086-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.total', (select count(*)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint), true);
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint; v_detail text;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t65_reg', 'rows ' || n, true);
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  perform set_config('app.t65_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm || ' (' || coalesce(v_detail, '') || ')', true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r65', format('registrar [%s], approved_by_registrar %s, status %s, audit_rows %s, audit_ok %s -> %s',
  current_setting('app.t65_reg'),
  coalesce((select approved_at is not null and approved_by::text = current_setting('app.reg')
              from public.clearances where clearance_id = current_setting('app.clr')::bigint), false),
  coalesce((select status from public.v_clearances where clearance_id = current_setting('app.clr')::bigint), 'none'),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
      and l.record_id = current_setting('app.clr')),
  coalesce((select bool_and(l.action = 'UPDATE' and l.actor_id::text = current_setting('app.reg')
                            and (l.old_data ->> 'approved_at') is null
                            and (l.new_data ->> 'approved_by') = current_setting('app.reg'))
              from public.audit_logs l
             where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
               and l.record_id = current_setting('app.clr')), false),
  case when current_setting('app.t65_reg') = 'rows 1'
        and coalesce((select approved_at is not null and approved_by::text = current_setting('app.reg')
                        from public.clearances where clearance_id = current_setting('app.clr')::bigint), false)
        and coalesce((select status = 'Approved' from public.v_clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
                and l.record_id = current_setting('app.clr')) = 1
        and coalesce((select bool_and(l.action = 'UPDATE' and l.actor_id::text = current_setting('app.reg')
                                      and (l.old_data ->> 'approved_at') is null
                                      and (l.new_data ->> 'approved_by') = current_setting('app.reg'))
                        from public.audit_logs l
                       where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
                         and l.record_id = current_setting('app.clr')), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 7. TC-66 (d): every item cleared, Student / Cashier / Department still blocked by the policy
-- ==========================================
-- reset and arrange (as postgres, no user JWT): Student 1 without active holds, a new
-- throwaway term, a clearance for Student 1 in it with one pending item per department
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2087-2088', '1st', '2087-08-01', '2088-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.total', (select count(*)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint), true);
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'student',    's1'),
    (2, 'cashier',    'cash'),
    (3, 'department', 'dept'),
    (4, 'registrar',  'reg')
  ) as t(ord, label, who) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      update public.clearances set approved_by = auth.uid(), approved_at = now()
      where clearance_id = current_setting('app.clr')::bigint;
      get diagnostics n = row_count;
      perform set_config('app.t66_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t66_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r66', format('student [%s], cashier [%s], department [%s], registrar_after [%s], audit_rows %s -> %s',
  current_setting('app.t66_student'), current_setting('app.t66_cashier'),
  current_setting('app.t66_department'), current_setting('app.t66_registrar'),
  (select count(*) from public.audit_logs
    where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
      and record_id = current_setting('app.clr')),
  case when (current_setting('app.t66_student') = 'rows 0' or current_setting('app.t66_student') like 'rls: %')
        and (current_setting('app.t66_cashier') = 'rows 0' or current_setting('app.t66_cashier') like 'rls: %')
        and (current_setting('app.t66_department') = 'rows 0' or current_setting('app.t66_department') like 'rls: %')
        and current_setting('app.t66_registrar') = 'rows 1'
        and coalesce((select approved_at is not null and approved_by::text = current_setting('app.reg')
                        from public.clearances where clearance_id = current_setting('app.clr')::bigint), false)
        and (select count(*) from public.audit_logs
              where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
                and record_id = current_setting('app.clr')) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 8. TC-67 (e): zero items, the Registrar and postgres are blocked
-- ==========================================
-- reset and arrange (as postgres, no user JWT): Student 1 without active holds, a new
-- throwaway term, a clearance for Student 1 in it with one pending item per department
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2089-2090', '1st', '2089-08-01', '2090-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.total', (select count(*)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint), true);
delete from public.clearance_items where clearance_id = current_setting('app.clr')::bigint;
select set_config('app.t67_expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved because it has no clearance items', true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t67_reg', 'rows ' || n, true);
exception when others then
  perform set_config('app.t67_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = current_setting('app.reg')::uuid, approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t67_pg', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.t67_pg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
select set_config('app.r67', format('items_left %s, registrar [%s], postgres [%s], still_not_approved %s -> %s',
  (select count(*) from public.clearance_items where clearance_id = current_setting('app.clr')::bigint),
  current_setting('app.t67_reg'), current_setting('app.t67_pg'),
  coalesce((select approved_at is null and approved_by is null from public.clearances
             where clearance_id = current_setting('app.clr')::bigint), false),
  case when (select count(*) from public.clearance_items
              where clearance_id = current_setting('app.clr')::bigint) = 0
        and left(current_setting('app.t67_reg'), length(current_setting('app.t67_expect'))) = current_setting('app.t67_expect')
        and left(current_setting('app.t67_pg'), length(current_setting('app.t67_expect'))) = current_setting('app.t67_expect')
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 9. TC-68 (f): only approved_by, or only approved_at
-- ==========================================
-- reset and arrange (as postgres, no user JWT): Student 1 without active holds, a new
-- throwaway term, a clearance for Student 1 in it with one pending item per department
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2091-2092', '1st', '2091-08-01', '2092-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.total', (select count(*)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint), true);
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null
  and clearance_item_id <> current_setting('app.item_dept')::bigint;
select set_config('app.t68_expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
-- part 1: one item pending
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'by_pending', $q$update public.clearances set approved_by = auth.uid()
                         where clearance_id = current_setting('app.clr')::bigint$q$),
    (2, 'at_pending', $q$update public.clearances set approved_at = now()
                         where clearance_id = current_setting('app.clr')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t68_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t68_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
update public.clearance_items set cleared_at = now(), cleared_by = current_setting('app.dept')::uuid
where clearance_item_id = current_setting('app.item_dept')::bigint;
-- part 2a: only approved_by, every item cleared
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = auth.uid() where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t68_by_cleared', 'rows ' || n, true);
exception when others then
  perform set_config('app.t68_by_cleared',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.t68_status_by', coalesce((select status from public.v_clearances
  where clearance_id = current_setting('app.clr')::bigint), 'none'), true);
update public.clearances set approved_by = null where clearance_id = current_setting('app.clr')::bigint;
-- part 2b: only approved_at (approved_by NULL), every item cleared
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_at = now() where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t68_at_cleared', 'rows ' || n, true);
exception when others then
  perform set_config('app.t68_at_cleared',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r68', format('by_only_pending [%s], at_only_pending [%s], by_only_cleared [%s], status_after_by_only %s, at_only_cleared [%s], final_approved_at_null %s -> %s',
  current_setting('app.t68_by_pending'), current_setting('app.t68_at_pending'),
  current_setting('app.t68_by_cleared'), current_setting('app.t68_status_by'),
  current_setting('app.t68_at_cleared'),
  coalesce((select approved_at is null from public.clearances
             where clearance_id = current_setting('app.clr')::bigint), false),
  case when left(current_setting('app.t68_by_pending'), length(current_setting('app.t68_expect'))) = current_setting('app.t68_expect')
        and left(current_setting('app.t68_at_pending'), length(current_setting('app.t68_expect'))) = current_setting('app.t68_expect')
        and current_setting('app.t68_by_cleared') like 'ERROR [23514]%ck_clearances_approval%'
        and current_setting('app.t68_status_by') = 'In Progress'
        and current_setting('app.t68_at_cleared') like 'rls: %'
        and coalesce((select approved_at is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 10. TC-69 (g): edit and un-approve an approved clearance; re-approval is checked
-- ==========================================
-- reset and arrange (as postgres, no user JWT): Student 1 without active holds, a new
-- throwaway term, a clearance for Student 1 in it with one pending item per department
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2093-2094', '1st', '2093-08-01', '2094-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.total', (select count(*)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint), true);
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null;
select set_config('app.t69_expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t69_approve', 'rows ' || n, true);
exception when others then
  perform set_config('app.t69_approve',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = null, cleared_by = null
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t69_unclear', 'rows ' || n, true);
exception when others then
  perform set_config('app.t69_unclear', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'edit_at',   $q$update public.clearances set approved_at = now() - interval '1 hour', approved_by = auth.uid()
                        where clearance_id = current_setting('app.clr')::bigint$q$),
    (2, 'unapprove', $q$update public.clearances set approved_at = null, approved_by = auth.uid()
                        where clearance_id = current_setting('app.clr')::bigint$q$),
    (3, 'reapprove', $q$update public.clearances set approved_at = now(), approved_by = auth.uid()
                        where clearance_id = current_setting('app.clr')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t69_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t69_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'pg_unapprove', $q$update public.clearances set approved_at = null, approved_by = null
                           where clearance_id = current_setting('app.clr')::bigint$q$),
    (2, 'pg_reapprove', $q$update public.clearances set approved_at = now(), approved_by = current_setting('app.reg')::uuid
                           where clearance_id = current_setting('app.clr')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t69_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t69_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
select set_config('app.r69', format('approve [%s], unclear_item [%s], edit_approved_at [%s], unapprove [%s], reapprove [%s], postgres_unapprove [%s], postgres_reapprove [%s], final_not_approved %s -> %s',
  current_setting('app.t69_approve'), current_setting('app.t69_unclear'), current_setting('app.t69_edit_at'),
  current_setting('app.t69_unapprove'), current_setting('app.t69_reapprove'),
  current_setting('app.t69_pg_unapprove'), current_setting('app.t69_pg_reapprove'),
  coalesce((select approved_at is null and approved_by is null from public.clearances
             where clearance_id = current_setting('app.clr')::bigint), false),
  case when current_setting('app.t69_approve') = 'rows 1' and current_setting('app.t69_unclear') = 'rows 1'
        and current_setting('app.t69_edit_at') = 'rows 1' and current_setting('app.t69_unapprove') like 'ERROR [23514]%ck_clearances_approval%'
        and current_setting('app.t69_reapprove') = 'rows 1'
        and current_setting('app.t69_pg_unapprove') = 'rows 1'
        and left(current_setting('app.t69_pg_reapprove'), length(current_setting('app.t69_expect'))) = current_setting('app.t69_expect')
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 11. TC-70: function privileges; anon cannot call it
-- ==========================================
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform private.require_all_items_cleared();
  perform set_config('app.t70_anon', 'NOT DENIED', true);
exception when others then
  perform set_config('app.t70_anon',
    case when sqlerrm like 'permission denied%' then 'denied: ' else 'OTHER [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
begin
  perform private.require_all_items_cleared();
  perform set_config('app.t70_auth', 'NO ERROR', true);
exception when others then
  perform set_config('app.t70_auth', 'error [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r70', (select format('anon_execute %s, authenticated_execute %s, public_in_acl %s, security_definer %s, anon_call [%s], authenticated_call [%s] -> %s',
    f.anon_execute, f.authenticated_execute, f.public_in_acl, f.security_definer,
    current_setting('app.t70_anon'), current_setting('app.t70_auth'),
    case when not f.anon_execute and f.authenticated_execute and not f.public_in_acl and f.security_definer
          and current_setting('app.t70_anon') like 'denied: %'
          and current_setting('app.t70_auth') like 'error %'
         then 'OK' else 'FAIL' end)
  from (select has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
               has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
               (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)) as public_in_acl,
               p.prosecdef as security_definer
          from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) f), true);

-- ==========================================
-- Result: ONE row. Compare each cell with Part L of docs/issue-12-testing-guide.md
-- ==========================================
select (current_setting('app.r62') like '%-> OK' and current_setting('app.r63') like '%-> OK'
        and current_setting('app.r64') like '%-> OK' and current_setting('app.r65') like '%-> OK'
        and current_setting('app.r66') like '%-> OK' and current_setting('app.r67') like '%-> OK'
        and current_setting('app.r68') like '%-> OK' and current_setting('app.r69') like '%-> OK'
        and current_setting('app.r70') like '%-> OK') as all_ok,
  current_setting('app.r62') as tc62, current_setting('app.r63') as tc63, current_setting('app.r64') as tc64,
  current_setting('app.r65') as tc65, current_setting('app.r66') as tc66, current_setting('app.r67') as tc67,
  current_setting('app.r68') as tc68, current_setting('app.r69') as tc69, current_setting('app.r70') as tc70;

rollback;
