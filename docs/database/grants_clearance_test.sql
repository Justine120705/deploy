-- ==========================================
-- TESTS FOR grants_clearance.sql (GitHub issue #60): TC-34 to TC-39
-- ==========================================
-- Part I of docs/issue-12-testing-guide.md explains each case and records the results.
--
-- Rules (same as Parts F, G and H of the guide):
--   - Supabase SQL editor, as postgres. Run ONE block at a time: copy one block, from its
--     "begin;" line to its "rollback;" line inclusive, into a new tab and run that tab as
--     a whole (never a selection). TC-34 is read-only and has no transaction.
--   - Every other block ends with "rollback;", so nothing is changed. If a block stops at
--     an unexpected error, run "rollback;" as its own query.
--   - Roles are impersonated exactly as in the guide: the user ids are looked up by e-mail
--     (seed accounts *@pnc.test) as postgres, then "set local role authenticated" (or
--     anon) and request.jwt.claims = {"sub": <id>, "role": "authenticated"}. Inside a
--     do block the claims are switched with set_config(..., true), as in TC-32.
--   - The editor shows only the last result, so every block ends with ONE result row.
--     Expected errors are caught inside a do block and shown as text:
--       "denied: ..."   = permission denied (the GRANTs stopped it)
--       "rls: ..."      = new row violates row-level security policy (RLS stopped it)
--       "rows N"        = the statement ran and changed / returned N rows
--   - No temporary GRANT is used in these blocks (unlike Parts F and G): they test the
--     real grants of grants_clearance.sql.
--
-- REHEARSAL BEFORE THE LIVE RUN (the issue asks for a test inside a transaction that ends
-- in ROLLBACK). In a new tab:
--   1. type   begin;
--   2. paste grants_clearance.sql from the line AFTER "BEGIN;" up to the line BEFORE
--      "COMMIT;" (sections 1 to 4 and the NOTIFY; a NOTIFY is discarded by a rollback);
--   3. paste ONE of the blocks below WITHOUT its first line "begin;" (for TC-34, paste
--      its select as it is);
--   4. end with that block's "rollback;" (TC-34: add "rollback;").
-- Run the tab as a whole. Sections 1 and 4 of grants_clearance.sql raise an error if a
-- check fails, which also ends in a rolled-back transaction. Repeat for each block. This
-- is TC-34R in the guide.
--
-- Status: rehearsed 2026-10-11 in rolled-back transactions on the live project (TC-34 to TC-39 pass); run live 2026-10-11; TC-34 to TC-40 pass live.


-- ------------------------------------------
-- TC-34. Grants after grants_clearance.sql (read-only, no transaction)
-- ------------------------------------------
-- Expected: anon_any_privilege '' (empty), any_dxtm '', slice_auth_select_all true,
-- slice_table_level_writes '', column_grants_missing '', column_grants_extra '',
-- auth_delete_tables 'profiles' (unchanged from before; no slice object),
-- auth_select_all true, auth_profiles_update true, auth_audit_insert false.
with slice(t) as (values ('clearances'), ('clearance_items'), ('academic_holds'), ('payments'),
                         ('charges'), ('audit_logs'), ('v_clearances'), ('v_clearance_items'), ('v_active_holds')),
rels as (
  select c.oid, c.relname from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')),
expected(t, col, priv) as (values
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
live as (
  select c.relname::text as t, a.attname::text as col, x.privilege_type::text as priv
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  cross join lateral aclexplode(a.attacl) x
  where c.relnamespace = 'public'::regnamespace and c.relname in (select t from slice)
    and a.attnum > 0 and not a.attisdropped and a.attacl is not null
    and x.grantee = 'authenticated'::regrole)
select
  coalesce((select string_agg(relname, ', ' order by relname) from rels
            where has_table_privilege('anon', oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
               or has_any_column_privilege('anon', oid, 'SELECT, INSERT, UPDATE, REFERENCES')), '') as anon_any_privilege,
  coalesce((select string_agg(r.relname || ':' || g.rolname, ', ') from rels r
            cross join (values ('anon'), ('authenticated')) as g(rolname)
            where has_table_privilege(g.rolname::name, r.oid, 'TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')), '') as any_dxtm,
  (select bool_and(has_table_privilege('authenticated', r.oid, 'SELECT'))
     from rels r where r.relname in (select t from slice)) as slice_auth_select_all,
  coalesce((select string_agg(r.relname, ', ') from rels r
            where r.relname in (select t from slice)
              and has_table_privilege('authenticated', r.oid, 'INSERT, UPDATE, DELETE')), '') as slice_table_level_writes,
  coalesce((select string_agg(t || '.' || col || ' ' || priv, ', ')
            from (select * from expected except select * from live) m), '') as column_grants_missing,
  coalesce((select string_agg(t || '.' || col || ' ' || priv, ', ')
            from (select * from live except select * from expected) x), '') as column_grants_extra,
  coalesce((select string_agg(relname, ', ' order by relname) from rels
            where has_table_privilege('authenticated', oid, 'DELETE')), '') as auth_delete_tables,
  (select bool_and(has_table_privilege('authenticated', oid, 'SELECT')) from rels) as auth_select_all,
  has_table_privilege('authenticated', 'public.profiles', 'UPDATE') as auth_profiles_update,
  has_table_privilege('authenticated', 'public.audit_logs', 'INSERT') as auth_audit_insert;


-- ------------------------------------------
-- TC-35. anon: every exposed object is denied (reads and writes)
-- ------------------------------------------
-- Expected: not_denied 0; details lists every statement with "denied: permission denied
-- for table/view ...". Any "rows N" is a Fail (anon got a right back).
begin;
set local role anon;
do $$
declare
  r record;
  n bigint;
  v_out text := '';
  v_bad int := 0;
begin
  for r in select * from (values
    ('select v_clearances',      $q$select count(*) from public.v_clearances$q$),
    ('select v_clearance_items', $q$select count(*) from public.v_clearance_items$q$),
    ('select v_active_holds',    $q$select count(*) from public.v_active_holds$q$),
    ('select charges',           $q$select count(*) from public.charges$q$),
    ('select payments',          $q$select count(*) from public.payments$q$),
    ('select audit_logs',        $q$select count(*) from public.audit_logs$q$),
    ('select clearances',        $q$select count(*) from public.clearances$q$),
    ('select clearance_items',   $q$select count(*) from public.clearance_items$q$),
    ('select academic_holds',    $q$select count(*) from public.academic_holds$q$),
    ('select profiles',          $q$select count(*) from public.profiles$q$),
    ('insert clearances',        $q$insert into public.clearances (student_id, term_id) values (gen_random_uuid(), 0)$q$),
    ('update clearances',        $q$update public.clearances set approved_at = now() where false$q$),
    ('update clearance_items',   $q$update public.clearance_items set remarks = 'x' where false$q$),
    ('insert academic_holds',    $q$insert into public.academic_holds (student_id, department_id, reason, placed_by) values (gen_random_uuid(), 0, 'x', gen_random_uuid())$q$),
    ('update academic_holds',    $q$update public.academic_holds set lifted_at = now() where false$q$),
    ('insert payments',          $q$insert into public.payments (charge_id, amount_paid, receipt_number, recorded_by) values (0, 1, 'tc35', gen_random_uuid())$q$),
    ('update charges',           $q$update public.charges set status = 'Waived' where false$q$),
    ('update profiles',          $q$update public.profiles set first_name = first_name where false$q$),
    ('delete profiles',          $q$delete from public.profiles where false$q$)
  ) as t(label, stmt)
  loop
    begin
      if r.stmt like 'select%' then
        execute r.stmt into n;
      else
        execute r.stmt;
        get diagnostics n = row_count;
      end if;
      v_out := v_out || r.label || ' = rows ' || n || '; ';
      v_bad := v_bad + 1;
    exception when others then
      if sqlerrm like 'permission denied%' then
        v_out := v_out || r.label || ' = denied: ' || sqlerrm || '; ';
      else
        v_out := v_out || r.label || ' = OTHER ERROR: ' || sqlerrm || '; ';
        v_bad := v_bad + 1;
      end if;
    end;
  end loop;
  perform set_config('app.not_denied', v_bad::text, true);
  perform set_config('app.details', v_out, true);
end $$;
reset role;
select current_setting('app.not_denied')::int as not_denied, current_setting('app.details') as details;
rollback;


-- ------------------------------------------
-- TC-36. Reads per role on the 6 exposed read objects
-- ------------------------------------------
-- Each role reads v_clearances, v_clearance_items, v_active_holds, charges, payments,
-- audit_logs (in that order). The expected numbers are computed as postgres first from
-- the live data and the read policies, so the test does not depend on the seed:
--   student1  : own clearances, own items, own active holds, own charges, own payments, 0
--   cashier   : clearances with a Financial-office item, Financial items, 0, all, all, 0
--   department: clearances with an item of its office, its items, its active holds, 0, 0, 0
--   registrar : all, all, all active, 0, 0, 0
--   admin     : all, all, all active, 0, 0, all audit rows
-- One audit row is added as postgres first (undone by the rollback), so Admin has at
-- least one row to see and every other role must see 0.
-- Expected: every column ends in "-> OK", and student1_not_own is 0. With the seed:
-- student1 1,4,0,1,1,0; cashier 3,3,0,3,2,0; department 3,3,1,0,0,0;
-- registrar 3,12,1,0,0,0; admin 3,12,1,0,0,n (n >= 1).
begin;
insert into public.audit_logs (action, table_name, record_id) values ('INSERT', 'tc36_test', 'tc36'); -- undone by the rollback
select set_config('app.s1',   (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('app.cash', (select id::text from auth.users where email = 'cashier@pnc.test'), true);
select set_config('app.dept', (select id::text from auth.users where email = 'dept@pnc.test'), true);
select set_config('app.reg',  (select id::text from auth.users where email = 'registrar@pnc.test'), true);
select set_config('app.adm',  (select id::text from auth.users where email = 'admin@pnc.test'), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments where department_type = 'Financial'), '0'), true);
select set_config('app.mydept', coalesce((select min(department_id)::text from public.department_staff
  where profile_id = current_setting('app.dept')::uuid), '0'), true);
select set_config('app.exp_s1', concat_ws(',',
  (select count(*) from public.clearances where student_id = current_setting('app.s1')::uuid),
  (select count(*) from public.clearance_items i join public.clearances c on c.clearance_id = i.clearance_id
     where c.student_id = current_setting('app.s1')::uuid),
  (select count(*) from public.academic_holds where lifted_at is null and student_id = current_setting('app.s1')::uuid),
  (select count(*) from public.charges where student_id = current_setting('app.s1')::uuid),
  (select count(*) from public.payments p join public.charges c on c.charge_id = p.charge_id
     where c.student_id = current_setting('app.s1')::uuid),
  0), true);
select set_config('app.exp_cash', concat_ws(',',
  (select count(distinct clearance_id) from public.clearance_items where department_id = current_setting('app.fin')::bigint),
  (select count(*) from public.clearance_items where department_id = current_setting('app.fin')::bigint),
  0,
  (select count(*) from public.charges),
  (select count(*) from public.payments),
  0), true);
select set_config('app.exp_dept', concat_ws(',',
  (select count(distinct clearance_id) from public.clearance_items where department_id = current_setting('app.mydept')::bigint),
  (select count(*) from public.clearance_items where department_id = current_setting('app.mydept')::bigint),
  (select count(*) from public.academic_holds where lifted_at is null and department_id = current_setting('app.mydept')::bigint),
  0, 0, 0), true);
select set_config('app.exp_reg', concat_ws(',',
  (select count(*) from public.clearances),
  (select count(*) from public.clearance_items),
  (select count(*) from public.academic_holds where lifted_at is null),
  0, 0, 0), true);
select set_config('app.exp_adm', concat_ws(',',
  (select count(*) from public.clearances),
  (select count(*) from public.clearance_items),
  (select count(*) from public.academic_holds where lifted_at is null),
  0, 0,
  (select count(*) from public.audit_logs)), true);
set local role authenticated;
do $$
declare
  v_who text;
  v_got text;
  v_not_own bigint;
begin
  foreach v_who in array array['s1', 'cash', 'dept', 'reg', 'adm'] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || v_who), 'role', 'authenticated')::text, true);
    begin
      v_got := concat_ws(',',
        (select count(*) from public.v_clearances),
        (select count(*) from public.v_clearance_items),
        (select count(*) from public.v_active_holds),
        (select count(*) from public.charges),
        (select count(*) from public.payments),
        (select count(*) from public.audit_logs));
    exception when others then
      v_got := 'ERROR: ' || sqlerrm;
    end;
    perform set_config('app.r_' || v_who,
      v_got || ' | expected ' || current_setting('app.exp_' || v_who) || ' -> '
      || case when v_got = current_setting('app.exp_' || v_who) then 'OK' else 'MISMATCH' end, true);
    if v_who = 's1' then
      select (select count(*) from public.v_clearances where student_id is distinct from auth.uid())
           + (select count(*) from public.v_clearance_items where student_id is distinct from auth.uid())
           + (select count(*) from public.v_active_holds where student_id is distinct from auth.uid())
           + (select count(*) from public.charges where student_id is distinct from auth.uid())
        into v_not_own;
      perform set_config('app.s1_not_own', v_not_own::text, true);
    end if;
  end loop;
end $$;
select current_setting('app.r_s1') as student1, current_setting('app.s1_not_own') as student1_not_own,
  current_setting('app.r_cash') as cashier, current_setting('app.r_dept') as department,
  current_setting('app.r_reg') as registrar, current_setting('app.r_adm') as admin;
rollback;


-- ------------------------------------------
-- TC-37. Allowed writes per role (the real grants, no temporary grant)
-- ------------------------------------------
-- Every write the issue exposes, done by the one role whose policy allows it, using
-- only the granted columns. The target rows are picked as postgres first; a missing
-- target shows SKIPPED (record that half as "not run", not Pass).
-- Expected: every column "rows 1" (request_clearance also shows the number of items the
-- trigger created, one per department: 4 with the seed).
-- After trigger_finance_autoclear.sql (issue 23) the results are the same: update_charge
-- may now also auto-clear a pending Financial item when it settles the last charge of a
-- student for that term (with the seed the lowest charge is normally Student 1's, whose
-- Financial item is already cleared; either way the cell stays "rows 1"), and
-- request_clearance uses a term without charges,
-- so its Financial item stays pending.
begin;
select set_config('app.s1',   (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('app.cash', (select id::text from auth.users where email = 'cashier@pnc.test'), true);
select set_config('app.dept', (select id::text from auth.users where email = 'dept@pnc.test'), true);
select set_config('app.reg',  (select id::text from auth.users where email = 'registrar@pnc.test'), true);
-- Every seed student already has a clearance for the current term (unique student_id + term_id), so
-- request_clearance uses a throwaway term created here as postgres; the rollback removes it.
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2098-2099', '1st', '2098-08-01', '2099-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments where department_type = 'Financial'), ''), true);
select set_config('app.mydept', coalesce((select min(department_id)::text from public.department_staff
  where profile_id = current_setting('app.dept')::uuid), ''), true);
select set_config('app.clr', coalesce((select min(clearance_id)::text from public.clearances where approved_at is null), ''), true);
-- Not an item whose student has an active hold of the same department: trigger
-- require_no_active_hold (trigger_dept_approval.sql) would refuse to clear it.
select set_config('app.item_dept', coalesce((select min(ci.clearance_item_id)::text from public.clearance_items ci
  join public.clearances c on c.clearance_id = ci.clearance_id
  where ci.cleared_at is null and ci.department_id::text = current_setting('app.mydept')
    and not exists (select 1 from public.academic_holds h
                    where h.student_id = c.student_id and h.department_id = ci.department_id and h.lifted_at is null)), ''), true);
select set_config('app.item_fin', coalesce((select min(clearance_item_id)::text from public.clearance_items
  where cleared_at is null and department_id::text = current_setting('app.fin')), ''), true);
select set_config('app.hold', coalesce((select min(hold_id)::text from public.academic_holds
  where lifted_at is null and department_id::text = current_setting('app.mydept')), ''), true);
select set_config('app.own_student', coalesce((select s.student_id::text from public.students s
  join public.programs pr on pr.program_id = s.program_id
  where pr.department_id::text = current_setting('app.mydept')
  order by s.student_number limit 1), ''), true);
select set_config('app.charge', coalesce((select min(charge_id)::text from public.charges), ''), true);
set local role authenticated;
do $$
declare
  r record;
  n bigint;
  v_id bigint;
  v_items bigint;
begin
  for r in select * from (values
    ('request_clearance', 's1',   'term',
       $q$insert into public.clearances (student_id, term_id)
          values (auth.uid(), current_setting('app.term')::bigint) returning clearance_id$q$),
    ('approve_clearance', 'reg',  'clr',
       $q$update public.clearances set approved_by = auth.uid(), approved_at = now()
          where clearance_id = current_setting('app.clr')::bigint$q$),
    ('clear_item_dept',   'dept', 'item_dept',
       $q$update public.clearance_items set cleared_at = now(), cleared_by = auth.uid(), remarks = 'TC-37'
          where clearance_item_id = current_setting('app.item_dept')::bigint$q$),
    ('clear_item_cashier', 'cash', 'item_fin',
       $q$update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
          where clearance_item_id = current_setting('app.item_fin')::bigint$q$),
    ('place_hold',        'dept', 'own_student',
       $q$insert into public.academic_holds (student_id, department_id, reason, placed_by)
          values (current_setting('app.own_student')::uuid, current_setting('app.mydept')::bigint, 'TC-37 test', auth.uid())$q$),
    ('lift_hold',         'dept', 'hold',
       $q$update public.academic_holds set lifted_by = auth.uid(), lifted_at = now()
          where hold_id = current_setting('app.hold')::bigint$q$),
    ('record_payment',    'cash', 'charge',
       $q$insert into public.payments (charge_id, amount_paid, paid_at, receipt_number, recorded_by)
          values (current_setting('app.charge')::bigint, 100, now(), 'TC37-' || txid_current(), auth.uid())$q$),
    ('update_charge',     'cash', 'charge',
       $q$update public.charges set status = 'Waived', amount = amount, due_date = due_date
          where charge_id = current_setting('app.charge')::bigint$q$)
  ) as t(label, who, needs, stmt)
  loop
    if current_setting('app.' || r.needs) = '' then
      perform set_config('app.r_' || r.label, 'SKIPPED: no target row (' || r.needs || ')', true);
      continue;
    end if;
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      if r.label = 'request_clearance' then
        execute r.stmt into v_id;
        select count(*) into v_items from public.clearance_items where clearance_id = v_id;
        perform set_config('app.r_' || r.label, 'rows 1, items created ' || v_items, true);
      else
        execute r.stmt;
        get diagnostics n = row_count;
        perform set_config('app.r_' || r.label, 'rows ' || n, true);
      end if;
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
select current_setting('app.r_request_clearance') as request_clearance,
  current_setting('app.r_approve_clearance') as approve_clearance,
  current_setting('app.r_clear_item_dept') as clear_item_dept,
  current_setting('app.r_clear_item_cashier') as clear_item_cashier,
  current_setting('app.r_place_hold') as place_hold,
  current_setting('app.r_lift_hold') as lift_hold,
  current_setting('app.r_record_payment') as record_payment,
  current_setting('app.r_update_charge') as update_charge;
rollback;


-- ------------------------------------------
-- TC-38. Writes the GRANTs must refuse (permission denied, for every role)
-- ------------------------------------------
-- Run as Student 1, but these fail at the privilege check, before RLS, so the role
-- inside the app does not matter. UPDATE / DELETE use "where false" and INSERT values
-- that could never pass RLS, so even a wrongly allowed statement changes nothing (and
-- the rollback undoes everything anyway).
-- Expected: not_denied 0; every line in details "denied: permission denied for ..."
-- (v_clearance_items update: "denied: cannot update view ...", also a Pass).
begin;
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
  v_out text := '';
  v_bad int := 0;
begin
  for r in select * from (values
    -- no DELETE anywhere
    ('delete clearances',        $q$delete from public.clearances where false$q$),
    ('delete clearance_items',   $q$delete from public.clearance_items where false$q$),
    ('delete academic_holds',    $q$delete from public.academic_holds where false$q$),
    ('delete payments',          $q$delete from public.payments where false$q$),
    ('delete charges',           $q$delete from public.charges where false$q$),
    ('delete audit_logs',        $q$delete from public.audit_logs where false$q$),
    ('delete v_active_holds',    $q$delete from public.v_active_holds where false$q$),
    -- columns outside the grants
    ('clearances insert approved_by', $q$insert into public.clearances (student_id, term_id, approved_by) values (auth.uid(), 0, auth.uid())$q$),
    ('clearances insert created_at',  $q$insert into public.clearances (student_id, term_id, created_at) values (auth.uid(), 0, now())$q$),
    ('clearances update student_id',  $q$update public.clearances set student_id = auth.uid() where false$q$),
    ('clearances update created_at',  $q$update public.clearances set created_at = now() where false$q$),
    ('clearance_items insert',        $q$insert into public.clearance_items (clearance_id, department_id) values (0, 0)$q$),
    ('clearance_items update department_id', $q$update public.clearance_items set department_id = 0 where false$q$),
    ('holds insert placed_at',        $q$insert into public.academic_holds (student_id, department_id, reason, placed_by, placed_at) values (auth.uid(), 0, 'x', auth.uid(), now())$q$),
    ('holds insert lifted_by',        $q$insert into public.academic_holds (student_id, department_id, reason, placed_by, lifted_by) values (auth.uid(), 0, 'x', auth.uid(), auth.uid())$q$),
    ('holds update reason',           $q$update public.academic_holds set reason = 'x' where false$q$),
    ('payments update amount_paid',   $q$update public.payments set amount_paid = 1 where false$q$),
    ('payments insert payment_id',    $q$insert into public.payments (payment_id, charge_id, amount_paid, receipt_number, recorded_by) overriding system value values (0, 0, 1, 'tc38', auth.uid())$q$),
    ('charges insert',                $q$insert into public.charges (student_id, term_id, fee_type_id, amount) values (auth.uid(), 0, 0, 1)$q$),
    ('charges update student_id',     $q$update public.charges set student_id = auth.uid() where false$q$),
    ('charges update fee_type_id',    $q$update public.charges set fee_type_id = 0 where false$q$),
    ('audit_logs insert',             $q$insert into public.audit_logs (action, table_name, record_id) values ('INSERT', 'tc38', 'tc38')$q$),
    ('audit_logs update',             $q$update public.audit_logs set table_name = 'x' where false$q$),
    -- views are read-only for the app
    ('v_active_holds update',         $q$update public.v_active_holds set reason = 'x' where false$q$),
    ('v_clearances update',           $q$update public.v_clearances set approved_at = now() where false$q$),
    ('v_clearance_items update',      $q$update public.v_clearance_items set remarks = 'x' where false$q$)
  ) as t(label, stmt)
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_out := v_out || r.label || ' = NOT DENIED (rows ' || n || '); ';
      v_bad := v_bad + 1;
    exception when others then
      -- v_clearance_items joins 3 tables, so it is not an updatable view at all: PostgreSQL
      -- refuses with "cannot update view" before it checks privileges. Also a refusal.
      if sqlerrm like 'permission denied%' or sqlerrm like 'cannot update view%' then
        v_out := v_out || r.label || ' = denied: ' || sqlerrm || '; ';
      else
        v_out := v_out || r.label || ' = OTHER ERROR: ' || sqlerrm || '; ';
        v_bad := v_bad + 1;
      end if;
    end;
  end loop;
  perform set_config('app.not_denied', v_bad::text, true);
  perform set_config('app.details', v_out, true);
end $$;
select current_setting('app.not_denied')::int as not_denied, current_setting('app.details') as details;
rollback;


-- ------------------------------------------
-- TC-39. Granted columns, wrong role: RLS still isolates per role
-- ------------------------------------------
-- The grants go to every signed-in user, so this checks that RLS (not the grant) stops
-- the roles whose policy does not allow the write. Targets are picked as postgres.
-- Expected:
--   student_approves_own       rows 0  (clearances_registrar_approve: Registrar only)
--   student_requests_for_other rls: ... (clearances_student_request: own id only)
--   registrar_requests         rls: ... (clearances_student_request: Student only)
--   cashier_places_hold        rls: ... (holds_dept_place: Department only)
--   dept_records_payment       rls: ... (payments_cashier_insert: Cashier only)
--   dept_updates_charge        rows 0  (charges_cashier_update: Cashier only)
--   student_updates_charge     rows 0  (same)
--   student_clears_own_item    rows 0  (clearance_items_dept_update: Cashier / Department)
--   dept_lifts_other_office    rows 0  (holds_dept_lift: own department only; SKIPPED
--                                       if no active hold of another department exists)
-- "rows 0" or "rls: ..." are both a Pass where listed; any "rows 1" is a Fail.
begin;
select set_config('app.s1',   (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('app.s2',   (select id::text from auth.users where email = 'student2@pnc.test'), true);
select set_config('app.cash', (select id::text from auth.users where email = 'cashier@pnc.test'), true);
select set_config('app.dept', (select id::text from auth.users where email = 'dept@pnc.test'), true);
select set_config('app.reg',  (select id::text from auth.users where email = 'registrar@pnc.test'), true);
select set_config('app.term', coalesce((select min(term_id)::text from public.terms where is_current), '0'), true);
select set_config('app.mydept', coalesce((select min(department_id)::text from public.department_staff
  where profile_id = current_setting('app.dept')::uuid), '0'), true);
select set_config('app.charge', coalesce((select min(charge_id)::text from public.charges), '0'), true);
select set_config('app.s1_charge', coalesce((select min(charge_id)::text from public.charges
  where student_id = current_setting('app.s1')::uuid), '0'), true);
-- The seed has no active hold of another department, so add one here as postgres (undone by
-- the rollback); otherwise dept_lifts_other_office is SKIPPED.
insert into public.academic_holds (student_id, department_id, reason, placed_by)
select current_setting('app.s1')::uuid, d.department_id, 'TC-39 other office hold', current_setting('app.dept')::uuid
from (select min(department_id) as department_id from public.departments
      where department_id::text <> current_setting('app.mydept')) d
where d.department_id is not null
  and not exists (select 1 from public.academic_holds
                  where lifted_at is null and department_id::text <> current_setting('app.mydept'));
select set_config('app.other_hold', coalesce((select min(hold_id)::text from public.academic_holds
  where lifted_at is null and department_id::text <> current_setting('app.mydept')), ''), true);
set local role authenticated;
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    ('student_approves_own', 's1',
       $q$update public.clearances set approved_by = auth.uid(), approved_at = now() where student_id = auth.uid()$q$),
    ('student_requests_for_other', 's1',
       $q$insert into public.clearances (student_id, term_id) values (current_setting('app.s2')::uuid, current_setting('app.term')::bigint)$q$),
    ('registrar_requests', 'reg',
       $q$insert into public.clearances (student_id, term_id) values (auth.uid(), current_setting('app.term')::bigint)$q$),
    ('cashier_places_hold', 'cash',
       $q$insert into public.academic_holds (student_id, department_id, reason, placed_by)
          values (current_setting('app.s1')::uuid, current_setting('app.mydept')::bigint, 'TC-39', auth.uid())$q$),
    ('dept_records_payment', 'dept',
       $q$insert into public.payments (charge_id, amount_paid, receipt_number, recorded_by)
          values (current_setting('app.charge')::bigint, 1, 'TC39-' || txid_current(), auth.uid())$q$),
    ('dept_updates_charge', 'dept',
       $q$update public.charges set status = 'Waived' where charge_id = current_setting('app.charge')::bigint$q$),
    ('student_updates_charge', 's1',
       $q$update public.charges set amount = 1 where charge_id = current_setting('app.s1_charge')::bigint$q$),
    ('student_clears_own_item', 's1',
       $q$update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
          where clearance_id in (select clearance_id from public.clearances where student_id = auth.uid())$q$),
    ('dept_lifts_other_office', 'dept',
       $q$update public.academic_holds set lifted_by = auth.uid(), lifted_at = now()
          where hold_id::text = current_setting('app.other_hold')$q$)
  ) as t(label, who, stmt)
  loop
    if r.label = 'dept_lifts_other_office' and current_setting('app.other_hold') = '' then
      perform set_config('app.r_' || r.label, 'SKIPPED: no active hold of another department', true);
      continue;
    end if;
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.r_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.r_' || r.label,
        case when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
select current_setting('app.r_student_approves_own') as student_approves_own,
  current_setting('app.r_student_requests_for_other') as student_requests_for_other,
  current_setting('app.r_registrar_requests') as registrar_requests,
  current_setting('app.r_cashier_places_hold') as cashier_places_hold,
  current_setting('app.r_dept_records_payment') as dept_records_payment,
  current_setting('app.r_dept_updates_charge') as dept_updates_charge,
  current_setting('app.r_student_updates_charge') as student_updates_charge,
  current_setting('app.r_student_clears_own_item') as student_clears_own_item,
  current_setting('app.r_dept_lifts_other_office') as dept_lifts_other_office;
rollback;
