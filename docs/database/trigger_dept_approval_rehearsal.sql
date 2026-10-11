-- ==========================================
-- REHEARSAL: trigger_dept_approval.sql + TC-41 to TC-48 in ONE rolled-back transaction
-- ==========================================
-- GitHub issue #61 (issue 22). One paste, one run, ONE result row, nothing committed.
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file (from
-- "begin;" to "rollback;") and click Run on the whole tab, never a selection. If the
-- script stops with an error, run "rollback;" as its own query and send the error back.
--
-- What it does:
--   1. begin;
--   2. the body of docs/database/trigger_dept_approval.sql (everything between its
--      "BEGIN;" and "COMMIT;" lines, copied verbatim: safety checks, function, grants,
--      trigger, checks after the change). A "trigger_dept_approval: ..." error here means
--      the live state is not what the file assumes: do NOT run the file live.
--   3. TC-41 to TC-48 (docs/database/trigger_dept_approval_test.sql), combined: the test
--      data is created once as postgres (a throwaway term, a clearance for Student 1 with
--      one pending item per department), and before each case every active hold of
--      Student 1 is lifted and the items are set back to pending, so each case starts
--      from the same known state. Each result is stored with set_config('app.rNN', ...).
--   4. One final row: one cell per case, each ending in "-> OK" or "-> FAIL", plus
--      "all_ok". Compare with Part J of docs/issue-12-testing-guide.md.
--   5. rollback; (the trigger, the function, the grants and all test data disappear)
--
-- Every statement that is expected to fail runs inside a do block with an exception
-- handler, so the transaction is never aborted by an expected error.
--
-- Status: run 2026-10-11 on the live project (rolled back): all_ok true.

begin;

-- ==========================================
-- 1. The change (body of trigger_dept_approval.sql, verbatim)
-- ==========================================

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


-- ==========================================
-- 2. Test data (as postgres; undone by the rollback)
-- ==========================================
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.dept', coalesce((select id::text from auth.users where email = 'dept@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.mydept', coalesce((select min(department_id)::text from public.department_staff
  where profile_id::text = current_setting('app.dept')), ''), true);
select set_config('app.fin', coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.otherdept', coalesce((select min(department_id)::text from public.departments
  where department_type <> 'Financial' and department_id::text <> current_setting('app.mydept')), ''), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.dept'), current_setting('app.cash'),
            current_setting('app.mydept'), current_setting('app.fin'), current_setting('app.otherdept'))
     or current_setting('app.mydept') = current_setting('app.fin')
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1')) then
    raise exception 'TC setup: seed account, student or department missing (s1 [%], dept [%], cash [%], mydept [%], fin [%], otherdept [%])',
      current_setting('app.s1'), current_setting('app.dept'), current_setting('app.cash'),
      current_setting('app.mydept'), current_setting('app.fin'), current_setting('app.otherdept');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
-- the clearance trigger normally created the items; add them only if it did not
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where d.department_id::text in (current_setting('app.mydept'), current_setting('app.fin'))
  and not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_dept', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.mydept')::bigint), true);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);

-- The reset used before every case (as postgres): no active hold for Student 1, every
-- item of the test clearance pending. Setting cleared_at to NULL is not checked by the
-- trigger, so the reset never fails.
-- (repeated inline below as "reset")

-- ==========================================
-- 3. TC-41: installed as intended (catalog)
-- ==========================================
select set_config('app.r41', (select format('order [%s], enabled %s, type %s, when %s, secdef %s, config [%s], owner %s, owner_bypasses_rls %s -> %s',
    x.trigger_order, x.trigger_enabled, x.trigger_type, x.has_when, x.secdef, x.config, x.owner, x.bypass,
    case when x.trigger_order = 'guard_immutable_columns (BEFORE) > require_no_active_hold (BEFORE) > audit_log (AFTER)'
          and x.trigger_enabled = 'O' and x.trigger_type = 19 and x.has_when and x.secdef
          and x.config in ('search_path=""', 'search_path=''''') and x.bypass
         then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(tg.tgname::text || ' (' || case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end || ')', ' > '
                       order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.clearance_items'::regclass and not tg.tgisinternal) as trigger_order,
    (select tg.tgenabled::text from pg_trigger tg
      where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold'
        and tg.tgfoid = to_regprocedure('private.require_no_active_hold()')) as trigger_enabled,
    (select tg.tgtype::int from pg_trigger tg
      where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold') as trigger_type,
    (select tg.tgqual is not null from pg_trigger tg
      where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold') as has_when,
    (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) as secdef,
    (select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) as config,
    (select pg_get_userbyid(p.proowner)::text from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) as owner,
    (select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
       from pg_class c
       cross join pg_proc p
       join pg_roles r on r.oid = p.proowner
      where p.oid = to_regprocedure('private.require_no_active_hold()')
        and c.oid in ('public.clearances'::regclass, 'public.academic_holds'::regclass)) as bypass) x), true);

-- ==========================================
-- 4. TC-42 (a): approval fails with an active hold of the same department
-- ==========================================
-- reset
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
update public.clearance_items set cleared_at = null, cleared_by = null, remarks = null
where clearance_id = current_setting('app.clr')::bigint;
-- arrange
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-42 test hold', current_setting('app.dept')::uuid);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Department user
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t42_dept', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.t42_dept',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
-- act as postgres (the rule applies to every role)
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = current_setting('app.dept')::uuid
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t42_pg', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.t42_pg',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
select set_config('app.t42_pending', (select (cleared_at is null)::text from public.clearance_items
  where clearance_item_id = current_setting('app.item_dept')::bigint), true);
select set_config('app.t42_audit', (select count(*)::text from public.audit_logs
  where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearance_items'
    and record_id = current_setting('app.item_dept')), true);
select set_config('app.r42', format('department [%s], postgres [%s], still_pending %s, audit_rows %s -> %s',
  current_setting('app.t42_dept'), current_setting('app.t42_pg'),
  current_setting('app.t42_pending'), current_setting('app.t42_audit'),
  case when current_setting('app.t42_dept') like 'blocked [P0001]: active hold:%'
        and current_setting('app.t42_pg') like 'blocked [P0001]: active hold:%'
        and current_setting('app.t42_pending') = 'true' and current_setting('app.t42_audit') = '0'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 5. TC-43 (b): approval succeeds after the hold is lifted
-- ==========================================
-- reset
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
update public.clearance_items set cleared_at = null, cleared_by = null, remarks = null
where clearance_id = current_setting('app.clr')::bigint;
-- arrange
with h as (insert into public.academic_holds (student_id, department_id, reason, placed_by)
           values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-43 test hold',
                   current_setting('app.dept')::uuid) returning hold_id)
select set_config('app.hold', hold_id::text, true) from h;
-- act as the Department user: try, lift own hold, try again
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'before_lift', $q$update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
                          where clearance_item_id = current_setting('app.item_dept')::bigint$q$),
    (2, 'lift_hold',   $q$update public.academic_holds set lifted_by = auth.uid(), lifted_at = now()
                          where hold_id = current_setting('app.hold')::bigint$q$),
    (3, 'after_lift',  $q$update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
                          where clearance_item_id = current_setting('app.item_dept')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t43_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t43_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('app.r43', format('before_lift [%s], lift_hold [%s], after_lift [%s] -> %s',
  current_setting('app.t43_before_lift'), current_setting('app.t43_lift_hold'), current_setting('app.t43_after_lift'),
  case when current_setting('app.t43_before_lift') like 'blocked [P0001]: active hold:%'
        and current_setting('app.t43_lift_hold') = 'rows 1'
        and current_setting('app.t43_after_lift') = 'rows 1'
        and (select cleared_at is not null from public.clearance_items
              where clearance_item_id = current_setting('app.item_dept')::bigint)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 6. TC-44 (c): a hold of another department does not block
-- ==========================================
-- reset
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
update public.clearance_items set cleared_at = null, cleared_by = null, remarks = null
where clearance_id = current_setting('app.clr')::bigint;
-- arrange
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.otherdept')::bigint, 'TC-44 other department hold',
        current_setting('app.dept')::uuid);
-- act as the Department user
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t44', 'rows ' || n, true);
exception when others then
  perform set_config('app.t44',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('app.r44', format('other_department_hold_active %s, department_approval [%s] -> %s',
  (select count(*) > 0 from public.academic_holds
    where student_id = current_setting('app.s1')::uuid and lifted_at is null
      and department_id = current_setting('app.otherdept')::bigint),
  current_setting('app.t44'),
  case when current_setting('app.t44') = 'rows 1'
        and exists (select 1 from public.academic_holds
                     where student_id = current_setting('app.s1')::uuid and lifted_at is null
                       and department_id = current_setting('app.otherdept')::bigint)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 7. TC-45 (d): Cashier's Financial item: Department hold does not block, Financial hold does
-- ==========================================
-- reset
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
update public.clearance_items set cleared_at = null, cleared_by = null, remarks = null
where clearance_id = current_setting('app.clr')::bigint;
-- step 1: a Department (academic) hold only
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-45 department hold',
        current_setting('app.dept')::uuid);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
  where clearance_item_id = current_setting('app.item_fin')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t45_dept_hold', 'rows ' || n, true);
exception when others then
  perform set_config('app.t45_dept_hold',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
-- step 2: back to pending and a Financial hold
update public.clearance_items set cleared_at = null, cleared_by = null
where clearance_item_id = current_setting('app.item_fin')::bigint;
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.fin')::bigint, 'TC-45 financial hold',
        current_setting('app.cash')::uuid);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
  where clearance_item_id = current_setting('app.item_fin')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t45_fin_hold', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.t45_fin_hold',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('app.r45', format('with_department_hold [%s], with_financial_hold [%s] -> %s',
  current_setting('app.t45_dept_hold'), current_setting('app.t45_fin_hold'),
  case when current_setting('app.t45_dept_hold') = 'rows 1'
        and current_setting('app.t45_fin_hold') like 'blocked [P0001]: active hold:%'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 8. TC-46 (e): a successful approval writes an audit row
-- ==========================================
-- reset
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
update public.clearance_items set cleared_at = null, cleared_by = null, remarks = null
where clearance_id = current_setting('app.clr')::bigint;
-- arrange: mark the audit log after the reset (the reset itself is audited)
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Department user
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid(), remarks = 'TC-46'
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t46', 'rows ' || n, true);
exception when others then
  perform set_config('app.t46',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('app.r46', (select format('approval [%s], audit_rows %s, actor_is_dept %s, action %s, old_cleared_at_null %s, new_cleared_by_is_dept %s -> %s',
    current_setting('app.t46'), a.audit_rows, a.actor_is_dept, coalesce(a.action, '-'),
    a.old_cleared_at_null, a.new_cleared_by_is_dept,
    case when current_setting('app.t46') = 'rows 1' and a.audit_rows = 1 and a.actor_is_dept
          and a.action = 'UPDATE' and a.old_cleared_at_null and a.new_cleared_by_is_dept
         then 'OK' else 'FAIL' end)
  from (select count(*) as audit_rows,
               coalesce(bool_and(l.actor_id = current_setting('app.dept')::uuid), false) as actor_is_dept,
               string_agg(distinct l.action::text, ',') as action,
               coalesce(bool_and(l.old_data ->> 'cleared_at' is null), false) as old_cleared_at_null,
               coalesce(bool_and(l.new_data ->> 'cleared_by' = current_setting('app.dept')), false) as new_cleared_by_is_dept
        from public.audit_logs l
        where l.log_id > current_setting('app.log_mark')::bigint
          and l.table_name = 'clearance_items'
          and l.record_id = current_setting('app.item_dept')) a), true);

-- ==========================================
-- 9. TC-47 (f): already-cleared item: remarks, timestamp correction, un-clear not blocked; re-clear blocked
-- ==========================================
-- reset
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
update public.clearance_items set cleared_at = null, cleared_by = null, remarks = null
where clearance_id = current_setting('app.clr')::bigint;
-- arrange: cleared first (no hold yet), then the hold
update public.clearance_items set cleared_at = now(), cleared_by = current_setting('app.dept')::uuid
where clearance_item_id = current_setting('app.item_dept')::bigint;
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-47 test hold',
        current_setting('app.dept')::uuid);
-- act as the Department user
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'edit_remarks',       $q$update public.clearance_items set remarks = 'TC-47 remark', cleared_by = auth.uid()
                                 where clearance_item_id = current_setting('app.item_dept')::bigint$q$),
    (2, 'correct_cleared_at', $q$update public.clearance_items set cleared_at = now() - interval '1 minute', cleared_by = auth.uid()
                                 where clearance_item_id = current_setting('app.item_dept')::bigint$q$),
    (3, 'unclear',            $q$update public.clearance_items set cleared_at = null, cleared_by = auth.uid()
                                 where clearance_item_id = current_setting('app.item_dept')::bigint$q$),
    (4, 'reclear',            $q$update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
                                 where clearance_item_id = current_setting('app.item_dept')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t47_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t47_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('app.r47', format('edit_remarks [%s], correct_cleared_at [%s], unclear [%s], reclear [%s] -> %s',
  current_setting('app.t47_edit_remarks'), current_setting('app.t47_correct_cleared_at'),
  current_setting('app.t47_unclear'), current_setting('app.t47_reclear'),
  case when current_setting('app.t47_edit_remarks') = 'rows 1'
        and current_setting('app.t47_correct_cleared_at') = 'rows 1'
        and current_setting('app.t47_unclear') = 'rows 1'
        and current_setting('app.t47_reclear') like 'blocked [P0001]: active hold:%'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 10. TC-48 (g): function privileges; anon cannot call it
-- ==========================================
set local role anon;
do $$
begin
  perform private.require_no_active_hold();
  perform set_config('app.t48_anon', 'NOT DENIED', true);
exception when others then
  perform set_config('app.t48_anon',
    case when sqlerrm like 'permission denied%' then 'denied: ' else 'OTHER [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
begin
  perform private.require_no_active_hold();
  perform set_config('app.t48_auth', 'NO ERROR', true);
exception when others then
  perform set_config('app.t48_auth', 'error [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select set_config('app.r48', (select format('anon_execute %s, authenticated_execute %s, public_in_acl %s, security_definer %s, anon_call [%s], authenticated_call [%s] -> %s',
    f.anon_execute, f.authenticated_execute, f.public_in_acl, f.security_definer,
    current_setting('app.t48_anon'), current_setting('app.t48_auth'),
    case when not f.anon_execute and f.authenticated_execute and not f.public_in_acl and f.security_definer
          and current_setting('app.t48_anon') like 'denied: %'
          and current_setting('app.t48_auth') like 'error %'
         then 'OK' else 'FAIL' end)
  from (select has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
               has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
               (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)) as public_in_acl,
               p.prosecdef as security_definer
        from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) f), true);

-- ==========================================
-- Result: ONE row. Every cell must end in "-> OK"; all_ok must be true.
-- ==========================================
select (current_setting('app.r41') like '%-> OK' and current_setting('app.r42') like '%-> OK'
        and current_setting('app.r43') like '%-> OK' and current_setting('app.r44') like '%-> OK'
        and current_setting('app.r45') like '%-> OK' and current_setting('app.r46') like '%-> OK'
        and current_setting('app.r47') like '%-> OK' and current_setting('app.r48') like '%-> OK') as all_ok,
  current_setting('app.r41') as tc41, current_setting('app.r42') as tc42, current_setting('app.r43') as tc43,
  current_setting('app.r44') as tc44, current_setting('app.r45') as tc45, current_setting('app.r46') as tc46,
  current_setting('app.r47') as tc47, current_setting('app.r48') as tc48;

rollback;
