-- ==========================================
-- TESTS FOR trigger_dept_approval.sql (GitHub issue #61): TC-41 to TC-48
-- ==========================================
-- Part J of docs/issue-12-testing-guide.md explains each case and records the results.
-- To run the change AND all these tests in one rolled-back transaction (one paste, one
-- result row), use docs/database/trigger_dept_approval_rehearsal.sql instead.
--
-- Rules (same as Part I of the guide):
--   - Supabase SQL editor, as postgres, AFTER trigger_dept_approval.sql has been run. Run
--     ONE block at a time: copy one block, from its "begin;" line to its "rollback;" line
--     inclusive, into a new tab and run that tab as a whole (never a selection).
--   - Every block ends with "rollback;", so nothing is changed. If a block stops at an
--     unexpected error, run "rollback;" as its own query.
--   - Roles are impersonated as in grants_clearance_test.sql: the user ids are looked up
--     by e-mail (seed accounts *@pnc.test) as postgres, then "set local role
--     authenticated" (or anon) and request.jwt.claims = {"sub": <id>, "role":
--     "authenticated"} via set_config(..., true).
--   - The editor shows only the last result, so every block ends with ONE result row.
--     Expected errors are caught inside a do block and shown as text:
--       "blocked [P0001]: active hold: ..." = the new trigger stopped it
--       "denied: ..."                       = permission denied (grants)
--       "rls: ..."                          = new row violates row-level security policy
--       "rows N"                            = the statement ran and changed N rows
--     Every block ends with a verdict cell "-> OK" or "-> FAIL".
--   - No SKIPPED results: each block CREATES its own data as postgres inside the
--     transaction (undone by the rollback): a throwaway term, a clearance for Student 1
--     in that term (the clearance trigger creates one pending item per department), and
--     the holds it needs. It first lifts every active hold of Student 1 (also undone by
--     the rollback), so the starting state is known whatever the live data holds. If a
--     seed account or department is missing, the setup stops with
--     "TC setup: ..." instead of skipping.
--   - No temporary GRANT: these blocks use the real grants of grants_clearance.sql.
--
-- Status: TC-41 to TC-48 pass live (2026-10-11).
--
-- The SETUP part is the same in TC-42 to TC-47 (between the "setup" and "end of setup"
-- comments); only the part after it differs.


-- ------------------------------------------
-- TC-41. Installed as intended (catalog, read-only)
-- ------------------------------------------
-- Expected: trigger_order "guard_immutable_columns (BEFORE) > require_no_active_hold
-- (BEFORE) > audit_log (AFTER)", trigger_enabled "O", trigger_type 19 (BEFORE UPDATE ROW),
-- has_when true, function_security_definer true, function_config 'search_path=""',
-- function_owner postgres, owner_bypasses_rls true, verdict "-> OK".
begin;
select row_to_json(t) as tc41 from (select
  (select string_agg(x.tgname || ' (' || x.timing || ')', ' > ' order by x.ord, x.tgname)
     from (select tg.tgname::text as tgname,
                  case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
                  case when (tg.tgtype::int & 2) = 2 then 0 else 1 end as ord
             from pg_trigger tg
            where tg.tgrelid = 'public.clearance_items'::regclass and not tg.tgisinternal) x) as trigger_order,
  (select tg.tgenabled::text from pg_trigger tg
    where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold') as trigger_enabled,
  (select tg.tgtype from pg_trigger tg
    where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold') as trigger_type,
  (select tg.tgqual is not null from pg_trigger tg
    where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold') as has_when,
  (select pg_get_triggerdef(tg.oid) from pg_trigger tg
    where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold') as trigger_definition,
  (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) as function_security_definer,
  (select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) as function_config,
  (select pg_get_userbyid(p.proowner)::text from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) as function_owner,
  (select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
     from pg_class c
     cross join pg_proc p
     join pg_roles r on r.oid = p.proowner
    where p.oid = to_regprocedure('private.require_no_active_hold()')
      and c.oid in ('public.clearances'::regclass, 'public.academic_holds'::regclass)) as owner_bypasses_rls,
  case when
    (select string_agg(tg.tgname::text, ',' order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.clearance_items'::regclass and not tg.tgisinternal)
      = 'guard_immutable_columns,require_no_active_hold,audit_log'
    and exists (select 1 from pg_trigger tg
                 where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'require_no_active_hold'
                   and tg.tgenabled = 'O' and tg.tgtype = 19 and tg.tgqual is not null
                   and tg.tgfoid = to_regprocedure('private.require_no_active_hold()'))
    and exists (select 1 from pg_proc p
                 where p.oid = to_regprocedure('private.require_no_active_hold()') and p.prosecdef
                   and p.proconfig && array['search_path=""', 'search_path='''''])
  then '-> OK' else '-> FAIL' end as verdict) t;
rollback;


-- ------------------------------------------
-- TC-42. (a) Department approval fails with an active hold of the SAME department
-- ------------------------------------------
-- Student 1 gets an active hold of the Department user's department (CCS with the seed).
-- The Department user tries to clear that department's item; then postgres tries the same
-- (the rule applies to every role).
-- Expected: department_approval and postgres_approval both "blocked [P0001]: active
-- hold: clearance item ... cannot be cleared ...", item_still_pending true,
-- audit_rows_for_item 0, verdict "-> OK".
begin;
-- setup (as postgres; undone by the rollback)
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
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of setup
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-42 test hold', current_setting('app.dept')::uuid);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_dept', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.r_dept',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = current_setting('app.dept')::uuid
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_pg', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.r_pg',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
select current_setting('app.r_dept') as department_approval,
  current_setting('app.r_pg') as postgres_approval,
  (select cleared_at is null from public.clearance_items
    where clearance_item_id = current_setting('app.item_dept')::bigint) as item_still_pending,
  (select count(*) from public.audit_logs
    where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearance_items'
      and record_id = current_setting('app.item_dept')) as audit_rows_for_item,
  case when current_setting('app.r_dept') like 'blocked [P0001]: active hold:%'
        and current_setting('app.r_pg') like 'blocked [P0001]: active hold:%'
        and (select cleared_at is null from public.clearance_items
              where clearance_item_id = current_setting('app.item_dept')::bigint)
        and (select count(*) from public.audit_logs
              where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearance_items'
                and record_id = current_setting('app.item_dept')) = 0
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-43. (b) Approval succeeds after the hold is lifted
-- ------------------------------------------
-- Same hold as TC-42. The Department user first tries (blocked), then lifts the hold
-- through its own policy (holds_dept_lift: lifted_by = the caller, lifted_at set), then
-- clears the item again.
-- Expected: before_lift "blocked [P0001]: active hold: ...", lift_hold "rows 1",
-- after_lift "rows 1", item_cleared true, verdict "-> OK".
begin;
-- setup (as postgres; undone by the rollback)
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
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of setup
with h as (insert into public.academic_holds (student_id, department_id, reason, placed_by)
           values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-43 test hold',
                   current_setting('app.dept')::uuid) returning hold_id)
select set_config('app.hold', hold_id::text, true) from h;
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
      perform set_config('app.r_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select current_setting('app.r_before_lift') as before_lift,
  current_setting('app.r_lift_hold') as lift_hold,
  current_setting('app.r_after_lift') as after_lift,
  (select cleared_at is not null from public.clearance_items
    where clearance_item_id = current_setting('app.item_dept')::bigint) as item_cleared,
  case when current_setting('app.r_before_lift') like 'blocked [P0001]: active hold:%'
        and current_setting('app.r_lift_hold') = 'rows 1'
        and current_setting('app.r_after_lift') = 'rows 1'
        and (select cleared_at is not null from public.clearance_items
              where clearance_item_id = current_setting('app.item_dept')::bigint)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-44. (c) A hold of ANOTHER department does not block the approval
-- ------------------------------------------
-- Student 1 gets an active hold of another academic department (CBA with the seed; placed
-- as postgres). The Department user clears its own department's item.
-- Expected: other_department_hold_active true, department_approval "rows 1",
-- verdict "-> OK".
begin;
-- setup (as postgres; undone by the rollback)
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
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of setup
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.otherdept')::bigint, 'TC-44 other department hold',
        current_setting('app.dept')::uuid);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_dept', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_dept',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select (select count(*) > 0 from public.academic_holds
         where student_id = current_setting('app.s1')::uuid and lifted_at is null
           and department_id = current_setting('app.otherdept')::bigint) as other_department_hold_active,
  current_setting('app.r_dept') as department_approval,
  case when current_setting('app.r_dept') = 'rows 1'
        and exists (select 1 from public.academic_holds
                     where student_id = current_setting('app.s1')::uuid and lifted_at is null
                       and department_id = current_setting('app.otherdept')::bigint)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-45. (d) The Cashier's Financial item: not blocked by a Department hold, blocked by
--        a Financial hold
-- ------------------------------------------
-- Step 1: Student 1 has an active hold of the Department user's department only; the
-- Cashier clears the Financial item. Step 2 (postgres resets the item to pending and
-- places a hold of the Financial department): the Cashier tries again.
-- Expected: with_department_hold "rows 1", with_financial_hold "blocked [P0001]: active
-- hold: ...", verdict "-> OK".
begin;
-- setup (as postgres; undone by the rollback)
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
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of setup
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
  perform set_config('app.r_with_dept_hold', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_with_dept_hold',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
-- step 2: back to pending (cleared -> NULL is not checked) and a Financial hold
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
  perform set_config('app.r_with_fin_hold', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.r_with_fin_hold',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select current_setting('app.r_with_dept_hold') as with_department_hold,
  current_setting('app.r_with_fin_hold') as with_financial_hold,
  case when current_setting('app.r_with_dept_hold') = 'rows 1'
        and current_setting('app.r_with_fin_hold') like 'blocked [P0001]: active hold:%'
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-46. (e) A successful approval writes an audit row (existing audit_log trigger)
-- ------------------------------------------
-- No active hold. The Department user clears its item; the audit rows written after that
-- are read as postgres in the same transaction.
-- Expected: approval "rows 1", audit_rows 1, actor_is_dept true, action UPDATE,
-- old_cleared_at_null true, new_cleared_by_is_dept true, verdict "-> OK".
begin;
-- setup (as postgres; undone by the rollback)
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
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of setup
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid(), remarks = 'TC-46'
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_dept', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_dept',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select current_setting('app.r_dept') as approval, a.audit_rows, a.actor_is_dept, a.action,
  a.old_cleared_at_null, a.new_cleared_by_is_dept,
  case when current_setting('app.r_dept') = 'rows 1' and a.audit_rows = 1 and a.actor_is_dept
        and a.action = 'UPDATE' and a.old_cleared_at_null and a.new_cleared_by_is_dept
       then '-> OK' else '-> FAIL' end as verdict
from (select count(*) as audit_rows,
             coalesce(bool_and(l.actor_id = current_setting('app.dept')::uuid), false) as actor_is_dept,
             string_agg(distinct l.action::text, ',') as action,
             coalesce(bool_and(l.old_data ->> 'cleared_at' is null), false) as old_cleared_at_null,
             coalesce(bool_and(l.new_data ->> 'cleared_by' = current_setting('app.dept')), false) as new_cleared_by_is_dept
      from public.audit_logs l
      where l.log_id > current_setting('app.log_mark')::bigint
        and l.table_name = 'clearance_items'
        and l.record_id = current_setting('app.item_dept')) a;
rollback;


-- ------------------------------------------
-- TC-47. (f) Already-cleared item: remarks, timestamp correction and un-clearing are not
--        blocked; re-clearing is
-- ------------------------------------------
-- postgres clears the item (no hold yet), then places an active hold of the same
-- department. The Department user then: edits the remarks, corrects cleared_at (still
-- cleared), un-clears (cleared_at NULL; the live policy allows it while cleared_by = the
-- caller), and clears again.
-- Expected: edit_remarks "rows 1", correct_cleared_at "rows 1", unclear "rows 1",
-- reclear "blocked [P0001]: active hold: ...", verdict "-> OK".
begin;
-- setup (as postgres; undone by the rollback)
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
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of setup
update public.clearance_items set cleared_at = now(), cleared_by = current_setting('app.dept')::uuid
where clearance_item_id = current_setting('app.item_dept')::bigint;   -- no hold yet, so allowed
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-47 test hold',
        current_setting('app.dept')::uuid);
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
      perform set_config('app.r_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select current_setting('app.r_edit_remarks') as edit_remarks,
  current_setting('app.r_correct_cleared_at') as correct_cleared_at,
  current_setting('app.r_unclear') as unclear,
  current_setting('app.r_reclear') as reclear,
  case when current_setting('app.r_edit_remarks') = 'rows 1'
        and current_setting('app.r_correct_cleared_at') = 'rows 1'
        and current_setting('app.r_unclear') = 'rows 1'
        and current_setting('app.r_reclear') like 'blocked [P0001]: active hold:%'
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-48. (g) Function privileges; anon cannot call it
-- ------------------------------------------
-- Expected: anon_execute false, authenticated_execute true, public_in_acl false,
-- security_definer true, anon_call "denied: permission denied for ...",
-- authenticated_call an error (normally "trigger functions can only be called as
-- triggers"; "permission denied for schema private" is also fine), verdict "-> OK".
begin;
select set_config('app.dept', coalesce((select id::text from auth.users where email = 'dept@pnc.test'), ''), true);
set local role anon;
do $$
begin
  perform private.require_no_active_hold();
  perform set_config('app.r_anon', 'NOT DENIED', true);
exception when others then
  perform set_config('app.r_anon',
    case when sqlerrm like 'permission denied%' then 'denied: ' else 'OTHER [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
begin
  perform private.require_no_active_hold();
  perform set_config('app.r_auth', 'NO ERROR', true);
exception when others then
  perform set_config('app.r_auth', 'error [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select f.anon_execute, f.authenticated_execute, f.public_in_acl, f.security_definer,
  current_setting('app.r_anon') as anon_call, current_setting('app.r_auth') as authenticated_call,
  case when not f.anon_execute and f.authenticated_execute and not f.public_in_acl and f.security_definer
        and current_setting('app.r_anon') like 'denied: %'
        and current_setting('app.r_auth') like 'error %'
       then '-> OK' else '-> FAIL' end as verdict
from (select has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
             has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
             (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)) as public_in_acl,
             p.prosecdef as security_definer
      from pg_proc p where p.oid = to_regprocedure('private.require_no_active_hold()')) f;
rollback;
