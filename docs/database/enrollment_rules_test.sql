-- ==========================================
-- TESTS TC-109 to TC-122 for enrollment_rules.sql (GitHub issue #94, Sprint 4 issue 38)
-- ==========================================
-- Run AFTER enrollment_rules.sql is live (or use enrollment_rules_rehearsal.sql, which runs
-- the change and these tests together, TC-109R). This file is the same as the test part of
-- the rehearsal (from its "TESTS START HERE" marker).
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file and click
-- Run on the whole tab, never a selection. It ends in rollback: nothing is committed. If it
-- stops with an error, run "rollback;" as its own query and send the error back.
--
-- Data: every case creates its OWN throwaway terms (school years 2061-2062 to 2087-2088,
-- is_current false), sections and enrollments as postgres, for the seed students
-- student1 / student2 / student3 (they already have an enrollment in the current term, so
-- the current term is never used). All rows are created through the same triggers the
-- app uses (Pending first, then approved), so they satisfy every CHECK constraint on
-- enrollments, including any live one that ties status to reviewed_by / reviewed_at.
-- TC-109 prints every CHECK / UNIQUE constraint on enrollments, enrollment_items, sections
-- and terms (informational) so a surprise constraint is visible in the result.
-- Users are simulated with SET LOCAL ROLE authenticated + request.jwt.claims (sub = the
-- user's id); anon with SET LOCAL ROLE anon; "postgres" = no JWT (auth.uid() NULL).
-- now() is the same for the whole transaction, so reviewed_at = now() is exact.
--
-- Result: ONE row, one cell per case ending in "-> OK" or "-> FAIL", plus all_ok. Every
-- statement that is expected to fail runs inside a do block with an exception handler, so
-- the transaction is never aborted by an expected error. Each step is recorded as
-- "rows N" or "ERR [SQLSTATE]: message". Booleans inside cells may print as t / f.
--
--   TC-109 installed as intended (triggers and order, functions, grants, unique keys,
--          policies unchanged) + list of constraints
--   TC-110 a student submits an enrollment and adds 2 sections: Pending, reviewed_* NULL,
--          audit rows with the student as actor
--   TC-111 a second enrollment in the same term is refused ("enrollment exists:"), for the
--          student and for postgres
--   TC-112 a section of another term is refused when added ("wrong term:") and at approval
--          (section moved by the Admin afterwards)
--   TC-113 the same section twice is refused ("duplicate section:")
--   TC-114 approval without sections is refused ("no items:"), Registrar and postgres
--   TC-115 approval with a full section is refused ("section full:", DETAIL lists it)
--   TC-116 approval with free seats (a Pending student in a capacity-1 section does not
--          count): reviewed_by = the Registrar (spoofed value replaced), reviewed_at =
--          now() (sent value replaced), one audit row; afterwards that section is full
--   TC-117 Approved is final: Registrar, student and postgres cannot change the row or
--          its sections ("enrollment locked:")
--   TC-118 the Registrar rejects without sending reviewed_by: Rejected is final, no second
--          enrollment in that term
--   TC-119 roles: student cannot decide, set status, submit or add for another student or
--          delete; Cashier / Department / Admin cannot decide; Registrar cannot delete,
--          add sections or submit; each role reads only what RLS allows
--   TC-120 owner paths: INSERT must be Pending ("invalid status:"), reviewed_* forced NULL,
--          decision without reviewer refused ("reviewer required:"), Registrar
--          Pending -> Pending refused by RLS
--   TC-121 a student removes sections of their Pending enrollment (audited); then approval
--          has no items
--   TC-122 anon has no access; trigger functions: no anon / PUBLIC EXECUTE
--
-- Status: NOT RUN YET (written 2026-10-12 without a local PostgreSQL).

begin;

-- ==========================================
-- 1. Accounts and ids used by every case (as postgres, no user JWT)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.s3',   coalesce((select id::text from auth.users where email = 'student3@pnc.test'), ''), true);
select set_config('app.reg',  coalesce((select id::text from auth.users where email = 'registrar@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.dept', coalesce((select id::text from auth.users where email = 'dept@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.subj1', coalesce((select min(subject_id)::text from public.subjects), ''), true);
select set_config('app.subj2', coalesce((select max(subject_id)::text from public.subjects), ''), true);
do $$
declare v_bad text;
begin
  select string_agg(v.who || ' (' || v.role_name || ')', ', ') into v_bad
  from (values ('s1', 'Student'), ('s2', 'Student'), ('s3', 'Student'), ('reg', 'Registrar'),
               ('cash', 'Cashier'), ('dept', 'Department'), ('adm', 'Admin')) as v(who, role_name)
  where current_setting('app.' || v.who) = ''
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.' || v.who)
                      and p.is_active and r.role_name = v.role_name)
     or (v.role_name = 'Student'
         and not exists (select 1 from public.students s where s.student_id::text = current_setting('app.' || v.who)));
  if v_bad is not null then
    raise exception 'TC setup: seed account missing, inactive or with another role: %', v_bad;
  end if;
  if current_setting('app.subj1') = '' or current_setting('app.subj1') = current_setting('app.subj2') then
    raise exception 'TC setup: at least two subjects are needed (subj1 [%], subj2 [%])',
      current_setting('app.subj1'), current_setting('app.subj2');
  end if;
end $$;

-- ==========================================
-- 2. TC-109: installed as intended (catalog)
-- ==========================================
select set_config('app.r109', (select format('enr_before [%s], items_before [%s], audit_both %s, types [%s], functions_ok %s, function_grants_ok %s, unique_keys %s, table_privs_ok %s, column_grant_diff [%s], policies %s, constraints [%s] -> %s',
    x.enr_before, x.items_before, x.audit_both, x.types, x.fn_ok, x.fn_grants_ok, x.uniques, x.privs_ok,
    x.col_diff, x.policies, x.constraints,
    case when x.enr_before = 'guard_immutable_columns, require_enrollment_rules'
          and x.items_before = 'require_enrollment_item_rules'
          and x.audit_both and x.types = '23, 31' and x.fn_ok and x.fn_grants_ok
          and x.uniques = 2 and x.privs_ok and x.col_diff = '' and x.policies = 6
         then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(t.tgname::text, ', ' order by t.tgname) from pg_trigger t
      where t.tgrelid = 'public.enrollments'::regclass and not t.tgisinternal and (t.tgtype::int & 2) = 2) as enr_before,
    (select string_agg(t.tgname::text, ', ' order by t.tgname) from pg_trigger t
      where t.tgrelid = 'public.enrollment_items'::regclass and not t.tgisinternal and (t.tgtype::int & 2) = 2) as items_before,
    ((select count(*) from pg_trigger t
       where t.tgrelid in ('public.enrollments'::regclass, 'public.enrollment_items'::regclass)
         and t.tgname = 'audit_log' and not t.tgisinternal and t.tgenabled <> 'D'
         and t.tgfoid = to_regprocedure('private.audit_log()')) = 2) as audit_both,
    coalesce((select t.tgtype::text from pg_trigger t
               where t.tgrelid = 'public.enrollments'::regclass and t.tgname = 'require_enrollment_rules'
                 and t.tgenabled = 'O' and t.tgfoid = to_regprocedure('private.require_enrollment_rules()')), 'none')
      || ', ' ||
    coalesce((select t.tgtype::text from pg_trigger t
               where t.tgrelid = 'public.enrollment_items'::regclass and t.tgname = 'require_enrollment_item_rules'
                 and t.tgenabled = 'O' and t.tgfoid = to_regprocedure('private.require_enrollment_item_rules()')), 'none') as types,
    coalesce((select bool_and(p.prosecdef and p.proconfig && array['search_path=""', 'search_path='''''])
                and count(*) = 2
              from pg_proc p
             where p.oid in (to_regprocedure('private.require_enrollment_rules()'),
                             to_regprocedure('private.require_enrollment_item_rules()'))), false) as fn_ok,
    coalesce((select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')
                              and has_function_privilege('authenticated', p.oid, 'EXECUTE')
                              and p.proacl is not null
                              and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))
                and count(*) = 2
              from pg_proc p
             where p.oid in (to_regprocedure('private.require_enrollment_rules()'),
                             to_regprocedure('private.require_enrollment_item_rules()'))), false) as fn_grants_ok,
    (select count(*) from (values ('enrollments', array['student_id', 'term_id']),
                                  ('enrollment_items', array['enrollment_id', 'section_id'])) as e(t, cols)
      where exists (select 1 from pg_index i
                     where i.indrelid = ('public.' || e.t)::regclass and i.indisunique
                       and i.indpred is null and i.indexprs is null and i.indnatts = 2
                       and (select array_agg(a.attname::text order by a.attname::text)
                              from unnest(i.indkey::int2[]) as k(attnum)
                              join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum) = e.cols)) as uniques,
    (not has_table_privilege('anon', 'public.enrollments', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
     and not has_table_privilege('anon', 'public.enrollment_items', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
     and not has_any_column_privilege('anon', 'public.enrollments', 'SELECT, INSERT, UPDATE')
     and not has_any_column_privilege('anon', 'public.enrollment_items', 'SELECT, INSERT, UPDATE')
     and has_table_privilege('authenticated', 'public.enrollments', 'SELECT')
     and has_table_privilege('authenticated', 'public.enrollment_items', 'SELECT')
     and not has_table_privilege('authenticated', 'public.enrollments', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
     and not has_table_privilege('authenticated', 'public.enrollment_items', 'INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER')
     and has_table_privilege('authenticated', 'public.enrollment_items', 'DELETE')) as privs_ok,
    coalesce((with expected(t, col, priv) as (values
                ('enrollments', 'student_id', 'INSERT'), ('enrollments', 'term_id', 'INSERT'),
                ('enrollments', 'year_level', 'INSERT'),
                ('enrollments', 'status', 'UPDATE'), ('enrollments', 'reviewed_by', 'UPDATE'),
                ('enrollments', 'reviewed_at', 'UPDATE'), ('enrollments', 'remarks', 'UPDATE'),
                ('enrollment_items', 'enrollment_id', 'INSERT'), ('enrollment_items', 'section_id', 'INSERT')),
              live as (
                select c.relname::text as t, a.attname::text as col, x.privilege_type::text as priv
                from pg_attribute a
                join pg_class c on c.oid = a.attrelid
                cross join lateral aclexplode(a.attacl) x
                where c.oid in ('public.enrollments'::regclass, 'public.enrollment_items'::regclass)
                  and a.attnum > 0 and not a.attisdropped and a.attacl is not null
                  and x.grantee = 'authenticated'::regrole)
              select string_agg(d, '; ' order by d) from (
                (select 'missing ' || t || '.' || col || ' ' || priv as d from (select * from expected except select * from live) m)
                union all
                (select 'unexpected ' || t || '.' || col || ' ' || priv from (select * from live except select * from expected) u)) dd), '') as col_diff,
    (select count(*) from pg_policies p
      where p.schemaname = 'public' and p.tablename in ('enrollments', 'enrollment_items')) as policies,
    coalesce((select string_agg(c.conrelid::regclass::text || '.' || c.conname || ' ' || pg_get_constraintdef(c.oid), '; '
                                order by c.conrelid::regclass::text, c.conname)
                from pg_constraint c
               where c.contype in ('c', 'u')
                 and c.conrelid in ('public.enrollments'::regclass, 'public.enrollment_items'::regclass,
                                    'public.sections'::regclass, 'public.terms'::regclass)), '') as constraints
  ) x), true);

-- ==========================================
-- 3. TC-110: a student submits an enrollment and adds 2 sections
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2061-2062', '1st', '2061-08-01', '2062-01-15', false) returning term_id)
select set_config('app.t110', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t110')::bigint, 'TC110-A', 'TBA', 40) returning section_id)
select set_config('app.sec110a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t110')::bigint, 'TC110-B', 'TBA', 40) returning section_id)
select set_config('app.sec110b', section_id::text, true) from s;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint; n bigint;
begin
  begin
    insert into public.enrollments (student_id, term_id, year_level)
    values (auth.uid(), current_setting('app.t110')::bigint, 1)
    returning enrollment_id into v_id;
    perform set_config('app.e110', v_id::text, true);
    perform set_config('app.c110_ins', 'rows 1', true);
  exception when others then
    perform set_config('app.e110', '0', true);
    perform set_config('app.c110_ins', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
  end;
  begin
    insert into public.enrollment_items (enrollment_id, section_id)
    values (current_setting('app.e110')::bigint, current_setting('app.sec110a')::bigint),
           (current_setting('app.e110')::bigint, current_setting('app.sec110b')::bigint);
    get diagnostics n = row_count;
    perform set_config('app.c110_items', 'rows ' || n, true);
  exception when others then
    perform set_config('app.c110_items', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
  end;
  begin
    select count(*) into n from public.enrollment_items where enrollment_id = current_setting('app.e110')::bigint;
    perform set_config('app.c110_read', 'items ' || n, true);
  exception when others then
    perform set_config('app.c110_read', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r110', format('insert [%s], items [%s], read [%s], row [%s], audit_enrollment %s, audit_items %s -> %s',
  current_setting('app.c110_ins'), current_setting('app.c110_items'), current_setting('app.c110_read'),
  coalesce((select e.status || ', reviewed ' || coalesce(e.reviewed_by::text, 'NULL') || ' / ' || coalesce(e.reviewed_at::text, 'NULL')
                   || ', year ' || e.year_level || ', submitted_now ' || (e.submitted_at = now())
              from public.enrollments e where e.enrollment_id = current_setting('app.e110')::bigint), 'none'),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
      and l.record_id = current_setting('app.e110') and l.action = 'INSERT' and l.actor_id::text = current_setting('app.s1')),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollment_items'
      and l.new_data ->> 'enrollment_id' = current_setting('app.e110') and l.action = 'INSERT'
      and l.actor_id::text = current_setting('app.s1')),
  case when current_setting('app.c110_ins') = 'rows 1' and current_setting('app.c110_items') = 'rows 2'
        and current_setting('app.c110_read') = 'items 2'
        and coalesce((select e.status = 'Pending' and e.reviewed_by is null and e.reviewed_at is null
                             and e.year_level = 1 and e.submitted_at = now() and e.student_id::text = current_setting('app.s1')
                        from public.enrollments e where e.enrollment_id = current_setting('app.e110')::bigint), false)
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
                and l.record_id = current_setting('app.e110') and l.action = 'INSERT'
                and l.actor_id::text = current_setting('app.s1')) = 1
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollment_items'
                and l.new_data ->> 'enrollment_id' = current_setting('app.e110') and l.action = 'INSERT'
                and l.actor_id::text = current_setting('app.s1')) = 2
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 4. TC-111: a second enrollment in the same term is refused
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2063-2064', '1st', '2063-08-01', '2064-01-15', false) returning term_id)
select set_config('app.t111', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t111')::bigint, 'TC111-A', 'TBA', 40) returning section_id)
select set_config('app.sec111a', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t111')::bigint, 1) returning enrollment_id)
select set_config('app.e111', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e111')::bigint, current_setting('app.sec111a')::bigint);
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c111_student', 's1', $q$insert into public.enrollments (student_id, term_id, year_level)
                                values (auth.uid(), current_setting('app.t111')::bigint, 1)$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  insert into public.enrollments (student_id, term_id, year_level)
  values (current_setting('app.s1')::uuid, current_setting('app.t111')::bigint, 2);
  get diagnostics n = row_count;
  perform set_config('app.c111_pg', 'rows ' || n, true);
exception when others then
  perform set_config('app.c111_pg', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.r111', format('student [%s], detail [%s], postgres [%s], enrollments_in_term %s -> %s',
  current_setting('app.c111_student'), current_setting('app.c111_student_d'), current_setting('app.c111_pg'),
  (select count(*) from public.enrollments where student_id::text = current_setting('app.s1')
      and term_id = current_setting('app.t111')::bigint),
  case when current_setting('app.c111_student') like 'ERR [P0001]: enrollment exists:%'
        and current_setting('app.c111_student_d') = 'existing enrollment: ' || current_setting('app.e111')
        and current_setting('app.c111_pg') like 'ERR [P0001]: enrollment exists:%'
        and (select count(*) from public.enrollments where student_id::text = current_setting('app.s1')
               and term_id = current_setting('app.t111')::bigint) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 5. TC-112: a section of another term is refused (when added and at approval)
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2065-2066', '1st', '2065-08-01', '2066-01-15', false) returning term_id)
select set_config('app.t112a', term_id::text, true) from t;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2067-2068', '1st', '2067-08-01', '2068-01-15', false) returning term_id)
select set_config('app.t112b', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t112a')::bigint, 'TC112-A', 'TBA', 40) returning section_id)
select set_config('app.sec112a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t112b')::bigint, 'TC112-B', 'TBA', 40) returning section_id)
select set_config('app.sec112b', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t112a')::bigint, 1) returning enrollment_id)
select set_config('app.e112', enrollment_id::text, true) from e;
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c112_other', 's1', $q$insert into public.enrollment_items (enrollment_id, section_id)
                              values (current_setting('app.e112')::bigint, current_setting('app.sec112b')::bigint)$q$),
    (2, 'c112_same',  's1', $q$insert into public.enrollment_items (enrollment_id, section_id)
                              values (current_setting('app.e112')::bigint, current_setting('app.sec112a')::bigint)$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- the Admin moves section A to the other term after the student picked it (as postgres)
update public.sections set term_id = current_setting('app.t112b')::bigint
where section_id = current_setting('app.sec112a')::bigint;
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c112_approve', 'reg', $q$update public.enrollments set status = 'Approved'
                                 where enrollment_id = current_setting('app.e112')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r112', format('add_other_term [%s], add_same_term [%s], approve_after_move [%s], detail [%s], status %s -> %s',
  current_setting('app.c112_other'), current_setting('app.c112_same'), current_setting('app.c112_approve'),
  current_setting('app.c112_approve_d'),
  coalesce((select status from public.enrollments where enrollment_id = current_setting('app.e112')::bigint), 'none'),
  case when current_setting('app.c112_other') like 'ERR [P0001]: wrong term: section ' || current_setting('app.sec112b') || ' %'
        and current_setting('app.c112_same') = 'rows 1'
        and current_setting('app.c112_approve') like 'ERR [P0001]: wrong term: enrollment ' || current_setting('app.e112') || ' %'
        and current_setting('app.c112_approve_d') like 'sections of another term: TC112-A %'
        and coalesce((select status = 'Pending' and reviewed_at is null from public.enrollments
                       where enrollment_id = current_setting('app.e112')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 6. TC-113: the same section twice is refused
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2069-2070', '1st', '2069-08-01', '2070-01-15', false) returning term_id)
select set_config('app.t113', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t113')::bigint, 'TC113-A', 'TBA', 40) returning section_id)
select set_config('app.sec113a', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t113')::bigint, 1) returning enrollment_id)
select set_config('app.e113', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e113')::bigint, current_setting('app.sec113a')::bigint);
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c113_student', 's1', $q$insert into public.enrollment_items (enrollment_id, section_id)
                                values (current_setting('app.e113')::bigint, current_setting('app.sec113a')::bigint)$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  insert into public.enrollment_items (enrollment_id, section_id)
  values (current_setting('app.e113')::bigint, current_setting('app.sec113a')::bigint);
  get diagnostics n = row_count;
  perform set_config('app.c113_pg', 'rows ' || n, true);
exception when others then
  perform set_config('app.c113_pg', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.r113', format('student [%s], postgres [%s], items %s -> %s',
  current_setting('app.c113_student'), current_setting('app.c113_pg'),
  (select count(*) from public.enrollment_items where enrollment_id = current_setting('app.e113')::bigint),
  case when current_setting('app.c113_student') like 'ERR [P0001]: duplicate section:%'
        and current_setting('app.c113_pg') like 'ERR [P0001]: duplicate section:%'
        and (select count(*) from public.enrollment_items where enrollment_id = current_setting('app.e113')::bigint) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 7. TC-114: approval without sections is refused
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2071-2072', '1st', '2071-08-01', '2072-01-15', false) returning term_id)
select set_config('app.t114', term_id::text, true) from t;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t114')::bigint, 1) returning enrollment_id)
select set_config('app.e114', enrollment_id::text, true) from e;
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c114_reg', 'reg', $q$update public.enrollments set status = 'Approved', reviewed_by = auth.uid()
                             where enrollment_id = current_setting('app.e114')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid
  where enrollment_id = current_setting('app.e114')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.c114_pg', 'rows ' || n, true);
exception when others then
  perform set_config('app.c114_pg', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.r114', format('registrar [%s], postgres [%s], status %s -> %s',
  current_setting('app.c114_reg'), current_setting('app.c114_pg'),
  coalesce((select status from public.enrollments where enrollment_id = current_setting('app.e114')::bigint), 'none'),
  case when current_setting('app.c114_reg') = 'ERR [P0001]: no items: enrollment ' || current_setting('app.e114')
                                              || ' cannot be approved because it has no sections'
        and current_setting('app.c114_pg') = 'ERR [P0001]: no items: enrollment ' || current_setting('app.e114')
                                             || ' cannot be approved because it has no sections'
        and coalesce((select status = 'Pending' and reviewed_by is null and reviewed_at is null
                        from public.enrollments where enrollment_id = current_setting('app.e114')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 8. TC-115: approval with a full section is refused
-- ==========================================
-- Section A has capacity 1 and Student 2 is already Approved in it; Student 1 picks A and B.
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2073-2074', '1st', '2073-08-01', '2074-01-15', false) returning term_id)
select set_config('app.t115', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t115')::bigint, 'TC115-A', 'TBA', 1) returning section_id)
select set_config('app.sec115a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t115')::bigint, 'TC115-B', 'TBA', 40) returning section_id)
select set_config('app.sec115b', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s2')::uuid, current_setting('app.t115')::bigint, 1) returning enrollment_id)
select set_config('app.e115x', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e115x')::bigint, current_setting('app.sec115a')::bigint);
do $$
declare n bigint;
begin
  update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid
  where enrollment_id = current_setting('app.e115x')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.c115_setup', 'rows ' || n, true);
exception when others then
  perform set_config('app.c115_setup', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t115')::bigint, 1) returning enrollment_id)
select set_config('app.e115', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e115')::bigint, current_setting('app.sec115a')::bigint),
       (current_setting('app.e115')::bigint, current_setting('app.sec115b')::bigint);
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c115_reg', 'reg', $q$update public.enrollments set status = 'Approved', reviewed_by = auth.uid()
                             where enrollment_id = current_setting('app.e115')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid
  where enrollment_id = current_setting('app.e115')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.c115_pg', 'rows ' || n, true);
exception when others then
  perform set_config('app.c115_pg', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.r115', format('setup_other_approved [%s], registrar [%s], detail [%s], postgres [%s], status %s -> %s',
  current_setting('app.c115_setup'), current_setting('app.c115_reg'), current_setting('app.c115_reg_d'),
  current_setting('app.c115_pg'),
  coalesce((select status from public.enrollments where enrollment_id = current_setting('app.e115')::bigint), 'none'),
  case when current_setting('app.c115_setup') = 'rows 1'
        and current_setting('app.c115_reg') = 'ERR [P0001]: section full: enrollment ' || current_setting('app.e115')
                                              || ' cannot be approved because 1 of its 2 sections have no seat left'
        and current_setting('app.c115_reg_d') = 'full sections: TC115-A (section ' || current_setting('app.sec115a')
                                                || ', 1 of 1 seats taken)'
        and current_setting('app.c115_pg') like 'ERR [P0001]: section full: enrollment ' || current_setting('app.e115') || ' %'
        and coalesce((select status = 'Pending' and reviewed_by is null from public.enrollments
                       where enrollment_id = current_setting('app.e115')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 9. TC-116: approval with free seats; reviewed_by / reviewed_at come from the database
-- ==========================================
-- Section A (capacity 1): Student 3 Pending in it (does not count). Section B (capacity 2):
-- Student 2 Approved in it (1 seat left). Student 1 picks A and B.
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2075-2076', '1st', '2075-08-01', '2076-01-15', false) returning term_id)
select set_config('app.t116', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t116')::bigint, 'TC116-A', 'TBA', 1) returning section_id)
select set_config('app.sec116a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t116')::bigint, 'TC116-B', 'TBA', 2) returning section_id)
select set_config('app.sec116b', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s3')::uuid, current_setting('app.t116')::bigint, 1) returning enrollment_id)
select set_config('app.e116y', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e116y')::bigint, current_setting('app.sec116a')::bigint);
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s2')::uuid, current_setting('app.t116')::bigint, 1) returning enrollment_id)
select set_config('app.e116x', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e116x')::bigint, current_setting('app.sec116b')::bigint);
do $$
declare n bigint;
begin
  update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid
  where enrollment_id = current_setting('app.e116x')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.c116_setup', 'rows ' || n, true);
exception when others then
  perform set_config('app.c116_setup', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t116')::bigint, 1) returning enrollment_id)
select set_config('app.e116', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e116')::bigint, current_setting('app.sec116a')::bigint),
       (current_setting('app.e116')::bigint, current_setting('app.sec116b')::bigint);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c116_reg', 'reg', $q$update public.enrollments
                               set status = 'Approved', reviewed_by = current_setting('app.adm')::uuid,
                                   reviewed_at = '2000-01-01 00:00:00+00', remarks = 'TC-116 approved'
                             where enrollment_id = current_setting('app.e116')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid
  where enrollment_id = current_setting('app.e116y')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.c116_s3', 'rows ' || n, true);
exception when others then
  perform set_config('app.c116_s3', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.r116', format('setup [%s], registrar [%s], row [%s], audit_rows %s, audit_ok %s, student3_after [%s] -> %s',
  current_setting('app.c116_setup'), current_setting('app.c116_reg'),
  coalesce((select e.status || ', by_registrar ' || (e.reviewed_by::text = current_setting('app.reg'))
                   || ', at_now ' || (e.reviewed_at = now()) || ', remarks ' || coalesce(e.remarks, 'NULL')
              from public.enrollments e where e.enrollment_id = current_setting('app.e116')::bigint), 'none'),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
      and l.record_id = current_setting('app.e116')),
  coalesce((select bool_and(l.action = 'UPDATE' and l.actor_id::text = current_setting('app.reg')
                            and l.old_data ->> 'status' = 'Pending' and l.new_data ->> 'status' = 'Approved'
                            and l.new_data ->> 'reviewed_by' = current_setting('app.reg'))
              from public.audit_logs l
             where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
               and l.record_id = current_setting('app.e116')), false),
  current_setting('app.c116_s3'),
  case when current_setting('app.c116_setup') = 'rows 1' and current_setting('app.c116_reg') = 'rows 1'
        and coalesce((select e.status = 'Approved' and e.reviewed_by::text = current_setting('app.reg')
                             and e.reviewed_at = now() and e.remarks = 'TC-116 approved'
                        from public.enrollments e where e.enrollment_id = current_setting('app.e116')::bigint), false)
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
                and l.record_id = current_setting('app.e116')) = 1
        and coalesce((select bool_and(l.action = 'UPDATE' and l.actor_id::text = current_setting('app.reg')
                                      and l.old_data ->> 'status' = 'Pending' and l.new_data ->> 'status' = 'Approved'
                                      and l.new_data ->> 'reviewed_by' = current_setting('app.reg'))
                        from public.audit_logs l
                       where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
                         and l.record_id = current_setting('app.e116')), false)
        and current_setting('app.c116_s3') like 'ERR [P0001]: section full: enrollment ' || current_setting('app.e116y') || ' %'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 10. TC-117: Approved is final
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2077-2078', '1st', '2077-08-01', '2078-01-15', false) returning term_id)
select set_config('app.t117', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t117')::bigint, 'TC117-A', 'TBA', 40) returning section_id)
select set_config('app.sec117a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t117')::bigint, 'TC117-B', 'TBA', 40) returning section_id)
select set_config('app.sec117b', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t117')::bigint, 1) returning enrollment_id)
select set_config('app.e117', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e117')::bigint, current_setting('app.sec117a')::bigint);
do $$
declare n bigint;
begin
  update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid
  where enrollment_id = current_setting('app.e117')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.c117_setup', 'rows ' || n, true);
exception when others then
  perform set_config('app.c117_setup', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c117_reject',  'reg', $q$update public.enrollments set status = 'Rejected', reviewed_by = auth.uid()
                                 where enrollment_id = current_setting('app.e117')::bigint$q$),
    (2, 'c117_remarks', 'reg', $q$update public.enrollments set remarks = 'changed', reviewed_by = auth.uid()
                                 where enrollment_id = current_setting('app.e117')::bigint$q$),
    (3, 'c117_pending', 'reg', $q$update public.enrollments set status = 'Pending', reviewed_by = auth.uid()
                                 where enrollment_id = current_setting('app.e117')::bigint$q$),
    (4, 'c117_add',     's1',  $q$insert into public.enrollment_items (enrollment_id, section_id)
                                 values (current_setting('app.e117')::bigint, current_setting('app.sec117b')::bigint)$q$),
    (5, 'c117_remove',  's1',  $q$delete from public.enrollment_items
                                 where enrollment_id = current_setting('app.e117')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c117_pg_status', $q$update public.enrollments set status = 'Pending'
                            where enrollment_id = current_setting('app.e117')::bigint$q$),
    (2, 'c117_pg_delete', $q$delete from public.enrollment_items
                            where enrollment_id = current_setting('app.e117')::bigint$q$),
    (3, 'c117_pg_add',    $q$insert into public.enrollment_items (enrollment_id, section_id)
                            values (current_setting('app.e117')::bigint, current_setting('app.sec117b')::bigint)$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
    end;
  end loop;
end $$;
select set_config('app.r117', format('setup [%s], reg_reject [%s], reg_remarks [%s], reg_pending [%s], student_add [%s], student_remove [%s], pg_status [%s], pg_delete [%s], pg_add [%s], final [%s] -> %s',
  current_setting('app.c117_setup'), current_setting('app.c117_reject'), current_setting('app.c117_remarks'),
  current_setting('app.c117_pending'), current_setting('app.c117_add'), current_setting('app.c117_remove'),
  current_setting('app.c117_pg_status'), current_setting('app.c117_pg_delete'), current_setting('app.c117_pg_add'),
  coalesce((select e.status || ', items ' || (select count(*) from public.enrollment_items i where i.enrollment_id = e.enrollment_id)
                   || ', remarks ' || coalesce(e.remarks, 'NULL')
              from public.enrollments e where e.enrollment_id = current_setting('app.e117')::bigint), 'none'),
  case when current_setting('app.c117_setup') = 'rows 1'
        and current_setting('app.c117_reject') like 'ERR [P0001]: enrollment locked: enrollment ' || current_setting('app.e117') || ' is Approved %'
        and current_setting('app.c117_remarks') like 'ERR [P0001]: enrollment locked:%'
        and current_setting('app.c117_pending') like 'ERR [P0001]: enrollment locked:%'
        and current_setting('app.c117_add') like 'ERR [P0001]: enrollment locked:%'
        and current_setting('app.c117_remove') = 'rows 0'
        and current_setting('app.c117_pg_status') like 'ERR [P0001]: enrollment locked:%'
        and current_setting('app.c117_pg_delete') like 'ERR [P0001]: enrollment locked:%'
        and current_setting('app.c117_pg_add') like 'ERR [P0001]: enrollment locked:%'
        and coalesce((select e.status = 'Approved' and e.remarks is null and e.reviewed_by::text = current_setting('app.reg')
                             and (select count(*) from public.enrollment_items i where i.enrollment_id = e.enrollment_id) = 1
                        from public.enrollments e where e.enrollment_id = current_setting('app.e117')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 11. TC-118: the Registrar rejects (without sending reviewed_by); Rejected is final
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2079-2080', '1st', '2079-08-01', '2080-01-15', false) returning term_id)
select set_config('app.t118', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t118')::bigint, 'TC118-A', 'TBA', 40) returning section_id)
select set_config('app.sec118a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t118')::bigint, 'TC118-B', 'TBA', 40) returning section_id)
select set_config('app.sec118b', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t118')::bigint, 1) returning enrollment_id)
select set_config('app.e118', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e118')::bigint, current_setting('app.sec118a')::bigint);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c118_reject',    'reg', $q$update public.enrollments set status = 'Rejected', remarks = 'TC-118 missing prerequisites'
                                   where enrollment_id = current_setting('app.e118')::bigint$q$),
    (2, 'c118_reapprove', 'reg', $q$update public.enrollments set status = 'Approved'
                                   where enrollment_id = current_setting('app.e118')::bigint$q$),
    (3, 'c118_again',     's1',  $q$insert into public.enrollments (student_id, term_id, year_level)
                                   values (auth.uid(), current_setting('app.t118')::bigint, 1)$q$),
    (4, 'c118_add',       's1',  $q$insert into public.enrollment_items (enrollment_id, section_id)
                                   values (current_setting('app.e118')::bigint, current_setting('app.sec118b')::bigint)$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r118', format('reject [%s], row [%s], reapprove [%s], second_enrollment [%s], add_section [%s], audit_rows %s -> %s',
  current_setting('app.c118_reject'),
  coalesce((select e.status || ', by_registrar ' || (e.reviewed_by::text = current_setting('app.reg'))
                   || ', at_now ' || (e.reviewed_at = now()) || ', remarks ' || coalesce(e.remarks, 'NULL')
              from public.enrollments e where e.enrollment_id = current_setting('app.e118')::bigint), 'none'),
  current_setting('app.c118_reapprove'), current_setting('app.c118_again'), current_setting('app.c118_add'),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
      and l.record_id = current_setting('app.e118') and l.action = 'UPDATE'
      and l.actor_id::text = current_setting('app.reg') and l.new_data ->> 'status' = 'Rejected'),
  case when current_setting('app.c118_reject') = 'rows 1'
        and coalesce((select e.status = 'Rejected' and e.reviewed_by::text = current_setting('app.reg')
                             and e.reviewed_at = now() and e.remarks = 'TC-118 missing prerequisites'
                        from public.enrollments e where e.enrollment_id = current_setting('app.e118')::bigint), false)
        and current_setting('app.c118_reapprove') like 'ERR [P0001]: enrollment locked: enrollment ' || current_setting('app.e118') || ' is Rejected %'
        and current_setting('app.c118_again') like 'ERR [P0001]: enrollment exists:%'
        and current_setting('app.c118_add') like 'ERR [P0001]: enrollment locked:%'
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollments'
                and l.record_id = current_setting('app.e118') and l.action = 'UPDATE'
                and l.actor_id::text = current_setting('app.reg') and l.new_data ->> 'status' = 'Rejected') = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 12. TC-119: roles (grants + RLS)
-- ==========================================
-- Term A: Student 1 (e119) and Student 2 (e119b), both Pending with section A. Term B: empty.
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2081-2082', '2nd', '2082-01-20', '2082-05-30', false) returning term_id)
select set_config('app.t119', term_id::text, true) from t;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2083-2084', '2nd', '2084-01-20', '2084-05-30', false) returning term_id)
select set_config('app.t119b', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t119')::bigint, 'TC119-A', 'TBA', 40) returning section_id)
select set_config('app.sec119a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t119')::bigint, 'TC119-B', 'TBA', 40) returning section_id)
select set_config('app.sec119b', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t119')::bigint, 1) returning enrollment_id)
select set_config('app.e119', enrollment_id::text, true) from e;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s2')::uuid, current_setting('app.t119')::bigint, 1) returning enrollment_id)
select set_config('app.e119b', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e119')::bigint, current_setting('app.sec119a')::bigint),
       (current_setting('app.e119b')::bigint, current_setting('app.sec119a')::bigint);
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1,  'c119_s_decide',    's1',   $q$update public.enrollments set status = 'Approved', reviewed_by = auth.uid()
                                       where enrollment_id = current_setting('app.e119')::bigint$q$),
    (2,  'c119_s_status',    's1',   $q$insert into public.enrollments (student_id, term_id, year_level, status)
                                       values (auth.uid(), current_setting('app.t119b')::bigint, 1, 'Approved')$q$),
    (3,  'c119_s_other',     's1',   $q$insert into public.enrollments (student_id, term_id, year_level)
                                       values (current_setting('app.s2')::uuid, current_setting('app.t119b')::bigint, 1)$q$),
    (4,  'c119_s_item_other','s1',   $q$insert into public.enrollment_items (enrollment_id, section_id)
                                       values (current_setting('app.e119b')::bigint, current_setting('app.sec119b')::bigint)$q$),
    (5,  'c119_s_delete',    's1',   $q$delete from public.enrollments where enrollment_id = current_setting('app.e119')::bigint$q$),
    (6,  'c119_s_read_other','s1',   $q$select 1 from public.enrollments where enrollment_id = current_setting('app.e119b')::bigint$q$),
    (7,  'c119_s_read_own',  's1',   $q$select 1 from public.enrollment_items where enrollment_id = current_setting('app.e119')::bigint$q$),
    (8,  'c119_cash',        'cash', $q$update public.enrollments set status = 'Approved', reviewed_by = auth.uid()
                                       where enrollment_id = current_setting('app.e119')::bigint$q$),
    (9,  'c119_dept',        'dept', $q$update public.enrollments set status = 'Approved', reviewed_by = auth.uid()
                                       where enrollment_id = current_setting('app.e119')::bigint$q$),
    (10, 'c119_adm',         'adm',  $q$update public.enrollments set status = 'Approved', reviewed_by = auth.uid()
                                       where enrollment_id = current_setting('app.e119')::bigint$q$),
    (11, 'c119_r_delete',    'reg',  $q$delete from public.enrollments where enrollment_id = current_setting('app.e119')::bigint$q$),
    (12, 'c119_r_item',      'reg',  $q$insert into public.enrollment_items (enrollment_id, section_id)
                                       values (current_setting('app.e119')::bigint, current_setting('app.sec119b')::bigint)$q$),
    (13, 'c119_r_submit',    'reg',  $q$insert into public.enrollments (student_id, term_id, year_level)
                                       values (current_setting('app.s1')::uuid, current_setting('app.t119b')::bigint, 1)$q$),
    (14, 'c119_r_read',      'reg',  $q$select 1 from public.enrollments
                                       where enrollment_id in (current_setting('app.e119')::bigint, current_setting('app.e119b')::bigint)$q$),
    (15, 'c119_s2_remove',   's2',   $q$delete from public.enrollment_items where enrollment_id = current_setting('app.e119')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r119', format('s_decide [%s], s_status [%s], s_other [%s], s_item_other [%s], s_delete [%s], s_read_other [%s], s_read_own [%s], cashier [%s], department [%s], admin [%s], r_delete [%s], r_item [%s], r_submit [%s], r_read [%s], s2_remove [%s], final [%s] -> %s',
  current_setting('app.c119_s_decide'), current_setting('app.c119_s_status'), current_setting('app.c119_s_other'),
  current_setting('app.c119_s_item_other'), current_setting('app.c119_s_delete'), current_setting('app.c119_s_read_other'),
  current_setting('app.c119_s_read_own'), current_setting('app.c119_cash'), current_setting('app.c119_dept'),
  current_setting('app.c119_adm'), current_setting('app.c119_r_delete'), current_setting('app.c119_r_item'),
  current_setting('app.c119_r_submit'), current_setting('app.c119_r_read'), current_setting('app.c119_s2_remove'),
  (select string_agg(e.enrollment_id || ' ' || e.status || ' items ' ||
                     (select count(*) from public.enrollment_items i where i.enrollment_id = e.enrollment_id), ', '
                     order by e.enrollment_id)
     from public.enrollments e where e.term_id in (current_setting('app.t119')::bigint, current_setting('app.t119b')::bigint)),
  case when current_setting('app.c119_s_decide') = 'rows 0'
        and current_setting('app.c119_s_status') like 'ERR [42501]: permission denied%'
        and current_setting('app.c119_s_other') like 'ERR [42501]: new row violates row-level security%'
        and current_setting('app.c119_s_item_other') like 'ERR [42501]: new row violates row-level security%'
        and current_setting('app.c119_s_delete') like 'ERR [42501]: permission denied%'
        and current_setting('app.c119_s_read_other') = 'rows 0'
        and current_setting('app.c119_s_read_own') = 'rows 1'
        and current_setting('app.c119_cash') = 'rows 0'
        and current_setting('app.c119_dept') = 'rows 0'
        and current_setting('app.c119_adm') = 'rows 0'
        and current_setting('app.c119_r_delete') like 'ERR [42501]: permission denied%'
        and current_setting('app.c119_r_item') like 'ERR [42501]: new row violates row-level security%'
        and current_setting('app.c119_r_submit') like 'ERR [42501]: new row violates row-level security%'
        and current_setting('app.c119_r_read') = 'rows 2'
        and current_setting('app.c119_s2_remove') = 'rows 0'
        and (select count(*) from public.enrollments e
              where e.term_id in (current_setting('app.t119')::bigint, current_setting('app.t119b')::bigint)) = 2
        and (select bool_and(e.status = 'Pending' and e.reviewed_by is null) from public.enrollments e
              where e.term_id = current_setting('app.t119')::bigint)
        and (select count(*) from public.enrollment_items i
              where i.enrollment_id in (current_setting('app.e119')::bigint, current_setting('app.e119b')::bigint)) = 2
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 13. TC-120: owner paths and the Registrar's Pending -> Pending update
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2085-2086', '1st', '2085-08-01', '2086-01-15', false) returning term_id)
select set_config('app.t120', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t120')::bigint, 'TC120-A', 'TBA', 40) returning section_id)
select set_config('app.sec120a', section_id::text, true) from s;
do $$
declare n bigint;
begin
  insert into public.enrollments (student_id, term_id, year_level, status, reviewed_by, reviewed_at)
  values (current_setting('app.s1')::uuid, current_setting('app.t120')::bigint, 1, 'Approved',
          current_setting('app.reg')::uuid, now());
  get diagnostics n = row_count;
  perform set_config('app.c120_ins_approved', 'rows ' || n, true);
exception when others then
  perform set_config('app.c120_ins_approved', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
-- a Pending insert that names a reviewer: the trigger clears reviewed_by / reviewed_at
with e as (insert into public.enrollments (student_id, term_id, year_level, reviewed_by, reviewed_at)
           values (current_setting('app.s1')::uuid, current_setting('app.t120')::bigint, 1,
                   current_setting('app.reg')::uuid, now()) returning enrollment_id)
select set_config('app.e120', enrollment_id::text, true) from e;
select set_config('app.c120_forced', coalesce((select (reviewed_by is null and reviewed_at is null)::text
  from public.enrollments where enrollment_id = current_setting('app.e120')::bigint), 'none'), true);
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e120')::bigint, current_setting('app.sec120a')::bigint);
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c120_no_reviewer', $q$update public.enrollments set status = 'Approved'
                              where enrollment_id = current_setting('app.e120')::bigint$q$),
    (2, 'c120_year',        $q$update public.enrollments set year_level = 2
                              where enrollment_id = current_setting('app.e120')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
    end;
  end loop;
end $$;
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c120_reg_remarks', 'reg', $q$update public.enrollments set remarks = 'note', reviewed_by = auth.uid()
                                     where enrollment_id = current_setting('app.e120')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare n bigint;
begin
  update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid,
                                reviewed_at = '2000-01-01 00:00:00+00'
  where enrollment_id = current_setting('app.e120')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.c120_pg_approve', 'rows ' || n, true);
exception when others then
  perform set_config('app.c120_pg_approve', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.r120', format('insert_approved [%s], reviewed_forced_null %s, no_reviewer [%s], year_level [%s], registrar_pending_update [%s], pg_approve [%s], row [%s] -> %s',
  current_setting('app.c120_ins_approved'), current_setting('app.c120_forced'), current_setting('app.c120_no_reviewer'),
  current_setting('app.c120_year'), current_setting('app.c120_reg_remarks'), current_setting('app.c120_pg_approve'),
  coalesce((select e.status || ', year ' || e.year_level || ', by_registrar ' || (e.reviewed_by::text = current_setting('app.reg'))
                   || ', at_now ' || (e.reviewed_at = now()) || ', remarks ' || coalesce(e.remarks, 'NULL')
              from public.enrollments e where e.enrollment_id = current_setting('app.e120')::bigint), 'none'),
  case when current_setting('app.c120_ins_approved') like 'ERR [P0001]: invalid status:%'
        and current_setting('app.c120_forced') = 'true'
        and current_setting('app.c120_no_reviewer') like 'ERR [P0001]: reviewer required:%'
        and current_setting('app.c120_year') = 'rows 1'
        and current_setting('app.c120_reg_remarks') like 'ERR [42501]: new row violates row-level security%'
        and current_setting('app.c120_pg_approve') = 'rows 1'
        and coalesce((select e.status = 'Approved' and e.year_level = 2 and e.reviewed_by::text = current_setting('app.reg')
                             and e.reviewed_at = now() and e.remarks is null
                        from public.enrollments e where e.enrollment_id = current_setting('app.e120')::bigint), false)
        and (select count(*) from public.enrollments where student_id::text = current_setting('app.s1')
               and term_id = current_setting('app.t120')::bigint) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 14. TC-121: a student removes sections of their Pending enrollment
-- ==========================================
select set_config('request.jwt.claims', '', true);
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2087-2088', '1st', '2087-08-01', '2088-01-15', false) returning term_id)
select set_config('app.t121', term_id::text, true) from t;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj1')::bigint, current_setting('app.t121')::bigint, 'TC121-A', 'TBA', 40) returning section_id)
select set_config('app.sec121a', section_id::text, true) from s;
with s as (insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
           values (current_setting('app.subj2')::bigint, current_setting('app.t121')::bigint, 'TC121-B', 'TBA', 40) returning section_id)
select set_config('app.sec121b', section_id::text, true) from s;
with e as (insert into public.enrollments (student_id, term_id, year_level)
           values (current_setting('app.s1')::uuid, current_setting('app.t121')::bigint, 1) returning enrollment_id)
select set_config('app.e121', enrollment_id::text, true) from e;
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.e121')::bigint, current_setting('app.sec121a')::bigint),
       (current_setting('app.e121')::bigint, current_setting('app.sec121b')::bigint);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
do $$
declare r record; n bigint; v_detail text;
begin
  for r in select * from (values
    (1, 'c121_rm1', 's1',  $q$delete from public.enrollment_items
                             where enrollment_id = current_setting('app.e121')::bigint
                               and section_id = current_setting('app.sec121a')::bigint$q$),
    (2, 'c121_rm2', 's1',  $q$delete from public.enrollment_items
                             where enrollment_id = current_setting('app.e121')::bigint
                               and section_id = current_setting('app.sec121b')::bigint$q$),
    (3, 'c121_reg', 'reg', $q$update public.enrollments set status = 'Approved'
                             where enrollment_id = current_setting('app.e121')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
      perform set_config('app.' || r.label || '_d', '', true);
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
      perform set_config('app.' || r.label || '_d', coalesce(v_detail, ''), true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r121', format('remove_1 [%s], remove_2 [%s], items_left %s, audit_deletes %s, approve_empty [%s], status %s -> %s',
  current_setting('app.c121_rm1'), current_setting('app.c121_rm2'),
  (select count(*) from public.enrollment_items where enrollment_id = current_setting('app.e121')::bigint),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollment_items'
      and l.action = 'DELETE' and l.old_data ->> 'enrollment_id' = current_setting('app.e121')
      and l.actor_id::text = current_setting('app.s1')),
  current_setting('app.c121_reg'),
  coalesce((select status from public.enrollments where enrollment_id = current_setting('app.e121')::bigint), 'none'),
  case when current_setting('app.c121_rm1') = 'rows 1' and current_setting('app.c121_rm2') = 'rows 1'
        and (select count(*) from public.enrollment_items where enrollment_id = current_setting('app.e121')::bigint) = 0
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'enrollment_items'
                and l.action = 'DELETE' and l.old_data ->> 'enrollment_id' = current_setting('app.e121')
                and l.actor_id::text = current_setting('app.s1')) = 2
        and current_setting('app.c121_reg') like 'ERR [P0001]: no items:%'
        and coalesce((select status = 'Pending' from public.enrollments
                       where enrollment_id = current_setting('app.e121')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 15. TC-122: anon has no access; trigger functions are not callable by anon
-- ==========================================
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c122_read_enr',   $q$select 1 from public.enrollments$q$),
    (2, 'c122_read_items', $q$select 1 from public.enrollment_items$q$),
    (3, 'c122_insert',     $q$insert into public.enrollments (student_id, term_id, year_level)
                             values (current_setting('app.s1')::uuid, current_setting('app.t121')::bigint, 1)$q$),
    (4, 'c122_call_enr',   $q$select private.require_enrollment_rules()$q$),
    (5, 'c122_call_item',  $q$select private.require_enrollment_item_rules()$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label, 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
begin
  perform private.require_enrollment_rules();
  perform set_config('app.c122_auth_call', 'NO ERROR', true);
exception when others then
  perform set_config('app.c122_auth_call', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r122', format('anon_read_enrollments [%s], anon_read_items [%s], anon_insert [%s], anon_call_enr [%s], anon_call_item [%s], authenticated_call [%s] -> %s',
  current_setting('app.c122_read_enr'), current_setting('app.c122_read_items'), current_setting('app.c122_insert'),
  current_setting('app.c122_call_enr'), current_setting('app.c122_call_item'), current_setting('app.c122_auth_call'),
  case when current_setting('app.c122_read_enr') like 'ERR [42501]: permission denied%'
        and current_setting('app.c122_read_items') like 'ERR [42501]: permission denied%'
        and current_setting('app.c122_insert') like 'ERR [42501]: permission denied%'
        and current_setting('app.c122_call_enr') like 'ERR [42501]: permission denied%'
        and current_setting('app.c122_call_item') like 'ERR [42501]: permission denied%'
        and current_setting('app.c122_auth_call') like 'ERR [%'
        and current_setting('app.c122_auth_call') not like 'ERR [42501]%'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- Result: ONE row
-- ==========================================
select (current_setting('app.r109') like '%-> OK' and current_setting('app.r110') like '%-> OK'
        and current_setting('app.r111') like '%-> OK' and current_setting('app.r112') like '%-> OK'
        and current_setting('app.r113') like '%-> OK' and current_setting('app.r114') like '%-> OK'
        and current_setting('app.r115') like '%-> OK' and current_setting('app.r116') like '%-> OK'
        and current_setting('app.r117') like '%-> OK' and current_setting('app.r118') like '%-> OK'
        and current_setting('app.r119') like '%-> OK' and current_setting('app.r120') like '%-> OK'
        and current_setting('app.r121') like '%-> OK' and current_setting('app.r122') like '%-> OK') as all_ok,
  current_setting('app.r109') as tc109, current_setting('app.r110') as tc110, current_setting('app.r111') as tc111,
  current_setting('app.r112') as tc112, current_setting('app.r113') as tc113, current_setting('app.r114') as tc114,
  current_setting('app.r115') as tc115, current_setting('app.r116') as tc116, current_setting('app.r117') as tc117,
  current_setting('app.r118') as tc118, current_setting('app.r119') as tc119, current_setting('app.r120') as tc120,
  current_setting('app.r121') as tc121, current_setting('app.r122') as tc122;

rollback;
