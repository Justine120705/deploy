-- ==========================================
-- REGRESSION TC-12 to TC-33 after grants_clearance.sql (GitHub issue #60)
-- ==========================================
-- One script, one transaction that ends in ROLLBACK, ONE result row. It repeats the checks
-- of Parts C, F, G and H of docs/issue-12-testing-guide.md (TC-12 to TC-33) and records each
-- result with set_config() because the SQL editor shows only the last result.
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file (from
-- "begin;" to "rollback;") and click Run on the whole tab, never a selection. Nothing is
-- committed. If the script stops with an error, run "rollback;" as its own query.
--
-- The temporary "grant insert, update on all tables" in section 3 is the same one Part F and G
-- use (undone by the rollback). It is needed because the real grants are column-level and
-- only for the clearance slice, so the old tests that write to other tables (grades,
-- charges.student_id) would stop at "permission denied" before reaching the RLS policy or the
-- column lock they test. With it, TC-18 to TC-26 test exactly what they tested before.
-- Sections 1 and 2 run BEFORE the temporary grant and use the real grants only.
--
-- Result keys (one column each in the final row):
--   r27, r29                      sections 1 (catalog checks, as postgres)
--   r12, r13, r14, r15, r16_28, r17, r30, r31, r32, r33   section 2 (as each role, real grants)
--   r18 .. r26                    section 3 (with the temporary grant)
-- "-> OK" or "-> FAIL" ends the cells that carry their own verdict; the cells that hold a JSON
-- row (r29, r30, r31) or the output of a loop (r32, r33) are compared with the guide.

begin;

select set_config('app.s1',   (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('app.s2',   (select id::text from auth.users where email = 'student2@pnc.test'), true);
select set_config('app.reg',  (select id::text from auth.users where email = 'registrar@pnc.test'), true);
select set_config('app.cash', (select id::text from auth.users where email = 'cashier@pnc.test'), true);
select set_config('app.cashier', current_setting('app.cash'), true);
select set_config('app.dept', (select id::text from auth.users where email = 'dept@pnc.test'), true);

-- ==========================================
-- 1. Catalog checks as postgres (TC-27, TC-29)
-- ==========================================

-- TC-27: grants (expected: trunc_refs_trigger f, anon_select_any f, anon_profiles_insert f,
-- auth_profiles_update t, auth_select_all t, auth_audit_insert f, the 4 anon_exec f, auth_exec_all_4 t)
select set_config('app.r27', (select row_to_json(t)::text from (select
  (select bool_or(has_table_privilege(r.rolname::name, c.oid, 'TRUNCATE')
               or has_table_privilege(r.rolname::name, c.oid, 'REFERENCES')
               or has_table_privilege(r.rolname::name, c.oid, 'TRIGGER'))
     from pg_class c cross join (values ('anon'), ('authenticated')) as r(rolname)
     where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')) as any_truncate_refs_trigger,
  (select bool_or(has_table_privilege('anon', c.oid, 'SELECT'))
     from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')) as anon_select_any,
  has_table_privilege('anon', 'public.profiles', 'INSERT') as anon_profiles_insert,
  has_table_privilege('authenticated', 'public.profiles', 'UPDATE') as auth_profiles_update,
  (select bool_and(has_table_privilege('authenticated', c.oid, 'SELECT'))
     from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')) as auth_select_all,
  has_table_privilege('authenticated', 'public.audit_logs', 'INSERT') as auth_audit_insert,
  has_function_privilege('anon', 'private.create_clearance_items()', 'EXECUTE') as anon_exec_create_items,
  has_function_privilege('anon', 'private.guard_immutable_columns()', 'EXECUTE') as anon_exec_guard,
  has_function_privilege('anon', 'private.audit_log()', 'EXECUTE') as anon_exec_audit_log,
  has_function_privilege('anon', 'private.audit_logs_readonly()', 'EXECUTE') as anon_exec_audit_readonly,
  (has_function_privilege('authenticated', 'private.create_clearance_items()', 'EXECUTE')
   and has_function_privilege('authenticated', 'private.guard_immutable_columns()', 'EXECUTE')
   and has_function_privilege('authenticated', 'private.audit_log()', 'EXECUTE')
   and has_function_privilege('authenticated', 'private.audit_logs_readonly()', 'EXECUTE')) as auth_exec_all_4) t), true);

-- TC-29: columns and view options (expected: expected_columns 41, missing_count 0, missing_columns "", views_security_invoker 4)
with expected(view_name, column_name) as (values
  ('v_active_holds', 'hold_id'), ('v_active_holds', 'student_id'), ('v_active_holds', 'department_id'),
  ('v_active_holds', 'reason'), ('v_active_holds', 'placed_by'), ('v_active_holds', 'placed_at'),
  ('v_clearance_items', 'clearance_item_id'), ('v_clearance_items', 'clearance_id'),
  ('v_clearance_items', 'student_id'), ('v_clearance_items', 'term_id'),
  ('v_clearance_items', 'department_id'), ('v_clearance_items', 'department_name'),
  ('v_clearance_items', 'department_type'), ('v_clearance_items', 'cleared_at'),
  ('v_clearance_items', 'cleared_by'), ('v_clearance_items', 'remarks'), ('v_clearance_items', 'status'),
  ('v_clearances', 'clearance_id'), ('v_clearances', 'student_id'), ('v_clearances', 'term_id'),
  ('v_clearances', 'created_at'), ('v_clearances', 'approved_by'), ('v_clearances', 'approved_at'),
  ('v_clearances', 'total_items'), ('v_clearances', 'cleared_items'), ('v_clearances', 'status'),
  ('v_grades', 'grade_id'), ('v_grades', 'enrollment_item_id'), ('v_grades', 'enrollment_id'),
  ('v_grades', 'student_id'), ('v_grades', 'term_id'), ('v_grades', 'section_id'),
  ('v_grades', 'subject_id'), ('v_grades', 'subject_code'), ('v_grades', 'subject_title'),
  ('v_grades', 'units'), ('v_grades', 'grade_code'), ('v_grades', 'numeric_value'),
  ('v_grades', 'is_passing'), ('v_grades', 'encoded_by'), ('v_grades', 'encoded_at')),
missing as (
  select e.view_name || '.' || e.column_name as col
  from expected e
  where not exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = e.view_name
                      and c.column_name = e.column_name))
select set_config('app.r29', (select row_to_json(t)::text from (select
  (select count(*) from expected) as expected_columns,
  (select count(*) from missing) as missing_count,
  coalesce((select string_agg(col, ', ' order by col) from missing), '') as missing_columns,
  (select count(*) from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
       and c.relname in ('v_active_holds', 'v_clearance_items', 'v_clearances', 'v_grades')
       and c.reloptions @> array['security_invoker=true']) as views_security_invoker) t), true);

-- Values the later sections compare against (read as postgres)
select set_config('app.n_grades', (select count(*)::text from public.grades), true);
select set_config('app.n_items', (select count(*)::text from public.clearance_items), true);
select set_config('app.n_clearances', (select count(*)::text from public.clearances), true);
select set_config('app.cid', coalesce((select min(clearance_id)::text from public.clearance_items), ''), true);
select set_config('app.cid_total', (select count(*)::text from public.clearance_items
  where clearance_id::text = current_setting('app.cid')), true);
select set_config('app.cid_cleared', (select count(*)::text from public.clearance_items
  where clearance_id::text = current_setting('app.cid') and cleared_at is not null), true);

-- ==========================================
-- 2. As each role, with the REAL grants only (TC-12 to TC-17, TC-28, TC-30 to TC-33)
-- ==========================================

-- Student 1 (TC-12, TC-13, TC-14, TC-15, TC-17)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare a bigint; b bigint; c bigint; d bigint; e bigint; f bigint; n bigint;
begin
  -- TC-12 (expected own_profile 1, other student grades 0)
  begin
    select count(*) into a from public.profiles where profile_id = auth.uid();
    select count(*) into b from public.grades g
      join public.enrollment_items ei on ei.enrollment_item_id = g.enrollment_item_id
      join public.enrollments en on en.enrollment_id = ei.enrollment_id
      where en.student_id = current_setting('app.s2')::uuid;
    perform set_config('app.r12', format('own_profile %s, s2_grades %s -> %s', a, b,
      case when a = 1 and b = 0 then 'OK' else 'FAIL' end), true);
  exception when others then perform set_config('app.r12', 'ERROR: ' || sqlerrm, true); end;
  -- TC-13 (expected s2 charges 0, s2 payments 0)
  begin
    select count(*) into a from public.charges where student_id = current_setting('app.s2')::uuid;
    select count(*) into b from public.payments p
      join public.charges ch on ch.charge_id = p.charge_id where ch.student_id = current_setting('app.s2')::uuid;
    select count(*) into c from public.payments;
    perform set_config('app.r13', format('s2_charges %s, s2_payments %s, own_payments %s -> %s', a, b, c,
      case when a = 0 and b = 0 then 'OK' else 'FAIL' end), true);
  exception when others then perform set_config('app.r13', 'ERROR: ' || sqlerrm, true); end;
  -- TC-14 (expected all 0)
  begin
    select count(*) into a from public.clearances where student_id = current_setting('app.s2')::uuid;
    select count(*) into b from public.academic_holds where student_id = current_setting('app.s2')::uuid;
    select count(*) into c from public.enrollments where student_id = current_setting('app.s2')::uuid;
    select count(*) into d from public.document_requests where student_id = current_setting('app.s2')::uuid;
    perform set_config('app.r14', format('s2 clearances %s, holds %s, enrollments %s, document_requests %s -> %s', a, b, c, d,
      case when a + b + c + d = 0 then 'OK' else 'FAIL' end), true);
  exception when others then perform set_config('app.r14', 'ERROR: ' || sqlerrm, true); end;
  -- TC-15 (expected students <= 1 in each view)
  begin
    select count(distinct student_id) into a from public.v_grades;
    select count(distinct student_id) into b from public.v_clearance_items;
    select count(distinct student_id) into c from public.v_clearances;
    select count(distinct student_id) into d from public.v_active_holds;
    perform set_config('app.r15', format('students in v_grades %s, v_clearance_items %s, v_clearances %s, v_active_holds %s -> %s', a, b, c, d,
      case when a <= 1 and b <= 1 and c <= 1 and d <= 1 then 'OK' else 'FAIL (leak)' end), true);
  exception when others then perform set_config('app.r15', 'ERROR: ' || sqlerrm, true); end;
  -- TC-17 (expected rows 0 or an error; rows 1 is critical)
  begin
    update public.profiles set role_id = (select role_id from public.roles where role_name = 'Admin')
      where profile_id = auth.uid();
    get diagnostics n = row_count;
    perform set_config('app.r17', format('rows %s -> %s', n, case when n = 0 then 'OK' else 'FAIL (CRITICAL)' end), true);
  exception when others then perform set_config('app.r17', 'blocked by error: ' || sqlerrm || ' -> OK', true); end;
end $$;

-- TC-30: Student 1 isolation through the views (compare with the guide)
select set_config('app.r30', (select row_to_json(t)::text from (select
  (select count(*) from public.v_grades) as v_grades_rows,
  (select count(*) from public.grades) as grades_rows,
  (select count(distinct student_id) from public.v_grades) as v_grades_students,
  (select count(*) from public.v_grades where student_id is distinct from auth.uid()) as v_grades_not_own,
  (select count(*) from public.v_clearance_items) as v_items_rows,
  (select count(*) from public.clearance_items) as items_rows,
  (select count(distinct student_id) from public.v_clearance_items) as v_items_students,
  (select count(*) from public.v_clearance_items where student_id is distinct from auth.uid()) as v_items_not_own,
  (select count(*) from public.v_clearances) as v_clearances_rows,
  (select count(*) from public.clearances) as clearances_rows,
  (select count(distinct student_id) from public.v_clearances) as v_clearances_students,
  (select bool_and(v.total_items = (select count(*) from public.clearance_items i where i.clearance_id = v.clearance_id)
               and v.cleared_items = (select count(*) from public.clearance_items i where i.clearance_id = v.clearance_id and i.cleared_at is not null))
     from public.v_clearances v) as counts_match,
  (select count(*) from public.v_active_holds) as v_holds_rows,
  (select count(*) from public.academic_holds where lifted_at is null) as active_holds_rows,
  (select count(distinct student_id) from public.v_active_holds) as v_holds_students,
  (select count(*) from public.v_grades where student_id = current_setting('app.s2')::uuid)
  + (select count(*) from public.v_clearance_items where student_id = current_setting('app.s2')::uuid)
  + (select count(*) from public.v_clearances where student_id = current_setting('app.s2')::uuid)
  + (select count(*) from public.v_active_holds where student_id = current_setting('app.s2')::uuid) as student2_rows_all_views) t), true);

-- TC-28 (second half): Student 1 sees only own grades
select set_config('app.r28_student', (select format('student1_visible_grades %s, student1_own_grades %s',
  (select count(*) from public.grades),
  (select count(*) from public.grades g
     join public.enrollment_items ei on ei.enrollment_item_id = g.enrollment_item_id
     join public.enrollments e on e.enrollment_id = ei.enrollment_id
     where e.student_id = auth.uid()))), true);

-- Registrar (TC-31)
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
set local role authenticated;
select set_config('app.r31', (select row_to_json(t)::text from (select
  (select count(*) from public.v_grades) || ' / ' || current_setting('app.n_grades') as v_grades_vs_real,
  (select count(*) from public.v_grades where student_id is null or subject_code is null) as v_grades_missing_join,
  (select count(*) from public.v_clearance_items) || ' / ' || current_setting('app.n_items') as v_items_vs_real,
  (select count(*) from public.v_clearance_items where student_id is null or department_name is null) as v_items_missing_join,
  (select count(*) from public.v_clearances) || ' / ' || current_setting('app.n_clearances') as v_clearances_vs_real,
  current_setting('app.cid') as clearance_id,
  (select total_items || ' / ' || current_setting('app.cid_total') from public.v_clearances
     where clearance_id::text = current_setting('app.cid')) as total_items_vs_real,
  (select cleared_items || ' / ' || current_setting('app.cid_cleared') from public.v_clearances
     where clearance_id::text = current_setting('app.cid')) as cleared_items_vs_real) t), true);

-- Cashier and Department (TC-32)
do $$
declare
  v_who text;
  vg bigint; g bigint; vi bigint; i bigint; vc bigint; c bigint; vh bigint; h bigint;
  v_depts bigint; v_max int;
begin
  foreach v_who in array array['cashier', 'dept'] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || v_who), 'role', 'authenticated')::text, true);
    select count(*) into vg from public.v_grades;
    select count(*) into g from public.grades;
    select count(*) into vi from public.v_clearance_items;
    select count(*) into i from public.clearance_items;
    select count(*) into vc from public.v_clearances;
    select count(*) into c from public.clearances;
    select count(*) into vh from public.v_active_holds;
    select count(*) into h from public.academic_holds where lifted_at is null;
    select count(distinct department_id) into v_depts from public.v_clearance_items;
    select max(total_items) into v_max from public.v_clearances;
    perform set_config('app.r32_' || v_who,
      format('grades %s/%s, items %s/%s, clearances %s/%s, holds %s/%s, item_depts %s, max_total_items %s -> %s',
        vg, g, vi, i, vc, c, vh, h, v_depts, coalesce(v_max::text, '-'),
        case when vg <= g and vi <= i and vc <= c and vh <= h then 'OK' else 'MORE THAN BASE TABLES' end),
      true);
  end loop;
end $$;
select set_config('app.r32', 'cashier: ' || current_setting('app.r32_cashier') || ' | department: ' || current_setting('app.r32_dept'), true);

-- Anonymous (TC-16, TC-28 first half, TC-33)
reset role;
set local role anon;
do $$
declare
  v_name text;
  n bigint;
begin
  foreach v_name in array array['grades', 'v_grades', 'v_active_holds', 'v_clearance_items', 'v_clearances'] loop
    begin
      execute format('select count(*) from public.%I', v_name) into n;
      perform set_config('app.ra_' || v_name, 'rows: ' || n, true);
    exception when others then
      perform set_config('app.ra_' || v_name, 'denied: ' || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('app.r16_28', format('anon grades [%s], v_grades [%s], student: %s -> %s',
  current_setting('app.ra_grades'), current_setting('app.ra_v_grades'), current_setting('app.r28_student'),
  case when current_setting('app.ra_grades') ~ '^(denied|rows: 0)' and current_setting('app.ra_v_grades') ~ '^(denied|rows: 0)' then 'OK' else 'FAIL' end), true);
select set_config('app.r33', format('v_active_holds [%s], v_clearance_items [%s], v_clearances [%s], v_grades [%s] -> %s',
  current_setting('app.ra_v_active_holds'), current_setting('app.ra_v_clearance_items'),
  current_setting('app.ra_v_clearances'), current_setting('app.ra_v_grades'),
  case when current_setting('app.ra_v_active_holds') ~ '^(denied|rows: 0)' and current_setting('app.ra_v_clearance_items') ~ '^(denied|rows: 0)'
        and current_setting('app.ra_v_clearances') ~ '^(denied|rows: 0)' and current_setting('app.ra_v_grades') ~ '^(denied|rows: 0)' then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 3. With the temporary grant (undone by the rollback): TC-18 to TC-26
-- ==========================================
grant insert, update on all tables in schema public to authenticated; -- temporary, undone by the rollback
select set_config('app.ccs', (select department_id::text from public.departments where code = 'CCS'), true);
select set_config('app.gid_max', (select max(grade_id)::text from public.grades), true);

-- TC-18 (expected: blocked by RLS on clearances), TC-19 (expected: approve 1, grade 1)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint; m bigint;
begin
  begin
    update public.clearances set approved_at = now(), approved_by = null
      where student_id = current_setting('app.s1')::uuid;
    get diagnostics n = row_count;
    perform set_config('app.r18', format('NOT BLOCKED, rows %s -> FAIL', n), true);
  exception when others then
    perform set_config('app.r18', 'blocked: ' || sqlerrm || ' -> ' || case when sqlerrm like '%row-level security%' then 'OK' else 'CHECK' end, true);
  end;
  begin
    update public.clearances set approved_at = now(), approved_by = auth.uid()
      where student_id = current_setting('app.s1')::uuid;
    get diagnostics n = row_count;
    update public.grades set grade_code = '1.25', encoded_by = auth.uid(), encoded_at = now()
      where grade_id = (select min(grade_id) from public.grades);
    get diagnostics m = row_count;
    perform set_config('app.r19', format('approve_clearance %s, correct_grade %s -> %s', n, m, case when n = 1 and m = 1 then 'OK' else 'FAIL' end), true);
  exception when others then perform set_config('app.r19', 'ERROR: ' || sqlerrm, true); end;
end $$;

-- TC-20 (expected: column charges.student_id cannot be changed), TC-21 part 2 (charge cleared: rows 1) as Cashier
-- After trigger_finance_autoclear.sql (issue 23): TC-21 settles Student 2's only charge, so the
-- trigger also clears Student 2's pending Financial item (cleared_by = the Cashier) and writes one
-- more audit row; every result cell stays the same (rolled back like everything else here).
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
-- TC-21 part 1 runs as postgres with the Cashier's claims (no grant on schema private needed)
select set_config('app.r21a', format('dept_id %s, expected %s', private.my_department_id(),
  (select min(department_id) from public.departments where department_type = 'Financial')), true);
set local role authenticated;
do $$
declare n bigint;
begin
  begin
    update public.charges set student_id = current_setting('app.s1')::uuid
      where student_id = current_setting('app.s2')::uuid;
    get diagnostics n = row_count;
    perform set_config('app.r20', format('NOT BLOCKED, rows %s -> FAIL', n), true);
  exception when others then
    perform set_config('app.r20', 'blocked: ' || sqlerrm || ' -> ' || case when sqlerrm like '%cannot be changed%' then 'OK' else 'CHECK' end, true);
  end;
  begin
    update public.charges set status = 'Cleared' where student_id = current_setting('app.s2')::uuid;
    get diagnostics n = row_count;
    perform set_config('app.r21b', format('rows %s', n), true);
  exception when others then perform set_config('app.r21b', 'ERROR: ' || sqlerrm, true); end;
end $$;
select set_config('app.r21', current_setting('app.r21a') || ', charge cleared ' || current_setting('app.r21b') || ' -> ' ||
  case when current_setting('app.r21b') = 'rows 1' then 'OK' else 'CHECK' end, true);

-- Department: TC-22 (expected: blocked by RLS on clearance_items), TC-23 (expected 1, 1, 1), TC-26 (own inserted, other RLS error)
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
select set_config('app.r22a', format('dept_id %s, expected %s', private.my_department_id(),
  (select department_id from public.departments where code = 'CCS')), true);
select set_config('app.mydept', coalesce(private.my_department_id()::text, ''), true);
select set_config('app.own', coalesce((select s.student_id::text from public.students s
  join public.programs pr on pr.program_id = s.program_id
  where pr.department_id::text = current_setting('app.mydept')
  order by s.student_number limit 1), ''), true);
select set_config('app.other', coalesce((select s.student_id::text from public.students s
  join public.programs pr on pr.program_id = s.program_id
  where pr.department_id::text <> current_setting('app.mydept')
  order by s.student_number limit 1), ''), true);
set local role authenticated;
do $$
declare n bigint; m bigint; k bigint;
begin
  begin
    update public.clearance_items set cleared_at = now(), cleared_by = null
      where department_id = current_setting('app.ccs')::bigint
        and clearance_id in (select clearance_id from public.clearances where student_id = current_setting('app.s1')::uuid);
    get diagnostics n = row_count;
    perform set_config('app.r22b', format('NOT BLOCKED, rows %s -> FAIL', n), true);
  exception when others then
    perform set_config('app.r22b', 'blocked: ' || sqlerrm || ' -> ' || case when sqlerrm like '%row-level security%' then 'OK' else 'CHECK' end, true);
  end;
  begin
    update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
      where department_id = current_setting('app.ccs')::bigint
        and clearance_id in (select clearance_id from public.clearances where student_id = current_setting('app.s1')::uuid);
    get diagnostics n = row_count;
    update public.academic_holds set lifted_at = now(), lifted_by = auth.uid()
      where student_id = current_setting('app.s2')::uuid and lifted_at is null;
    get diagnostics m = row_count;
    insert into public.academic_holds (student_id, department_id, reason, placed_by)
      values (current_setting('app.s1')::uuid, current_setting('app.ccs')::bigint, 'Regression test', auth.uid());
    get diagnostics k = row_count;
    perform set_config('app.r23', format('clear_item_as_self %s, lift_hold_as_self %s, place_hold_as_self %s -> %s', n, m, k,
      case when n = 1 and m = 1 and k = 1 then 'OK' else 'CHECK (a 0 can mean live data changed, look at the row)' end), true);
  exception when others then perform set_config('app.r23', 'ERROR: ' || sqlerrm, true); end;
  -- TC-26
  if current_setting('app.mydept') = '' then
    perform set_config('app.r26_own', 'SKIPPED: dept@pnc.test has no department', true);
    perform set_config('app.r26_other', 'SKIPPED: dept@pnc.test has no department', true);
  else
    if current_setting('app.own') = '' then
      perform set_config('app.r26_own', 'SKIPPED: no student in a program of this department', true);
    else
      begin
        insert into public.academic_holds (student_id, department_id, reason, placed_by)
        values (current_setting('app.own')::uuid, current_setting('app.mydept')::bigint, 'Regression26', auth.uid());
        perform set_config('app.r26_own', 'inserted', true);
      exception when others then perform set_config('app.r26_own', 'ERROR: ' || sqlerrm, true); end;
    end if;
    if current_setting('app.other') = '' then
      perform set_config('app.r26_other', 'SKIPPED: every student is in a program of this department', true);
    else
      begin
        insert into public.academic_holds (student_id, department_id, reason, placed_by)
        values (current_setting('app.other')::uuid, current_setting('app.mydept')::bigint, 'Regression26', auth.uid());
        perform set_config('app.r26_other', 'inserted', true);
      exception when others then perform set_config('app.r26_other', 'ERROR: ' || sqlerrm, true); end;
    end if;
  end if;
end $$;
select set_config('app.r22', current_setting('app.r22a') || '; ' || current_setting('app.r22b'), true);
select set_config('app.r26', 'own [' || current_setting('app.r26_own') || '], other [' || current_setting('app.r26_other') || ']', true);

-- TC-24: Registrar grade correction is written to the audit log (a grade TC-19 did not touch)
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
set local role authenticated;
update public.grades set grade_code = '1.50', encoded_by = auth.uid(), encoded_at = now()
  where grade_id = current_setting('app.gid_max')::bigint;
reset role;
select set_config('app.r24', (select format('audit_rows %s, actor_is_registrar %s, new_grade %s -> %s',
    count(*), bool_and(a.actor_id = current_setting('app.reg')::uuid), max(a.new_data ->> 'grade_code'),
    case when count(*) = 1 and bool_and(a.actor_id = current_setting('app.reg')::uuid) and max(a.new_data ->> 'grade_code') = '1.50' then 'OK' else 'FAIL' end)
  from public.audit_logs a
  where a.table_name = 'grades' and a.action = 'UPDATE'
    and a.record_id = current_setting('app.gid_max') and a.created_at = now()), true);

-- TC-25: audit_logs cannot be changed, deleted or truncated, even as postgres
insert into public.audit_logs (action, table_name, record_id) values ('INSERT', 'tc25_test', 'tc25');
do $$
begin
  begin
    update public.audit_logs set table_name = 'changed' where record_id = 'tc25';
    perform set_config('app.r25_u', 'NOT BLOCKED', true);
  exception when others then perform set_config('app.r25_u', 'blocked', true); end;
  begin
    delete from public.audit_logs where record_id = 'tc25';
    perform set_config('app.r25_d', 'NOT BLOCKED', true);
  exception when others then perform set_config('app.r25_d', 'blocked', true); end;
  begin
    truncate public.audit_logs;
    perform set_config('app.r25_t', 'NOT BLOCKED', true);
  exception when others then perform set_config('app.r25_t', 'blocked', true); end;
end $$;
select set_config('app.r25', format('ran_as %s, update %s, delete %s, truncate %s -> %s', current_user,
  current_setting('app.r25_u'), current_setting('app.r25_d'), current_setting('app.r25_t'),
  case when current_setting('app.r25_u') = 'blocked' and current_setting('app.r25_d') = 'blocked' and current_setting('app.r25_t') = 'blocked' then 'OK' else 'FAIL' end), true);

-- ==========================================
-- Result: ONE row. Compare each cell with the expected value in docs/issue-12-testing-guide.md
-- ==========================================
select current_setting('app.r12') as tc12, current_setting('app.r13') as tc13, current_setting('app.r14') as tc14,
  current_setting('app.r15') as tc15, current_setting('app.r16_28') as tc16_tc28, current_setting('app.r17') as tc17,
  current_setting('app.r18') as tc18, current_setting('app.r19') as tc19, current_setting('app.r20') as tc20,
  current_setting('app.r21') as tc21, current_setting('app.r22') as tc22, current_setting('app.r23') as tc23,
  current_setting('app.r24') as tc24, current_setting('app.r25') as tc25, current_setting('app.r26') as tc26,
  current_setting('app.r27') as tc27, current_setting('app.r29') as tc29, current_setting('app.r30') as tc30,
  current_setting('app.r31') as tc31, current_setting('app.r32') as tc32, current_setting('app.r33') as tc33;

rollback;
