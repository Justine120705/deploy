-- ==========================================
-- TESTS FOR trigger_finance_autoclear.sql (GitHub issue #62): TC-49 to TC-61
-- ==========================================
-- Part K of docs/issue-12-testing-guide.md explains each case and records the results.
-- To run the change AND all these tests in one rolled-back transaction (one paste, one
-- result row), use docs/database/trigger_finance_autoclear_rehearsal.sql instead; its
-- test part can also be run on its own once the change is live.
--
-- Rules (same as Parts I and J of the guide):
--   - Supabase SQL editor, as postgres, AFTER trigger_finance_autoclear.sql has been run.
--     Run ONE block at a time: copy one block, from its "begin;" line to its "rollback;"
--     line inclusive, into a new tab and run that tab as a whole (never a selection).
--   - Every block ends with "rollback;", so nothing is changed. If a block stops at an
--     unexpected error, run "rollback;" as its own query.
--   - Roles are impersonated as in trigger_dept_approval_test.sql: the user ids are looked
--     up by e-mail (seed accounts *@pnc.test) as postgres, then "set local role
--     authenticated" (or anon) and request.jwt.claims = {"sub": <id>, "role":
--     "authenticated"} via set_config(..., true). After every impersonated step the block
--     goes back to postgres AND clears request.jwt.claims, so "postgres" always means
--     "no user JWT" (auth.uid() NULL), as in the SQL editor.
--   - The editor shows only the last result, so every block ends with ONE result row.
--     Expected errors are caught inside a do block and shown as text:
--       "blocked [P0001]: active hold: ..." = trigger require_no_active_hold stopped it
--       "denied: ..."                       = permission denied (grants)
--       "rls: ..."                          = new row violates row-level security policy
--       "rows N"                            = the statement ran and changed N rows
--     Every block ends with a verdict cell "-> OK" or "-> FAIL".
--   - No SKIPPED results: each block CREATES its own data as postgres inside the
--     transaction (undone by the rollback): a throwaway term (seed students already have
--     a clearance for the current term, and clearances are unique per student and term),
--     charges, payments, a clearance (the clearance trigger creates one pending item per
--     department) and the holds it needs. It first lifts every active hold of Student 1
--     (also undone by the rollback). If a seed account, the Financial department or a fee
--     type is missing, the setup stops with "TC setup: ...". TC-50 is the one case that
--     uses the seed rows themselves (the issue asks for it); it shows the seed numbers it
--     found and fails, rather than skips, if they are not the documented ones.
--   - No temporary GRANT: these blocks use the real grants of grants_clearance.sql (the
--     Cashier has UPDATE (amount, due_date, status) on charges and nothing else here).
--
-- Status: TC-49 to TC-61 pass live (2026-10-11).
--
-- The SETUP part is the same in TC-50 to TC-60 (between the "setup" and "end of common
-- setup" comments); only the part after it differs.


-- ------------------------------------------
-- TC-49. Installed as intended (catalog, read-only)
-- ------------------------------------------
-- Expected: charges_order "guard_immutable_columns (BEFORE) > audit_log (AFTER) >
-- finance_autoclear (AFTER)", items_order "guard_immutable_columns (BEFORE) >
-- require_no_active_hold (BEFORE) > audit_log (AFTER) > finance_autoclear_on_create
-- (AFTER)", charges trigger "O" type 21 with WHEN on status,student_id,term_id, items
-- trigger "O" type 5 with WHEN, function SECURITY DEFINER with 'search_path=""', owner
-- postgres, owner_bypasses_rls true, verdict "-> OK".
begin;
select row_to_json(t) as tc49 from (select
  (select string_agg(x.tgname || ' (' || x.timing || ')', ' > ' order by x.ord, x.tgname)
     from (select tg.tgname::text as tgname,
                  case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
                  case when (tg.tgtype::int & 2) = 2 then 0 else 1 end as ord
             from pg_trigger tg
            where tg.tgrelid = 'public.charges'::regclass and not tg.tgisinternal) x) as charges_order,
  (select string_agg(x.tgname || ' (' || x.timing || ')', ' > ' order by x.ord, x.tgname)
     from (select tg.tgname::text as tgname,
                  case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end as timing,
                  case when (tg.tgtype::int & 2) = 2 then 0 else 1 end as ord
             from pg_trigger tg
            where tg.tgrelid = 'public.clearance_items'::regclass and not tg.tgisinternal) x) as items_order,
  (select tg.tgenabled::text || ', type ' || tg.tgtype || ', when ' || case when tg.tgqual is not null then 'true' else 'false' end
          || ', columns ' || coalesce((select string_agg(a.attname::text, ',' order by a.attname)
                                         from pg_attribute a
                                        where a.attrelid = tg.tgrelid and a.attnum = any (tg.tgattr)), '-')
     from pg_trigger tg
    where tg.tgrelid = 'public.charges'::regclass and tg.tgname = 'finance_autoclear') as charges_trigger,
  (select tg.tgenabled::text || ', type ' || tg.tgtype || ', when ' || case when tg.tgqual is not null then 'true' else 'false' end
     from pg_trigger tg
    where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'finance_autoclear_on_create') as items_trigger,
  (select pg_get_triggerdef(tg.oid) from pg_trigger tg
    where tg.tgrelid = 'public.charges'::regclass and tg.tgname = 'finance_autoclear') as charges_trigger_definition,
  (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) as function_security_definer,
  (select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) as function_config,
  (select pg_get_userbyid(p.proowner)::text from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) as function_owner,
  (select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
     from pg_class c
     cross join pg_proc p
     join pg_roles r on r.oid = p.proowner
    where p.oid = to_regprocedure('private.finance_autoclear()')
      and c.oid in ('public.charges'::regclass, 'public.clearance_items'::regclass, 'public.clearances'::regclass,
                    'public.departments'::regclass, 'public.academic_holds'::regclass, 'public.audit_logs'::regclass,
                    'public.profiles'::regclass, 'public.roles'::regclass)) as owner_bypasses_rls,
  case when
    (select string_agg(tg.tgname::text, ',' order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.charges'::regclass and not tg.tgisinternal)
      = 'guard_immutable_columns,audit_log,finance_autoclear'
    and (select string_agg(tg.tgname::text, ',' order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
           from pg_trigger tg where tg.tgrelid = 'public.clearance_items'::regclass and not tg.tgisinternal)
      = 'guard_immutable_columns,require_no_active_hold,audit_log,finance_autoclear_on_create'
    and exists (select 1 from pg_trigger tg
                 where tg.tgrelid = 'public.charges'::regclass and tg.tgname = 'finance_autoclear'
                   and tg.tgenabled = 'O' and tg.tgtype = 21 and tg.tgqual is not null
                   and tg.tgfoid = to_regprocedure('private.finance_autoclear()')
                   and (select string_agg(a.attname::text, ',' order by a.attname) from pg_attribute a
                         where a.attrelid = tg.tgrelid and a.attnum = any (tg.tgattr)) = 'status,student_id,term_id')
    and exists (select 1 from pg_trigger tg
                 where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'finance_autoclear_on_create'
                   and tg.tgenabled = 'O' and tg.tgtype = 5 and tg.tgqual is not null
                   and tg.tgfoid = to_regprocedure('private.finance_autoclear()'))
    and exists (select 1 from pg_proc p
                 where p.oid = to_regprocedure('private.finance_autoclear()') and p.prosecdef
                   and p.proconfig && array['search_path=""', 'search_path='''''])
    and (select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
           from pg_class c cross join pg_proc p join pg_roles r on r.oid = p.proowner
          where p.oid = to_regprocedure('private.finance_autoclear()')
            and c.oid in ('public.charges'::regclass, 'public.clearance_items'::regclass, 'public.clearances'::regclass,
                          'public.departments'::regclass, 'public.academic_holds'::regclass, 'public.audit_logs'::regclass,
                          'public.profiles'::regclass, 'public.roles'::regclass))
  then '-> OK' else '-> FAIL' end as verdict) t;
rollback;


-- ------------------------------------------
-- TC-50. The seed data (current term): 3 charges, 20,000 of 45,000 collected
-- ------------------------------------------
-- The issue asks for this. Seed: Student 1's charge Cleared (Financial item cleared),
-- Student 2's charge Unpaid with nothing paid (item pending, active CCS hold), Student 3's
-- charge Unpaid with 5,000 paid (item pending). The Cashier tags Student 2's charge
-- Cleared. Active Financial holds of Students 2 and 3 are lifted first (Student 2's CCS
-- hold stays: a Department hold must not matter).
-- Expected: seed "charges 3, total 45000, collected 20000", seed_ok true,
-- preconditions_ok true, cashier_tags_s2 "rows 1", s2_financial_cleared true,
-- s2_cleared_by_cashier true, s3_financial_pending true, s1_item_unchanged true,
-- verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
select set_config('app.s3',  coalesce((select id::text from auth.users where email = 'student3@pnc.test'), ''), true);
select set_config('app.cur', coalesce((select min(term_id)::text from public.terms where is_current), ''), true);
select set_config('app.seed', (select format('charges %s, total %s, collected %s', count(*), coalesce(sum(ch.amount), 0),
    (select coalesce(sum(p.amount_paid), 0) from public.payments p join public.charges c2 on c2.charge_id = p.charge_id
      where c2.term_id::text = current_setting('app.cur')))
  from public.charges ch where ch.term_id::text = current_setting('app.cur')), true);
select set_config('app.seed_ok', ((select count(*) from public.charges where term_id::text = current_setting('app.cur')) = 3
  and (select coalesce(sum(amount), 0) from public.charges where term_id::text = current_setting('app.cur')) = 45000
  and (select coalesce(sum(p.amount_paid), 0) from public.payments p join public.charges c2 on c2.charge_id = p.charge_id
        where c2.term_id::text = current_setting('app.cur')) = 20000)::text, true);
select set_config('app.s2_charge', coalesce((select min(charge_id)::text from public.charges
  where student_id::text = current_setting('app.s2') and term_id::text = current_setting('app.cur')), ''), true);
select set_config('app.s1_item', coalesce((select min(ci.clearance_item_id)::text from public.clearance_items ci
  join public.clearances c on c.clearance_id = ci.clearance_id
  where c.student_id::text = current_setting('app.s1') and c.term_id::text = current_setting('app.cur')
    and ci.department_id::text = current_setting('app.fin')), ''), true);
select set_config('app.s2_item', coalesce((select min(ci.clearance_item_id)::text from public.clearance_items ci
  join public.clearances c on c.clearance_id = ci.clearance_id
  where c.student_id::text = current_setting('app.s2') and c.term_id::text = current_setting('app.cur')
    and ci.department_id::text = current_setting('app.fin')), ''), true);
select set_config('app.s3_item', coalesce((select min(ci.clearance_item_id)::text from public.clearance_items ci
  join public.clearances c on c.clearance_id = ci.clearance_id
  where c.student_id::text = current_setting('app.s3') and c.term_id::text = current_setting('app.cur')
    and ci.department_id::text = current_setting('app.fin')), ''), true);
-- known start: no active Financial hold for Students 2 and 3
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id::text in (current_setting('app.s2'), current_setting('app.s3'))
  and department_id::text = current_setting('app.fin') and lifted_at is null;
select set_config('app.pre_ok', (
  (select count(*) from public.charges where student_id::text = current_setting('app.s2')
     and term_id::text = current_setting('app.cur')) = 1
  and (select count(*) from public.charges where student_id::text = current_setting('app.s2')
         and term_id::text = current_setting('app.cur') and status = 'Unpaid') = 1
  and exists (select 1 from public.charges where student_id::text = current_setting('app.s3')
                and term_id::text = current_setting('app.cur') and status = 'Unpaid')
  and coalesce((select cleared_at is null from public.clearance_items
                 where clearance_item_id::text = current_setting('app.s2_item')), false)
  and coalesce((select cleared_at is null from public.clearance_items
                 where clearance_item_id::text = current_setting('app.s3_item')), false))::text, true);
select set_config('app.s1_before', coalesce((select cleared_at::text || ' ' || coalesce(cleared_by::text, '-')
  from public.clearance_items where clearance_item_id::text = current_setting('app.s1_item')), 'none'), true);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Cleared' where charge_id::text = current_setting('app.s2_charge');
  get diagnostics n = row_count;
  perform set_config('app.r_tag', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_tag',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.seed') as seed, current_setting('app.seed_ok') as seed_ok,
  current_setting('app.pre_ok') as preconditions_ok,
  current_setting('app.r_tag') as cashier_tags_s2,
  (select cleared_at is not null from public.clearance_items
    where clearance_item_id::text = current_setting('app.s2_item')) as s2_financial_cleared,
  (select cleared_by::text = current_setting('app.cash') from public.clearance_items
    where clearance_item_id::text = current_setting('app.s2_item')) as s2_cleared_by_cashier,
  (select cleared_at is null from public.clearance_items
    where clearance_item_id::text = current_setting('app.s3_item')) as s3_financial_pending,
  (coalesce((select cleared_at::text || ' ' || coalesce(cleared_by::text, '-') from public.clearance_items
              where clearance_item_id::text = current_setting('app.s1_item')), 'none')
   = current_setting('app.s1_before')) as s1_item_unchanged,
  case when current_setting('app.seed_ok') = 'true' and current_setting('app.pre_ok') = 'true'
        and current_setting('app.r_tag') = 'rows 1'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id::text = current_setting('app.s2_item')), false)
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id::text = current_setting('app.s3_item')), false)
        and coalesce((select cleared_at::text || ' ' || coalesce(cleared_by::text, '-') from public.clearance_items
                       where clearance_item_id::text = current_setting('app.s1_item')), 'none')
            = current_setting('app.s1_before')
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-51. (a) Mixed Cleared / Waived: the Financial item clears on the last tag
-- ------------------------------------------
-- Student 1 has a clearance in the throwaway term and 3 Unpaid charges of 15,000; 15,000
-- and 5,000 were paid (20,000 of 45,000). The Cashier tags them Cleared, Waived, Waived.
-- After each tag the block reads the Financial item (as the Cashier, through RLS).
-- Expected: tag1 "rows 1, item pending", tag2 "rows 1, item pending", tag3 "rows 1, item
-- cleared", collected 20000, total 45000, financial_cleared true, cleared_by_cashier
-- true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
-- the clearance (the clearance trigger creates the items; add them only if it did not)
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
-- 3 Unpaid charges of 15,000 (45,000) and 20,000 of payments
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
insert into public.payments (charge_id, amount_paid, receipt_number, recorded_by)
values (current_setting('app.ch1')::bigint, 15000, 'TC51-' || txid_current() || '-1', current_setting('app.cash')::uuid),
       (current_setting('app.ch2')::bigint,  5000, 'TC51-' || txid_current() || '-2', current_setting('app.cash')::uuid);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.r_' || r.label, 'rows ' || n || ', item ' ||
        coalesce((select case when ci.cleared_at is null then 'pending' else 'cleared' end
                    from public.clearance_items ci
                   where ci.clearance_item_id = current_setting('app.item_fin')::bigint), 'not visible'), true);
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
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_tag1') as tag1_cleared, current_setting('app.r_tag2') as tag2_waived,
  current_setting('app.r_tag3') as tag3_waived,
  (select sum(p.amount_paid) from public.payments p
    where p.charge_id in (current_setting('app.ch1')::bigint, current_setting('app.ch2')::bigint, current_setting('app.ch3')::bigint)) as collected,
  (select sum(ch.amount) from public.charges ch
    where ch.student_id = current_setting('app.s1')::uuid and ch.term_id = current_setting('app.term')::bigint) as total,
  (select cleared_at is not null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as financial_cleared,
  (select cleared_by::text = current_setting('app.cash') from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as cleared_by_cashier,
  case when current_setting('app.r_tag1') = 'rows 1, item pending'
        and current_setting('app.r_tag2') = 'rows 1, item pending'
        and current_setting('app.r_tag3') = 'rows 1, item cleared'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-52. (b) One charge still Unpaid: not cleared
-- ------------------------------------------
-- Same data as TC-51 without payments. The Cashier tags the first two charges (Cleared,
-- Waived) and only edits the amount and due date of the third (it stays Unpaid).
-- Expected: tag1, tag2 and edit3 each "rows 1", third_status Unpaid,
-- financial_pending true, cleared_by_null true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1',  $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2',  $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'edit3', $q$update public.charges set amount = 14000, due_date = date '2097-11-15'
                    where charge_id = current_setting('app.ch3')::bigint$q$)
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
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_tag1') as tag1, current_setting('app.r_tag2') as tag2,
  current_setting('app.r_edit3') as edit3,
  (select status from public.charges where charge_id = current_setting('app.ch3')::bigint) as third_status,
  (select cleared_at is null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as financial_pending,
  (select cleared_by is null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as cleared_by_null,
  case when current_setting('app.r_tag1') = 'rows 1' and current_setting('app.r_tag2') = 'rows 1'
        and current_setting('app.r_edit3') = 'rows 1'
        and (select status from public.charges where charge_id = current_setting('app.ch3')::bigint) = 'Unpaid'
        and coalesce((select cleared_at is null and cleared_by is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-53. (c) No clearance yet: tagging works; the item clears when the clearance is created
-- ------------------------------------------
-- Student 1 has 3 Unpaid charges in the throwaway term and NO clearance there. The
-- Cashier tags all three (Cleared, Cleared, Waived). Then Student 1 requests the
-- clearance through the API path (insert as authenticated); the clearance trigger creates
-- the items and the Financial item is cleared at creation with cleared_by = the Cashier
-- (the actor of the last tag, from audit_logs).
-- Expected: tags "rows 1" x3, clearances_before 0, request "rows 1", items_created =
-- number of departments (4 with the seed), financial_cleared true, cleared_by_cashier
-- true, other_items_pending = departments - 1, item_audit "INSERT,UPDATE",
-- update_actor_is_student true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- act as the Cashier (no clearance exists yet)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch3')::bigint$q$)
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
select set_config('request.jwt.claims', '', true);
select set_config('app.clr_before', (select count(*)::text from public.clearances
  where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term')::bigint), true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as Student 1: request the clearance (the API path)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr', v_id::text, true);
  perform set_config('app.r_request', 'rows 1', true);
exception when others then
  perform set_config('app.clr', '', true);
  perform set_config('app.r_request',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.item_fin', coalesce((select min(clearance_item_id)::text from public.clearance_items
  where clearance_id::text = current_setting('app.clr') and department_id::text = current_setting('app.fin')), ''), true);
select current_setting('app.r_tag1') || ', ' || current_setting('app.r_tag2') || ', ' || current_setting('app.r_tag3') as tags,
  current_setting('app.clr_before') as clearances_before,
  current_setting('app.r_request') as request,
  (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr')) as items_created,
  (select cleared_at is not null from public.clearance_items
    where clearance_item_id::text = current_setting('app.item_fin')) as financial_cleared,
  (select cleared_by::text = current_setting('app.cash') from public.clearance_items
    where clearance_item_id::text = current_setting('app.item_fin')) as cleared_by_cashier,
  (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr')
     and department_id::text <> current_setting('app.fin') and cleared_at is null) as other_items_pending,
  (select string_agg(l.action::text, ',' order by l.log_id) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
      and l.record_id = current_setting('app.item_fin')) as item_audit,
  (select bool_and(l.actor_id::text = current_setting('app.s1')) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
      and l.record_id = current_setting('app.item_fin') and l.action = 'UPDATE') as update_actor_is_student,
  case when current_setting('app.r_tag1') = 'rows 1' and current_setting('app.r_tag2') = 'rows 1'
        and current_setting('app.r_tag3') = 'rows 1' and current_setting('app.clr_before') = '0'
        and current_setting('app.r_request') = 'rows 1'
        and (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr'))
            = current_setting('app.ndept')::bigint
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id::text = current_setting('app.item_fin')), false)
        and (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr')
               and department_id::text <> current_setting('app.fin') and cleared_at is null)
            = current_setting('app.ndept')::bigint - 1
        and (select string_agg(l.action::text, ',' order by l.log_id) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                and l.record_id = current_setting('app.item_fin')) = 'INSERT,UPDATE'
        and coalesce((select bool_and(l.actor_id::text = current_setting('app.s1')) from public.audit_logs l
                       where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                         and l.record_id = current_setting('app.item_fin') and l.action = 'UPDATE'), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-54. (d) Zero charges: not cleared
-- ------------------------------------------
-- Student 1 has NO charge in the throwaway term; a settled charge exists only in a SECOND
-- throwaway term (tagged by the Cashier), which must not count. Student 1 requests the
-- clearance for the first term.
-- Expected: other_term_tag "rows 1", charges_in_term 0, request "rows 1", items_created =
-- number of departments, financial_pending true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2096-2097', '1st', '2096-08-01', '2097-01-01', false) returning term_id)
select set_config('app.term2', term_id::text, true) from t;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s1')::uuid, current_setting('app.term2')::bigint, current_setting('app.fee')::bigint,
        15000, date '2096-10-15', 'Unpaid');
-- act as the Cashier: settle the charge of the OTHER term
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Cleared'
  where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term2')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_other', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_other',
    case when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
-- act as Student 1: request the clearance for the term without charges
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr', v_id::text, true);
  perform set_config('app.r_request', 'rows 1', true);
exception when others then
  perform set_config('app.clr', '', true);
  perform set_config('app.r_request',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_other') as other_term_tag,
  (select count(*) from public.charges where student_id = current_setting('app.s1')::uuid
     and term_id = current_setting('app.term')::bigint) as charges_in_term,
  current_setting('app.r_request') as request,
  (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr')) as items_created,
  (select cleared_at is null from public.clearance_items where clearance_id::text = current_setting('app.clr')
     and department_id::text = current_setting('app.fin')) as financial_pending,
  case when current_setting('app.r_other') = 'rows 1' and current_setting('app.r_request') = 'rows 1'
        and (select count(*) from public.charges where student_id = current_setting('app.s1')::uuid
               and term_id = current_setting('app.term')::bigint) = 0
        and (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr'))
            = current_setting('app.ndept')::bigint
        and coalesce((select bool_and(cleared_at is null) from public.clearance_items
                       where clearance_id::text = current_setting('app.clr')
                         and department_id::text = current_setting('app.fin')), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-55. (e) Active Financial hold: the item stays pending and nothing fails
-- ------------------------------------------
-- Part 1: clearance and 3 charges; an active Financial hold (placed as postgres; no API
-- flow places Financial holds today). The Cashier tags all three: each update succeeds,
-- the item stays pending (without decision 6 the last tag would fail with "active hold").
-- Part 2: postgres lifts the hold; the Cashier re-saves the last charge's status
-- ("set status = status"): the item clears, cleared_by = the Cashier.
-- Part 3 (creation path): in a second throwaway term the charge is settled by the
-- Cashier, a Financial hold is active, and Student 1 requests the clearance: the request
-- succeeds and the item stays pending.
-- Expected: tags_with_hold "rows 1, rows 1, rows 1", pending_with_hold true,
-- resave_after_lift "rows 1", cleared_after_lift true, cleared_by_cashier true,
-- term2_tag "rows 1", request_with_hold "rows 1", created_item_pending true,
-- verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- part 1: an active Financial hold
with h as (insert into public.academic_holds (student_id, department_id, reason, placed_by)
           values (current_setting('app.s1')::uuid, current_setting('app.fin')::bigint, 'TC-55 financial hold',
                   current_setting('app.cash')::uuid) returning hold_id)
select set_config('app.hold', hold_id::text, true) from h;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch3')::bigint$q$)
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
select set_config('request.jwt.claims', '', true);
select set_config('app.pending_with_hold', (select (cleared_at is null)::text from public.clearance_items
  where clearance_item_id = current_setting('app.item_fin')::bigint), true);
-- part 2: lift the hold (postgres), then the Cashier re-saves the last charge's status
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where hold_id = current_setting('app.hold')::bigint;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = status where charge_id = current_setting('app.ch3')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_resave', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_resave',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- part 3: creation path with an active Financial hold (second throwaway term)
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2096-2097', '1st', '2096-08-01', '2097-01-01', false) returning term_id)
select set_config('app.term2', term_id::text, true) from t;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s1')::uuid, current_setting('app.term2')::bigint, current_setting('app.fee')::bigint,
        15000, date '2096-10-15', 'Unpaid');
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.fin')::bigint, 'TC-55 financial hold 2',
        current_setting('app.cash')::uuid);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Cleared'
  where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term2')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_tag_term2', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_tag_term2', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term2')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr2', v_id::text, true);
  perform set_config('app.r_request2', 'rows 1', true);
exception when others then
  perform set_config('app.clr2', '', true);
  perform set_config('app.r_request2',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_tag1') || ', ' || current_setting('app.r_tag2') || ', ' || current_setting('app.r_tag3') as tags_with_hold,
  current_setting('app.pending_with_hold') as pending_with_hold,
  current_setting('app.r_resave') as resave_after_lift,
  (select cleared_at is not null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as cleared_after_lift,
  (select cleared_by::text = current_setting('app.cash') from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as cleared_by_cashier,
  current_setting('app.r_tag_term2') as term2_tag,
  current_setting('app.r_request2') as request_with_hold,
  (select cleared_at is null from public.clearance_items where clearance_id::text = current_setting('app.clr2')
     and department_id::text = current_setting('app.fin')) as created_item_pending,
  case when current_setting('app.r_tag1') = 'rows 1' and current_setting('app.r_tag2') = 'rows 1'
        and current_setting('app.r_tag3') = 'rows 1' and current_setting('app.pending_with_hold') = 'true'
        and current_setting('app.r_resave') = 'rows 1'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and current_setting('app.r_tag_term2') = 'rows 1'
        and current_setting('app.r_request2') = 'rows 1'
        and coalesce((select bool_and(cleared_at is null) from public.clearance_items
                       where clearance_id::text = current_setting('app.clr2')
                         and department_id::text = current_setting('app.fin')), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-56. (f) An already-cleared Financial item is not overwritten
-- ------------------------------------------
-- postgres clears the Financial item first with a distinct time, cleared_by = the Admin
-- account and a remark (an earlier manual clear). Then the Cashier tags all three charges.
-- Expected: tags "rows 1, rows 1, rows 1", cleared_at_unchanged true,
-- cleared_by_unchanged true, remarks_unchanged true, item_audit_rows 0, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- an earlier manual clear (postgres, no hold, so require_no_active_hold allows it)
update public.clearance_items
set cleared_at = timestamptz '2097-09-01 08:00:00+00', cleared_by = current_setting('app.adm')::uuid,
    remarks = 'TC-56 manual clear'
where clearance_item_id = current_setting('app.item_fin')::bigint;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch3')::bigint$q$)
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
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_tag1') || ', ' || current_setting('app.r_tag2') || ', ' || current_setting('app.r_tag3') as tags,
  (select cleared_at = timestamptz '2097-09-01 08:00:00+00' from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as cleared_at_unchanged,
  (select cleared_by::text = current_setting('app.adm') from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as cleared_by_unchanged,
  (select remarks = 'TC-56 manual clear' from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as remarks_unchanged,
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
      and l.record_id = current_setting('app.item_fin')) as item_audit_rows,
  case when current_setting('app.r_tag1') = 'rows 1' and current_setting('app.r_tag2') = 'rows 1'
        and current_setting('app.r_tag3') = 'rows 1'
        and coalesce((select cleared_at = timestamptz '2097-09-01 08:00:00+00'
                             and cleared_by::text = current_setting('app.adm')
                             and remarks = 'TC-56 manual clear'
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                and l.record_id = current_setting('app.item_fin')) = 0
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-57. (g) A charge goes back to Unpaid: nothing breaks, the item is NOT un-cleared
-- ------------------------------------------
-- The Cashier tags all three charges (the item auto-clears), then sets the second one
-- back to Unpaid, then tags it Cleared again (decision 8 in the change file).
-- Expected: auto_cleared true, revert "rows 1", retag "rows 1", still_cleared true,
-- cleared_by_cashier true, item_audit_rows_after_revert 0, charge_audit_rows 2,
-- verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- act as the Cashier: tag all three (the item auto-clears)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch3')::bigint$q$)
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
select set_config('request.jwt.claims', '', true);
select set_config('app.auto_cleared', coalesce((select (cleared_at is not null)::text from public.clearance_items
  where clearance_item_id = current_setting('app.item_fin')::bigint), 'false'), true);
select set_config('app.clear_log', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier: revert the second charge to Unpaid, then tag it again
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'revert', $q$update public.charges set status = 'Unpaid'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (2, 'retag',  $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch2')::bigint$q$)
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
select set_config('request.jwt.claims', '', true);
select current_setting('app.auto_cleared') as auto_cleared,
  current_setting('app.r_revert') as revert, current_setting('app.r_retag') as retag,
  (select cleared_at is not null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as still_cleared,
  (select cleared_by::text = current_setting('app.cash') from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as cleared_by_cashier,
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.clear_log')::bigint and l.table_name = 'clearance_items'
      and l.record_id = current_setting('app.item_fin')) as item_audit_rows_after_revert,
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.clear_log')::bigint and l.table_name = 'charges'
      and l.record_id = current_setting('app.ch2')) as charge_audit_rows,
  case when current_setting('app.auto_cleared') = 'true'
        and current_setting('app.r_tag1') = 'rows 1' and current_setting('app.r_tag2') = 'rows 1'
        and current_setting('app.r_tag3') = 'rows 1'
        and current_setting('app.r_revert') = 'rows 1' and current_setting('app.r_retag') = 'rows 1'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.clear_log')::bigint and l.table_name = 'clearance_items'
                and l.record_id = current_setting('app.item_fin')) = 0
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.clear_log')::bigint and l.table_name = 'charges'
                and l.record_id = current_setting('app.ch2')) = 2
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-58. (h) A successful auto-clear writes an audit row (existing audit_log trigger)
-- ------------------------------------------
-- The Cashier tags the first two charges; the audit log is marked; the Cashier tags the
-- third (the auto-clear happens). The audit rows written after the mark are read as
-- postgres in the same transaction.
-- Expected: last_tag "rows 1", item_audit_rows 1, action UPDATE, actor_is_cashier true,
-- old_cleared_at_null true, new_cleared_by_is_cashier true, charge_row_first true,
-- verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- the first two charges are settled by the Cashier (as postgres with the Cashier's claims)
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
update public.charges set status = 'Cleared'
where charge_id in (current_setting('app.ch1')::bigint, current_setting('app.ch2')::bigint);
select set_config('request.jwt.claims', '', true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier: the last tag
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Waived' where charge_id = current_setting('app.ch3')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_tag3', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_tag3',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_tag3') as last_tag, a.item_audit_rows, a.action, a.actor_is_cashier,
  a.old_cleared_at_null, a.new_cleared_by_is_cashier, a.charge_row_first,
  case when current_setting('app.r_tag3') = 'rows 1' and a.item_audit_rows = 1 and a.action = 'UPDATE'
        and a.actor_is_cashier and a.old_cleared_at_null and a.new_cleared_by_is_cashier and a.charge_row_first
       then '-> OK' else '-> FAIL' end as verdict
from (select count(*) as item_audit_rows,
             string_agg(distinct l.action::text, ',') as action,
             coalesce(bool_and(l.actor_id::text = current_setting('app.cash')), false) as actor_is_cashier,
             coalesce(bool_and(l.old_data ->> 'cleared_at' is null), false) as old_cleared_at_null,
             coalesce(bool_and(l.new_data ->> 'cleared_by' = current_setting('app.cash')), false) as new_cleared_by_is_cashier,
             coalesce(bool_and(l.log_id > (select min(c.log_id) from public.audit_logs c
                                            where c.log_id > current_setting('app.log_mark')::bigint
                                              and c.table_name = 'charges'
                                              and c.record_id = current_setting('app.ch3'))), false) as charge_row_first
      from public.audit_logs l
      where l.log_id > current_setting('app.log_mark')::bigint
        and l.table_name = 'clearance_items'
        and l.record_id = current_setting('app.item_fin')) a;
rollback;


-- ------------------------------------------
-- TC-59. (i) Other departments' items and other students are never touched
-- ------------------------------------------
-- Student 1 and Student 2 both have a clearance in the throwaway term; Student 2 has one
-- Unpaid charge there. The Cashier settles all three charges of Student 1.
-- Expected: tags "rows 1, rows 1, rows 1", s1_financial_cleared true,
-- s1_other_items_pending = departments - 1, other_rows_audited 0, s2_financial_pending
-- true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s2')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr2', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select x.clr, d.department_id
from (values (current_setting('app.clr')::bigint), (current_setting('app.clr2')::bigint)) as x(clr)
cross join public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = x.clr and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.item_fin2', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr2')::bigint and department_id = current_setting('app.fin')::bigint), true);
-- known start for Student 2: no active Financial hold (other holds stay)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s2')::uuid and department_id = current_setting('app.fin')::bigint
  and lifted_at is null;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s2')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
        15000, date '2097-10-15', 'Unpaid');
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch3')::bigint$q$)
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
select set_config('request.jwt.claims', '', true);
select current_setting('app.r_tag1') || ', ' || current_setting('app.r_tag2') || ', ' || current_setting('app.r_tag3') as tags,
  (select cleared_at is not null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as s1_financial_cleared,
  (select count(*) from public.clearance_items where clearance_id = current_setting('app.clr')::bigint
     and department_id <> current_setting('app.fin')::bigint and cleared_at is null and cleared_by is null) as s1_other_items_pending,
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
      and l.record_id <> current_setting('app.item_fin')) as other_rows_audited,
  (select cleared_at is null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin2')::bigint) as s2_financial_pending,
  case when current_setting('app.r_tag1') = 'rows 1' and current_setting('app.r_tag2') = 'rows 1'
        and current_setting('app.r_tag3') = 'rows 1'
        and coalesce((select cleared_at is not null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and (select count(*) from public.clearance_items where clearance_id = current_setting('app.clr')::bigint
               and department_id <> current_setting('app.fin')::bigint and cleared_at is null and cleared_by is null)
            = current_setting('app.ndept')::bigint - 1
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                and l.record_id <> current_setting('app.item_fin')) = 0
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin2')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-60. No Cashier to record (postgres / SQL editor): the item stays pending
-- ------------------------------------------
-- Decision 4 in the change file. Part 1: the Cashier settles two charges, then postgres
-- WITHOUT a user JWT (auth.uid() NULL, as in the SQL editor) settles the last one: the
-- update works, the item stays pending. Part 2: in a second throwaway term the only
-- charge is settled by postgres; Student 1 then requests the clearance: the last tag has
-- no Cashier in audit_logs, so the item stays pending.
-- Expected: auth_uid_null true, postgres_last_tag "rows 1", item_pending true,
-- request "rows 1", created_item_pending true, verdict "-> OK".
begin;
-- setup (as postgres without a user JWT; undone by the rollback)
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
-- known start: Student 1 has no active hold of any department
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
-- end of common setup
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- part 1: the Cashier settles the first two
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
update public.charges set status = 'Cleared'
where charge_id in (current_setting('app.ch1')::bigint, current_setting('app.ch2')::bigint);
reset role;
-- ... and postgres without a user JWT settles the last one
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.uid_null', (auth.uid() is null)::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Waived' where charge_id = current_setting('app.ch3')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.r_pg', 'rows ' || n, true);
exception when others then
  perform set_config('app.r_pg', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
-- part 2: second throwaway term, the only charge settled by postgres, then the request
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2096-2097', '1st', '2096-08-01', '2097-01-01', false) returning term_id)
select set_config('app.term2', term_id::text, true) from t;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s1')::uuid, current_setting('app.term2')::bigint, current_setting('app.fee')::bigint,
        15000, date '2096-10-15', 'Unpaid');
update public.charges set status = 'Cleared'
where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term2')::bigint;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term2')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr2', v_id::text, true);
  perform set_config('app.r_request', 'rows 1', true);
exception when others then
  perform set_config('app.clr2', '', true);
  perform set_config('app.r_request',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select current_setting('app.uid_null') as auth_uid_null,
  current_setting('app.r_pg') as postgres_last_tag,
  (select cleared_at is null from public.clearance_items
    where clearance_item_id = current_setting('app.item_fin')::bigint) as item_pending,
  current_setting('app.r_request') as request,
  (select cleared_at is null from public.clearance_items where clearance_id::text = current_setting('app.clr2')
     and department_id::text = current_setting('app.fin')) as created_item_pending,
  case when current_setting('app.uid_null') = 'true' and current_setting('app.r_pg') = 'rows 1'
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and current_setting('app.r_request') = 'rows 1'
        and coalesce((select bool_and(cleared_at is null) from public.clearance_items
                       where clearance_id::text = current_setting('app.clr2')
                         and department_id::text = current_setting('app.fin')), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;


-- ------------------------------------------
-- TC-61. (j) Function privileges; anon cannot call it
-- ------------------------------------------
-- Expected: anon_execute false, authenticated_execute true, public_in_acl false,
-- security_definer true, anon_call "denied: permission denied for ...",
-- authenticated_call an error (normally "trigger functions can only be called as
-- triggers"; "permission denied for schema private" is also fine), verdict "-> OK".
begin;
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
set local role anon;
do $$
begin
  perform private.finance_autoclear();
  perform set_config('app.r_anon', 'NOT DENIED', true);
exception when others then
  perform set_config('app.r_anon',
    case when sqlerrm like 'permission denied%' then 'denied: ' else 'OTHER [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
begin
  perform private.finance_autoclear();
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
      from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) f;
rollback;
