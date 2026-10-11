-- ==========================================
-- TESTS FOR trigger_final_clearance.sql (GitHub issue #63): TC-62 to TC-70
-- ==========================================
-- Part L of docs/issue-12-testing-guide.md explains each case and records the results.
-- To run the change AND all these tests in one rolled-back transaction (one paste, one
-- result row), use docs/database/trigger_final_clearance_rehearsal.sql instead; its test
-- part can also be run on its own once the change is live.
--
-- Rules (same as Parts I, J and K of the guide):
--   - Supabase SQL editor, as postgres, AFTER trigger_final_clearance.sql has been run.
--     Run ONE block at a time: copy one block, from its "begin;" line to its "rollback;"
--     line inclusive, into a new tab and run that tab as a whole (never a selection).
--   - Every block ends with "rollback;", so nothing is changed. If a block stops at an
--     unexpected error, run "rollback;" as its own query.
--   - Roles are impersonated as in trigger_finance_autoclear_test.sql: the user ids are
--     looked up by e-mail (seed accounts *@pnc.test) as postgres, then "set local role
--     authenticated" (or anon) and request.jwt.claims = {"sub": <id>, "role":
--     "authenticated"} via set_config(..., true). After every impersonated step the block
--     goes back to postgres AND clears request.jwt.claims, so "postgres" always means
--     "no user JWT" (auth.uid() NULL), as in the SQL editor.
--   - The editor shows only the last result, so every block ends with ONE result row.
--     Expected errors are caught inside a do block and shown as text:
--       "blocked [P0001]: pending items: ..." = trigger require_all_items_cleared stopped it
--       "denied: ..."                         = permission denied (grants)
--       "rls: ..."                            = new row violates row-level security policy
--       "rows N"                              = the statement ran and changed N rows
--     The DETAIL of a "pending items" error (the pending departments) is shown in its own
--     cell. Every block ends with a verdict cell "-> OK" or "-> FAIL".
--   - No SKIPPED results: each block CREATES its own data as postgres inside the
--     transaction (undone by the rollback): a throwaway term (seed students already have
--     a clearance for the current term, and clearances are unique per student and term)
--     and a clearance for Student 1 in it (the clearance trigger creates one pending item
--     per department). It first lifts every active hold of Student 1, because
--     require_no_active_hold (issue 22) refuses to clear an item of a department with an
--     active hold, also for postgres. Items are cleared as postgres (cleared_by = the
--     Cashier for the Financial item, the Department user for its own department, the
--     Admin account for the others, as in seed.sql). The term has no charges, so the
--     Finance auto-clear (issue 23) never changes anything here. If a seed account or
--     department is missing, the setup stops with "TC setup: ..." instead of skipping.
--   - No temporary GRANT: these blocks use the real grants of grants_clearance.sql (the
--     Registrar has UPDATE (approved_by, approved_at) on clearances, like every signed-in
--     user; the policy clearances_registrar_approve decides who may use it).
--
-- Status: TC-62 to TC-70 pass live (2026-10-11).
--
-- The SETUP part is the same in TC-63 to TC-69 (between the "setup" and "end of common
-- setup" comments); only the part after it differs.


-- ------------------------------------------
-- TC-62. Installed as intended (catalog, read-only)
-- ------------------------------------------
-- Expected: clearances_order "guard_immutable_columns (BEFORE) > require_all_items_cleared
-- (BEFORE) > audit_log (AFTER) > trg_clearances_create_items (AFTER)", trigger
-- "O, type 19, when true" (BEFORE UPDATE FOR EACH ROW with a WHEN clause), the trigger
-- definition with the WHEN on approved_at / approved_by, function SECURITY DEFINER with
-- 'search_path=""', owner postgres, owner_bypasses_rls true, registrar_policy_ok true,
-- other_update_policies "" (empty), verdict "-> OK".
begin;
select row_to_json(t) as tc62 from (select
  (select string_agg(x.tgname::text || ' (' || x.timing || ')', ' > ' order by x.ord, x.tgname)
     from (select tg.tgname,
                  case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
                  case when (tg.tgtype::int & 2) = 2 then 0 else 1 end as ord
             from pg_trigger tg
            where tg.tgrelid = 'public.clearances'::regclass and not tg.tgisinternal) x) as clearances_order,
  (select tg.tgenabled::text || ', type ' || tg.tgtype || ', when ' || case when tg.tgqual is not null then 'true' else 'false' end
     from pg_trigger tg
    where tg.tgrelid = 'public.clearances'::regclass and tg.tgname = 'require_all_items_cleared') as clearances_trigger,
  (select pg_get_triggerdef(tg.oid) from pg_trigger tg
    where tg.tgrelid = 'public.clearances'::regclass and tg.tgname = 'require_all_items_cleared') as trigger_definition,
  (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) as function_security_definer,
  (select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) as function_config,
  (select pg_get_userbyid(p.proowner)::text from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) as function_owner,
  (select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
     from pg_class c
     cross join pg_proc p
     join pg_roles r on r.oid = p.proowner
    where p.oid = to_regprocedure('private.require_all_items_cleared()')
      and c.oid in ('public.clearance_items'::regclass, 'public.departments'::regclass)) as owner_bypasses_rls,
  exists (select 1 from pg_policies p
           where p.schemaname = 'public' and p.tablename = 'clearances'
             and p.policyname = 'clearances_registrar_approve' and p.cmd = 'UPDATE'
             and position('''Registrar''' in coalesce(p.qual, '')) > 0
             and position('active_uid' in coalesce(p.with_check, '')) > 0
             and position('IS NULL' in upper(coalesce(p.with_check, ''))) = 0) as registrar_policy_ok,
  coalesce((select string_agg(p.policyname::text, ', ') from pg_policies p
             where p.schemaname = 'public' and p.tablename = 'clearances' and p.cmd in ('UPDATE', 'ALL')
               and p.policyname <> 'clearances_registrar_approve'), '') as other_update_policies,
  case when
    (select string_agg(tg.tgname::text, ',' order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.clearances'::regclass and not tg.tgisinternal)
      = 'guard_immutable_columns,require_all_items_cleared,audit_log,trg_clearances_create_items'
    and exists (select 1 from pg_trigger tg
                 where tg.tgrelid = 'public.clearances'::regclass and tg.tgname = 'require_all_items_cleared'
                   and tg.tgenabled = 'O' and tg.tgtype = 19 and tg.tgqual is not null
                   and tg.tgfoid = to_regprocedure('private.require_all_items_cleared()'))
    and exists (select 1 from pg_proc p
                 where p.oid = to_regprocedure('private.require_all_items_cleared()') and p.prosecdef
                   and p.proconfig && array['search_path=""', 'search_path='''''])
    and coalesce((select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
                    from pg_class c cross join pg_proc p join pg_roles r on r.oid = p.proowner
                   where p.oid = to_regprocedure('private.require_all_items_cleared()')
                     and c.oid in ('public.clearance_items'::regclass, 'public.departments'::regclass)), false)
    and exists (select 1 from pg_policies p
                 where p.schemaname = 'public' and p.tablename = 'clearances'
                   and p.policyname = 'clearances_registrar_approve' and p.cmd = 'UPDATE'
                   and position('''Registrar''' in coalesce(p.qual, '')) > 0
                   and position('active_uid' in coalesce(p.with_check, '')) > 0
                   and position('IS NULL' in upper(coalesce(p.with_check, ''))) = 0)
    and not exists (select 1 from pg_policies p
                     where p.schemaname = 'public' and p.tablename = 'clearances' and p.cmd in ('UPDATE', 'ALL')
                       and p.policyname <> 'clearances_registrar_approve')
  then '-> OK' else '-> FAIL' end as verdict) t;
rollback;


-- ------------------------------------------
-- TC-63. (a) Approval fails while ONE department item is pending
-- ------------------------------------------
-- Student 1's clearance: every item cleared except the item of the Department user's
-- department (CCS with the seed). The Registrar approves it exactly as the app does
-- (approved_by = self, approved_at = now()); then postgres tries the same (the rule
-- applies to every role).
-- Expected: registrar_approval "blocked [P0001]: pending items: clearance <id> cannot be
-- approved while 1 of <T> items are not cleared" (T = number of departments, 4 with the
-- seed), registrar_detail "pending departments: CCS (item <id>)", postgres_approval the
-- same "blocked [P0001]: ..." text, still_not_approved true, audit_rows_for_clearance 0,
-- verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
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
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department (require_no_active_hold,
-- issue 22, would otherwise refuse to clear the items below)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- the clearance (the clearance trigger creates one pending item per department; add any
-- that is missing). No charges in this term, so finance_autoclear (issue 23) does nothing.
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
-- end of common setup
-- every item cleared except the Department user's item (as postgres)
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null
  and clearance_item_id <> current_setting('app.item_dept')::bigint;
select set_config('app.expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
select set_config('app.expect_detail', 'pending departments: ' || (select code from public.departments
  where department_id = current_setting('app.mydept')::bigint) || ' (item ' || current_setting('app.item_dept') || ')', true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Registrar
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint; v_detail text;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_reg', 'rows ' || n, true);
  perform set_config('app.d_reg', '', true);
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  perform set_config('app.r_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
  perform set_config('app.d_reg', coalesce(v_detail, ''), true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- postgres tries the same
do $$
declare n bigint;
begin
  update public.clearances set approved_by = current_setting('app.reg')::uuid, approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_pg', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.r_pg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
select current_setting('app.r_reg') as registrar_approval,
  current_setting('app.d_reg') as registrar_detail,
  current_setting('app.r_pg') as postgres_approval,
  (select approved_at is null and approved_by is null from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as still_not_approved,
  (select count(*) from public.audit_logs
    where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
      and record_id = current_setting('app.clr')) as audit_rows_for_clearance,
  case when left(current_setting('app.r_reg'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and current_setting('app.d_reg') = current_setting('app.expect_detail')
        and left(current_setting('app.r_pg'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
        and (select count(*) from public.audit_logs
              where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
                and record_id = current_setting('app.clr')) = 0
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-64. (b) Approval fails while ONLY the Financial item is pending
-- ------------------------------------------
-- Every academic department has cleared; the Cashier's Office (Financial) item is still
-- pending. The Registrar approves.
-- Expected: registrar_approval "blocked [P0001]: pending items: clearance <id> cannot be
-- approved while 1 of <T> items are not cleared", registrar_detail "pending departments:
-- CSH (item <id>)" (the Financial department's code), financial_item_pending true,
-- still_not_approved true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
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
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department (require_no_active_hold,
-- issue 22, would otherwise refuse to clear the items below)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- the clearance (the clearance trigger creates one pending item per department; add any
-- that is missing). No charges in this term, so finance_autoclear (issue 23) does nothing.
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
-- end of common setup
-- every item cleared except the Financial item (as postgres)
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null
  and clearance_item_id <> current_setting('app.item_fin')::bigint;
select set_config('app.expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
select set_config('app.expect_detail', 'pending departments: ' || (select code from public.departments
  where department_id = current_setting('app.fin')::bigint) || ' (item ' || current_setting('app.item_fin') || ')', true);
-- act as the Registrar
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint; v_detail text;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_reg', 'rows ' || n, true);
  perform set_config('app.d_reg', '', true);
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  perform set_config('app.r_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
  perform set_config('app.d_reg', coalesce(v_detail, ''), true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_reg') as registrar_approval,
  current_setting('app.d_reg') as registrar_detail,
  (select cleared_at is null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as financial_item_pending,
  (select approved_at is null and approved_by is null from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as still_not_approved,
  case when left(current_setting('app.r_reg'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and current_setting('app.d_reg') = current_setting('app.expect_detail')
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-65. (c) Approval succeeds when every item is cleared, and is audited
-- ------------------------------------------
-- Every item cleared (as postgres). The Registrar approves.
-- Expected: registrar_approval "rows 1", approved true, approved_by_registrar true,
-- status "Approved" (v_clearances), audit_rows 1, audit_action UPDATE,
-- audit_actor_is_registrar true, old_approved_at_null true, new_approved_by_is_registrar
-- true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
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
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department (require_no_active_hold,
-- issue 22, would otherwise refuse to clear the items below)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- the clearance (the clearance trigger creates one pending item per department; add any
-- that is missing). No charges in this term, so finance_autoclear (issue 23) does nothing.
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
-- end of common setup
-- every item cleared (as postgres)
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Registrar
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint; v_detail text;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_reg', 'rows ' || n, true);
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  perform set_config('app.r_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm || ' (' || coalesce(v_detail, '') || ')', true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_reg') as registrar_approval,
  (select approved_at is not null from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as approved,
  (select approved_by::text = current_setting('app.reg') from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as approved_by_registrar,
  (select status from public.v_clearances where clearance_id = current_setting('app.clr')::bigint) as status,
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
      and l.record_id = current_setting('app.clr')) as audit_rows,
  (select string_agg(l.action::text, ',') from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
      and l.record_id = current_setting('app.clr')) as audit_action,
  (select bool_and(l.actor_id::text = current_setting('app.reg')) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
      and l.record_id = current_setting('app.clr')) as audit_actor_is_registrar,
  (select bool_and((l.old_data ->> 'approved_at') is null) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
      and l.record_id = current_setting('app.clr')) as old_approved_at_null,
  (select bool_and((l.new_data ->> 'approved_by') = current_setting('app.reg')) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearances'
      and l.record_id = current_setting('app.clr')) as new_approved_by_is_registrar,
  case when current_setting('app.r_reg') = 'rows 1'
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
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-66. (d) Non-Registrar roles are still blocked by the policy (every item cleared)
-- ------------------------------------------
-- Every item is cleared, so the trigger would let the approval through: what stops
-- Student 1 (own clearance), the Cashier and the Department user is the policy
-- clearances_registrar_approve (USING role = Registrar filters the row out before any
-- trigger fires, so the UPDATE changes 0 rows). Then the Registrar approves the same
-- clearance (rows 1), which shows that the trigger was not what blocked the others.
-- Expected: student "rows 0", cashier "rows 0", department "rows 0" ("rls: ..." would also
-- be a Pass; "blocked [P0001]" or "rows 1" is a Fail), registrar_after "rows 1",
-- approved_by_registrar true, audit_rows 1 (only the Registrar's update), verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
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
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department (require_no_active_hold,
-- issue 22, would otherwise refuse to clear the items below)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- the clearance (the clearance trigger creates one pending item per department; add any
-- that is missing). No charges in this term, so finance_autoclear (issue 23) does nothing.
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
-- end of common setup
-- every item cleared (as postgres)
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
      perform set_config('app.r_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_student') as student, current_setting('app.r_cashier') as cashier,
  current_setting('app.r_department') as department, current_setting('app.r_registrar') as registrar_after,
  (select approved_by::text = current_setting('app.reg') from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as approved_by_registrar,
  (select count(*) from public.audit_logs
    where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
      and record_id = current_setting('app.clr')) as audit_rows,
  case when (current_setting('app.r_student') = 'rows 0' or current_setting('app.r_student') like 'rls: %')
        and (current_setting('app.r_cashier') = 'rows 0' or current_setting('app.r_cashier') like 'rls: %')
        and (current_setting('app.r_department') = 'rows 0' or current_setting('app.r_department') like 'rls: %')
        and current_setting('app.r_registrar') = 'rows 1'
        and coalesce((select approved_at is not null and approved_by::text = current_setting('app.reg')
                        from public.clearances where clearance_id = current_setting('app.clr')::bigint), false)
        and (select count(*) from public.audit_logs
              where log_id > current_setting('app.log_mark')::bigint and table_name = 'clearances'
                and record_id = current_setting('app.clr')) = 1
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-67. (e) A clearance with ZERO items cannot be approved
-- ------------------------------------------
-- A data anomaly made on purpose: postgres deletes every item of the new clearance. The
-- Registrar approves; then postgres tries the same.
-- Expected: items_left 0, registrar_approval "blocked [P0001]: pending items: clearance
-- <id> cannot be approved because it has no clearance items", postgres_approval the same
-- text, still_not_approved true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
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
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department (require_no_active_hold,
-- issue 22, would otherwise refuse to clear the items below)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- the clearance (the clearance trigger creates one pending item per department; add any
-- that is missing). No charges in this term, so finance_autoclear (issue 23) does nothing.
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
-- end of common setup
delete from public.clearance_items where clearance_id = current_setting('app.clr')::bigint;
select set_config('app.expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved because it has no clearance items', true);
-- act as the Registrar
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_reg', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_reg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- postgres tries the same
do $$
declare n bigint;
begin
  update public.clearances set approved_by = current_setting('app.reg')::uuid, approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_pg', 'NOT BLOCKED, rows ' || n, true);
exception when others then
  perform set_config('app.r_pg',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
select (select count(*) from public.clearance_items
         where clearance_id = current_setting('app.clr')::bigint) as items_left,
  current_setting('app.r_reg') as registrar_approval,
  current_setting('app.r_pg') as postgres_approval,
  (select approved_at is null and approved_by is null from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as still_not_approved,
  case when (select count(*) from public.clearance_items
              where clearance_id = current_setting('app.clr')::bigint) = 0
        and left(current_setting('app.r_reg'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and left(current_setting('app.r_pg'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-68. (f) Setting only approved_by, or only approved_at
-- NOTE (rehearsal 2026-10-11): the table has CHECK ck_clearances_approval (approved_at and approved_by are both NULL or both set), so a lone column cannot be saved: by_only_cleared is "ERROR [23514] ... ck_clearances_approval" (not "rows 1"). The trigger still runs first for the pending cases.
-- ------------------------------------------
-- Part 1, the Department user's item pending: the Registrar sets ONLY approved_by = self,
-- then ONLY approved_at. Both are a step of approving, so both are blocked by the trigger.
-- Part 2, after postgres clears that item: the Registrar sets ONLY approved_by = self
-- (allowed: the policy is satisfied, the status stays "In Progress"); postgres resets
-- approved_by to NULL; the Registrar sets ONLY approved_at: now the trigger lets it through
-- and the policy rejects it (WITH CHECK approved_by = the caller), which is what TC-18
-- tests.
-- Expected: by_only_pending and at_only_pending both "blocked [P0001]: pending items: ...
-- while 1 of <T> items are not cleared", by_only_cleared "rows 1", status_after_by_only
-- "In Progress", at_only_cleared "rls: new row violates row-level security policy ...",
-- final_approved_at_null true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
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
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department (require_no_active_hold,
-- issue 22, would otherwise refuse to clear the items below)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- the clearance (the clearance trigger creates one pending item per department; add any
-- that is missing). No charges in this term, so finance_autoclear (issue 23) does nothing.
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
-- end of common setup
-- every item cleared except the Department user's item (as postgres)
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null
  and clearance_item_id <> current_setting('app.item_dept')::bigint;
select set_config('app.expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
-- part 1: act as the Registrar, one item pending
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
      perform set_config('app.r_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- postgres clears the last item
update public.clearance_items set cleared_at = now(), cleared_by = current_setting('app.dept')::uuid
where clearance_item_id = current_setting('app.item_dept')::bigint;
-- part 2a: the Registrar sets only approved_by
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = auth.uid() where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_by_cleared', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_by_cleared',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.status_by', coalesce((select status from public.v_clearances
  where clearance_id = current_setting('app.clr')::bigint), 'none'), true);
-- postgres resets approved_by (value -> NULL is not checked)
update public.clearances set approved_by = null where clearance_id = current_setting('app.clr')::bigint;
-- part 2b: the Registrar sets only approved_at (approved_by stays NULL)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_at = now() where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_at_cleared', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_at_cleared',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_by_pending') as by_only_pending,
  current_setting('app.r_at_pending') as at_only_pending,
  current_setting('app.r_by_cleared') as by_only_cleared,
  current_setting('app.status_by') as status_after_by_only,
  current_setting('app.r_at_cleared') as at_only_cleared,
  (select approved_at is null from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as final_approved_at_null,
  case when left(current_setting('app.r_by_pending'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and left(current_setting('app.r_at_pending'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and current_setting('app.r_by_cleared') like 'ERROR [23514]%ck_clearances_approval%'
        and current_setting('app.status_by') = 'In Progress'
        and current_setting('app.r_at_cleared') like 'rls: %'
        and coalesce((select approved_at is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-69. (g) Editing and un-approving an approved clearance; re-approval is checked
-- NOTE (rehearsal 2026-10-11): ck_clearances_approval rejects a Registrar un-approve (approved_at NULL with approved_by set): unapprove is "ERROR [23514] ... ck_clearances_approval" and the clearance stays approved, so reapprove is a plain edit, "rows 1" (not checked). Only postgres can un-approve completely; its re-approval is blocked.
-- ------------------------------------------
-- Every item cleared; the Registrar approves (rows 1). Then postgres un-clears the
-- Department user's item, so the clearance is approved while an item is pending (the case
-- diagnostic (d) of the change file lists; the trigger does not change it). Then:
--   the Registrar corrects approved_at (value -> other value): not checked, rows 1;
--   the Registrar un-approves (approved_at NULL, approved_by stays self): not checked, rows 1;
--   the Registrar approves again (approved_at NULL -> value): blocked;
--   postgres un-approves completely (both NULL): rows 1;
--   postgres approves again: blocked (every role).
-- Expected: approve "rows 1", unclear_item "rows 1", edit_approved_at "rows 1", unapprove
-- "rows 1", reapprove "blocked [P0001]: pending items: ... while 1 of <T> items are not
-- cleared", postgres_unapprove "rows 1", postgres_reapprove the same "blocked [P0001]: ..."
-- text, final_not_approved true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
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
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department (require_no_active_hold,
-- issue 22, would otherwise refuse to clear the items below)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.dept')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- the clearance (the clearance trigger creates one pending item per department; add any
-- that is missing). No charges in this term, so finance_autoclear (issue 23) does nothing.
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
-- end of common setup
-- every item cleared (as postgres)
update public.clearance_items
set cleared_at = now(),
    cleared_by = case when department_id = current_setting('app.fin')::bigint then current_setting('app.cash')::uuid
                      when department_id = current_setting('app.mydept')::bigint then current_setting('app.dept')::uuid
                      else current_setting('app.adm')::uuid end
where clearance_id = current_setting('app.clr')::bigint and cleared_at is null;
select set_config('app.expect', 'blocked [P0001]: pending items: clearance ' || current_setting('app.clr')
  || ' cannot be approved while 1 of ' || current_setting('app.total') || ' items are not cleared', true);
-- the Registrar approves
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.clearances set approved_by = auth.uid(), approved_at = now()
  where clearance_id = current_setting('app.clr')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_approve', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_approve',
    case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- postgres un-clears the Department user's item (require_no_active_hold does not fire on
-- NOT NULL -> NULL)
do $$
declare n bigint;
begin
  update public.clearance_items set cleared_at = null, cleared_by = null
  where clearance_item_id = current_setting('app.item_dept')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_unclear', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_unclear', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
-- the Registrar edits, un-approves and re-approves
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
      perform set_config('app.r_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- postgres un-approves completely, then approves again
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
      perform set_config('app.r_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'pending items:%' then 'blocked [' || sqlstate || ']: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
select current_setting('app.r_approve') as approve, current_setting('app.r_unclear') as unclear_item,
  current_setting('app.r_edit_at') as edit_approved_at, current_setting('app.r_unapprove') as unapprove,
  current_setting('app.r_reapprove') as reapprove,
  current_setting('app.r_pg_unapprove') as postgres_unapprove,
  current_setting('app.r_pg_reapprove') as postgres_reapprove,
  (select approved_at is null and approved_by is null from public.clearances
    where clearance_id = current_setting('app.clr')::bigint) as final_not_approved,
  case when current_setting('app.r_approve') = 'rows 1' and current_setting('app.r_unclear') = 'rows 1'
        and current_setting('app.r_edit_at') = 'rows 1' and current_setting('app.r_unapprove') like 'ERROR [23514]%ck_clearances_approval%'
        and current_setting('app.r_reapprove') = 'rows 1'
        and current_setting('app.r_pg_unapprove') = 'rows 1'
        and left(current_setting('app.r_pg_reapprove'), length(current_setting('app.expect'))) = current_setting('app.expect')
        and coalesce((select approved_at is null and approved_by is null from public.clearances
                       where clearance_id = current_setting('app.clr')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-70. Function privileges; anon cannot call it
-- ------------------------------------------
-- Expected: anon_execute false, authenticated_execute true, public_in_acl false,
-- security_definer true, anon_call "denied: permission denied for ...",
-- authenticated_call an error (normally "trigger functions can only be called as
-- triggers"; "permission denied for schema private" is also fine), verdict "-> OK".
begin;
select set_config('app.reg', coalesce((select id::text from auth.users where email = 'registrar@pnc.test'), ''), true);
set local role anon;
do $$
begin
  perform private.require_all_items_cleared();
  perform set_config('app.r_anon', 'NOT DENIED', true);
exception when others then
  perform set_config('app.r_anon',
    case when sqlerrm like 'permission denied%' then 'denied: ' else 'OTHER [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
begin
  perform private.require_all_items_cleared();
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
      from pg_proc p where p.oid = to_regprocedure('private.require_all_items_cleared()')) f;
rollback;
