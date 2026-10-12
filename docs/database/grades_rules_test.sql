-- ==========================================
-- TESTS FOR grades_rules.sql (GitHub issue #92): TC-83 to TC-93
-- ==========================================
-- One script, one transaction that ends in ROLLBACK, ONE result row. To run the change
-- AND these tests together before the live run, use
-- docs/database/grades_rules_rehearsal.sql (its part after "TESTS START HERE" is this
-- file, verbatim).
--
-- How to run (AFTER grades_rules.sql is live): Supabase SQL editor, as postgres, a new
-- tab. Paste the whole file (from "begin;" to "rollback;") and click Run on the whole tab,
-- never a selection. Nothing is committed. If the script stops with an error, run
-- "rollback;" as its own query and send the error back.
--
-- Rules (same as the earlier test files):
--   - Roles are impersonated as in grants_clearance_test.sql: the user ids are looked up
--     by e-mail (seed accounts *@pnc.test) as postgres, then "set local role
--     authenticated" (or anon) and request.jwt.claims = {"sub": <id>, "role":
--     "authenticated"} via set_config(..., true). postgres steps run with empty claims.
--   - No temporary GRANT: only the real grants of grades_rules.sql are used.
--   - No SKIPPED results: the script CREATES its own data as postgres inside the
--     transaction (undone by the rollback): a throwaway term (2093-2094) with three
--     sections, an Approved enrollment for Student 1 (items A1, A2, A3), a Pending
--     enrollment for Student 2 (item P1) and an Approved enrollment for Student 3 (item
--     O1); postgres encodes a grade for A3 (Student 1's own) and for O1 (another
--     student). If a seed account is missing the setup stops with "TC setup: ...".
--   - Expected errors are caught inside do blocks and shown as text:
--       "blocked [P0001]: not approved: ..." = the new approved-enrollment trigger
--       "denied: ..."                        = permission denied (grants)
--       "rls: ..."                           = new row violates row-level security policy
--       "fk [23503]: ..."                    = foreign key violation (unknown grade code)
--       "rows N"                             = the statement ran and changed N rows
--   - Every cell ends in "-> OK" or "-> FAIL"; all_ok must be true. (Booleans inside the
--     cells may print as t / f.)
--
-- Cases:
--   TC-83 installed as intended (triggers, functions, grants; catalog)
--   TC-84 a student reads only own grades (grades and v_grades)
--   TC-85 a student cannot write grades (insert, update, delete)
--   TC-86 the Registrar inserts and updates a grade
--   TC-87 the Registrar cannot set encoded_by to someone else
--   TC-88 anon is denied everything (read and write)
--   TC-89 no DELETE for anyone through the API
--   TC-90 a grade for a Pending enrollment is refused (Registrar and postgres), and is
--         accepted once the enrollment is Approved
--   TC-91 an unknown grade_code is refused (foreign key to grade_scale)
--   TC-92 encoded_at comes from the database (column not granted; a value sent by
--         postgres is overwritten)
--   TC-93 the Registrar's insert and update are in the audit log
--
-- Status: NOT RUN YET.

begin;

-- ==========================================
-- Setup (as postgres, no user JWT; undone by the rollback)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',  coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',  coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.s3',  coalesce((select id::text from auth.users where email = 'student3@pnc.test'), ''), true);
select set_config('app.reg', coalesce((select id::text from auth.users where email = 'registrar@pnc.test'), ''), true);
select set_config('app.subj', coalesce((select min(subject_id)::text from public.subjects), ''), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.s3'),
            current_setting('app.reg'), current_setting('app.subj'))
     or (select count(*) from public.students
          where student_id::text in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.s3'))) <> 3
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                     where p.profile_id::text = current_setting('app.reg') and p.is_active and r.role_name = 'Registrar')
     or exists (select 1 from public.grade_scale where grade_code = 'X.XX')
     or not exists (select 1 from public.grade_scale where grade_code = '1.00')
     or not exists (select 1 from public.grade_scale where grade_code = '1.50')
     or not exists (select 1 from public.grade_scale where grade_code = '1.75')
     or not exists (select 1 from public.grade_scale where grade_code = '2.00') then
    raise exception 'TC setup: seed account, student, active Registrar, subject or grade_scale row missing (s1 [%], s2 [%], s3 [%], reg [%], subject [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.s3'),
      current_setting('app.reg'), current_setting('app.subj');
  end if;
end $$;

-- a throwaway term with three sections
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2093-2094', '1st', '2093-08-01', '2094-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
insert into public.sections (subject_id, term_id, section_code, schedule, capacity)
select current_setting('app.subj')::bigint, current_setting('app.term')::bigint, v.code, 'TC-83 test', 40
from (values ('TC-A'), ('TC-B'), ('TC-C')) as v(code);
select set_config('app.sec_a', (select min(section_id)::text from public.sections
  where term_id = current_setting('app.term')::bigint and section_code = 'TC-A'), true);
select set_config('app.sec_b', (select min(section_id)::text from public.sections
  where term_id = current_setting('app.term')::bigint and section_code = 'TC-B'), true);
select set_config('app.sec_c', (select min(section_id)::text from public.sections
  where term_id = current_setting('app.term')::bigint and section_code = 'TC-C'), true);

-- enrollments: submitted as Pending, then Student 1's and Student 3's approved by postgres
insert into public.enrollments (student_id, term_id, year_level)
values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint, 1),
       (current_setting('app.s2')::uuid, current_setting('app.term')::bigint, 1),
       (current_setting('app.s3')::uuid, current_setting('app.term')::bigint, 1);
select set_config('app.enr_a', (select min(enrollment_id)::text from public.enrollments
  where term_id = current_setting('app.term')::bigint and student_id = current_setting('app.s1')::uuid), true);
select set_config('app.enr_p', (select min(enrollment_id)::text from public.enrollments
  where term_id = current_setting('app.term')::bigint and student_id = current_setting('app.s2')::uuid), true);
select set_config('app.enr_o', (select min(enrollment_id)::text from public.enrollments
  where term_id = current_setting('app.term')::bigint and student_id = current_setting('app.s3')::uuid), true);
update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid, reviewed_at = now()
where enrollment_id in (current_setting('app.enr_a')::bigint, current_setting('app.enr_o')::bigint);

-- enrollment items: A1, A2, A3 (Student 1, Approved), P1 (Student 2, Pending), O1 (Student 3, Approved)
insert into public.enrollment_items (enrollment_id, section_id)
values (current_setting('app.enr_a')::bigint, current_setting('app.sec_a')::bigint),
       (current_setting('app.enr_a')::bigint, current_setting('app.sec_b')::bigint),
       (current_setting('app.enr_a')::bigint, current_setting('app.sec_c')::bigint),
       (current_setting('app.enr_p')::bigint, current_setting('app.sec_a')::bigint),
       (current_setting('app.enr_o')::bigint, current_setting('app.sec_a')::bigint);
select set_config('app.item_a1', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_a')::bigint and section_id = current_setting('app.sec_a')::bigint), true);
select set_config('app.item_a2', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_a')::bigint and section_id = current_setting('app.sec_b')::bigint), true);
select set_config('app.item_a3', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_a')::bigint and section_id = current_setting('app.sec_c')::bigint), true);
select set_config('app.item_p1', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_p')::bigint), true);
select set_config('app.item_o1', (select min(enrollment_item_id)::text from public.enrollment_items
  where enrollment_id = current_setting('app.enr_o')::bigint), true);

-- grades encoded by postgres: A3 (Student 1's own) and O1 (another student's)
insert into public.grades (enrollment_item_id, grade_code, encoded_by)
values (current_setting('app.item_a3')::bigint, '1.50', current_setting('app.reg')::uuid),
       (current_setting('app.item_o1')::bigint, '2.00', current_setting('app.reg')::uuid);

-- ==========================================
-- TC-83: installed as intended (catalog, as postgres)
-- ==========================================
select set_config('app.r83', (select format('triggers [%s], functions_invoker_empty_path %s, function_grants_ok %s, anon_any_privilege %s, auth_select %s, auth_table_level_writes %s, auth_columns [%s] -> %s',
    x.trig, x.fn_ok, x.acl_ok, x.anon_any, x.auth_select, x.auth_table_writes, x.cols,
    case when x.trig = 'guard_immutable_columns (BEFORE) > require_approved_enrollment (BEFORE) > stamp_encoded_at (BEFORE) > audit_log (AFTER)'
          and x.fn_ok and x.acl_ok and not x.anon_any and x.auth_select and not x.auth_table_writes
          and x.cols = 'INSERT(encoded_by), INSERT(enrollment_item_id), INSERT(grade_code), UPDATE(encoded_by), UPDATE(grade_code)'
         then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(tg.tgname::text || ' (' || case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end || ')', ' > '
                       order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.grades'::regclass and not tg.tgisinternal) as trig,
    (select count(*) = 2 from pg_proc p
      where p.oid in (to_regprocedure('private.require_approved_enrollment()'), to_regprocedure('private.stamp_grade_encoded_at()'))
        and not p.prosecdef and p.proconfig && array['search_path=""', 'search_path='''''] ) as fn_ok,
    (select count(*) = 2 from pg_proc p
      where p.oid in (to_regprocedure('private.require_approved_enrollment()'), to_regprocedure('private.stamp_grade_encoded_at()'))
        and p.proacl is not null
        and not exists (select 1 from aclexplode(p.proacl) ac where ac.grantee = 0)
        and not has_function_privilege('anon', p.oid, 'EXECUTE')
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')) as acl_ok,
    (select bool_or(has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
                    or has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES'))
       from pg_class c where c.oid in ('public.grades'::regclass, 'public.v_grades'::regclass)) as anon_any,
    (has_table_privilege('authenticated', 'public.grades', 'SELECT')
     and has_table_privilege('authenticated', 'public.v_grades', 'SELECT')) as auth_select,
    has_table_privilege('authenticated', 'public.grades', 'INSERT, UPDATE, DELETE, TRUNCATE') as auth_table_writes,
    (select string_agg(ac.privilege_type || '(' || a.attname::text || ')', ', ' order by ac.privilege_type, a.attname)
       from pg_attribute a cross join lateral aclexplode(a.attacl) ac
      where a.attrelid = 'public.grades'::regclass and a.attnum > 0 and not a.attisdropped and a.attacl is not null
        and ac.grantee = 'authenticated'::regrole) as cols) x), true);

-- ==========================================
-- TC-84: Student 1 reads only own grades (grades and v_grades)
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare a bigint; b bigint; c bigint; d bigint; e bigint; f bigint;
begin
  select count(*) into a from public.grades;
  select count(*) into b from public.grades g
    join public.enrollment_items ei on ei.enrollment_item_id = g.enrollment_item_id
    join public.enrollments en on en.enrollment_id = ei.enrollment_id
    where en.student_id = auth.uid();
  select count(*) into c from public.v_grades where student_id is distinct from auth.uid();
  select count(*) into d from public.v_grades where enrollment_item_id = current_setting('app.item_a3')::bigint;
  select count(*) into e from public.grades where enrollment_item_id = current_setting('app.item_o1')::bigint;
  select count(*) into f from public.v_grades where enrollment_item_id = current_setting('app.item_o1')::bigint;
  perform set_config('app.t84', format('visible %s, own %s, v_grades_not_own %s, own_test_grade_in_v_grades %s, other_student_grade_in_grades %s, in_v_grades %s',
    a, b, c, d, e, f), true);
  perform set_config('app.t84_ok', (a = b and c = 0 and d = 1 and e = 0 and f = 0)::text, true);
exception when others then
  perform set_config('app.t84', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
  perform set_config('app.t84_ok', 'false', true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r84', format('student1 [%s], other_student_grade_exists_for_postgres %s -> %s',
  current_setting('app.t84'),
  (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_o1')::bigint),
  case when current_setting('app.t84_ok') = 'true'
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_o1')::bigint) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-85: Student 1 cannot write grades
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't85_insert', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                         values (current_setting('app.item_a2')::bigint, '1.00', auth.uid())$q$),
    (2, 't85_update', $q$update public.grades set grade_code = '1.00', encoded_by = auth.uid()
                         where enrollment_item_id = current_setting('app.item_a3')::bigint$q$),
    (3, 't85_delete', $q$delete from public.grades
                         where enrollment_item_id = current_setting('app.item_a3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r85', format('insert [%s], update_own [%s], delete_own [%s], a2_grades %s, a3_grade %s -> %s',
  current_setting('app.t85_insert'), current_setting('app.t85_update'), current_setting('app.t85_delete'),
  (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint),
  (select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a3')::bigint),
  case when current_setting('app.t85_insert') like 'rls: %'
        and current_setting('app.t85_update') = 'rows 0'
        and current_setting('app.t85_delete') like 'denied: %'
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint) = 0
        and (select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a3')::bigint) = '1.50'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-86: the Registrar inserts and updates a grade (A1)
-- ==========================================
-- mark the audit log first (read again in TC-93)
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't86_insert', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                         values (current_setting('app.item_a1')::bigint, '1.75', auth.uid())$q$),
    (2, 't86_update', $q$update public.grades set grade_code = '2.00', encoded_by = auth.uid()
                         where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.gid_a1', coalesce((select grade_id::text from public.grades
  where enrollment_item_id = current_setting('app.item_a1')::bigint), ''), true);
select set_config('app.r86', format('insert [%s], update [%s], stored_grade %s, encoded_by_is_registrar %s -> %s',
  current_setting('app.t86_insert'), current_setting('app.t86_update'),
  coalesce((select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  coalesce((select (encoded_by = current_setting('app.reg')::uuid)::text from public.grades
             where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  case when current_setting('app.t86_insert') = 'rows 1' and current_setting('app.t86_update') = 'rows 1'
        and exists (select 1 from public.grades
                     where enrollment_item_id = current_setting('app.item_a1')::bigint
                       and grade_code = '2.00' and encoded_by = current_setting('app.reg')::uuid)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-87: the Registrar cannot set encoded_by to someone else
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't87_insert_other', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                               values (current_setting('app.item_a2')::bigint, '1.00', current_setting('app.s1')::uuid)$q$),
    (2, 't87_update_other', $q$update public.grades set encoded_by = current_setting('app.s1')::uuid
                               where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r87', format('insert_with_other_encoded_by [%s], update_to_other_encoded_by [%s] -> %s',
  current_setting('app.t87_insert_other'), current_setting('app.t87_update_other'),
  case when current_setting('app.t87_insert_other') like 'rls: %'
        and current_setting('app.t87_update_other') like 'rls: %'
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint) = 0
        and exists (select 1 from public.grades
                     where enrollment_item_id = current_setting('app.item_a1')::bigint
                       and encoded_by = current_setting('app.reg')::uuid)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-88: anon is denied everything
-- ==========================================
set local role anon;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't88_select_grades',   $q$select count(*) from public.grades$q$),
    (2, 't88_select_v_grades', $q$select count(*) from public.v_grades$q$),
    (3, 't88_insert',          $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                  values (current_setting('app.item_a2')::bigint, '1.00', current_setting('app.reg')::uuid)$q$),
    (4, 't88_update',          $q$update public.grades set grade_code = '1.00'
                                  where enrollment_item_id = current_setting('app.item_a1')::bigint$q$),
    (5, 't88_delete',          $q$delete from public.grades
                                  where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'NOT DENIED, rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'permission denied%' then 'denied: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r88', format('select_grades [%s], select_v_grades [%s], insert [%s], update [%s], delete [%s] -> %s',
  current_setting('app.t88_select_grades'), current_setting('app.t88_select_v_grades'),
  current_setting('app.t88_insert'), current_setting('app.t88_update'), current_setting('app.t88_delete'),
  case when current_setting('app.t88_select_grades') like 'denied: %'
        and current_setting('app.t88_select_v_grades') like 'denied: %'
        and current_setting('app.t88_insert') like 'denied: %'
        and current_setting('app.t88_update') like 'denied: %'
        and current_setting('app.t88_delete') like 'denied: %'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-89: no DELETE for anyone through the API
-- ==========================================
-- The Student's and anon's DELETE are in TC-85 and TC-88; here the Registrar's.
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  delete from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t89_reg_delete', 'NOT DENIED, rows ' || n, true);
exception when others then
  perform set_config('app.t89_reg_delete',
    case when sqlerrm like 'permission denied%' then 'denied: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r89', format('registrar_delete [%s], student_delete [%s], anon_delete [%s], delete_grant_authenticated %s, delete_grant_anon %s, grade_still_there %s -> %s',
  current_setting('app.t89_reg_delete'), current_setting('app.t85_delete'), current_setting('app.t88_delete'),
  has_table_privilege('authenticated', 'public.grades', 'DELETE'), has_table_privilege('anon', 'public.grades', 'DELETE'),
  (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint),
  case when current_setting('app.t89_reg_delete') like 'denied: %'
        and current_setting('app.t85_delete') like 'denied: %'
        and current_setting('app.t88_delete') like 'denied: %'
        and not has_table_privilege('authenticated', 'public.grades', 'DELETE')
        and not has_table_privilege('anon', 'public.grades', 'DELETE')
        and (select count(*) from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-90: a grade for a Pending enrollment is refused; accepted once Approved
-- ==========================================
-- step 1: the Registrar (insert for P1; moving A1's grade to P1)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't90_reg_insert_pending', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                     values (current_setting('app.item_p1')::bigint, '1.00', auth.uid())$q$),
    (2, 't90_reg_move_to_pending', $q$update public.grades set enrollment_item_id = current_setting('app.item_p1')::bigint
                                      where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- step 2: postgres (the rule applies to every role)
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't90_pg_insert_pending', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                    values (current_setting('app.item_p1')::bigint, '1.00', current_setting('app.reg')::uuid)$q$),
    (2, 't90_pg_move_to_pending', $q$update public.grades set enrollment_item_id = current_setting('app.item_p1')::bigint
                                     where enrollment_item_id = current_setting('app.item_a3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
select set_config('app.t90_p1_before', (select count(*)::text from public.grades
  where enrollment_item_id = current_setting('app.item_p1')::bigint), true);
-- step 3: postgres approves Student 2's enrollment; the Registrar tries again
update public.enrollments set status = 'Approved', reviewed_by = current_setting('app.reg')::uuid, reviewed_at = now()
where enrollment_id = current_setting('app.enr_p')::bigint;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  insert into public.grades (enrollment_item_id, grade_code, encoded_by)
  values (current_setting('app.item_p1')::bigint, '1.00', auth.uid());
  get diagnostics n = row_count;
  perform set_config('app.t90_reg_insert_approved', 'rows ' || n, true);
exception when others then
  perform set_config('app.t90_reg_insert_approved',
    case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         when sqlstate = '23503' then 'fk [23503]: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r90', format('registrar_insert_pending [%s], registrar_move_to_pending [%s], postgres_insert_pending [%s], postgres_move_to_pending [%s], p1_grades_while_pending %s, registrar_insert_after_approval [%s] -> %s',
  current_setting('app.t90_reg_insert_pending'), current_setting('app.t90_reg_move_to_pending'),
  current_setting('app.t90_pg_insert_pending'), current_setting('app.t90_pg_move_to_pending'),
  current_setting('app.t90_p1_before'), current_setting('app.t90_reg_insert_approved'),
  case when current_setting('app.t90_reg_insert_pending') like 'blocked [P0001]: not approved:%'
        and current_setting('app.t90_reg_move_to_pending') like 'denied: %'
        and current_setting('app.t90_pg_insert_pending') like 'blocked [P0001]: not approved:%'
        and current_setting('app.t90_pg_move_to_pending') like 'blocked [P0001]: not approved:%'
        and current_setting('app.t90_p1_before') = '0'
        and current_setting('app.t90_reg_insert_approved') = 'rows 1'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-91: an unknown grade_code is refused (foreign key to grade_scale)
-- ==========================================
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't91_insert_unknown', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by)
                                 values (current_setting('app.item_a2')::bigint, 'X.XX', auth.uid())$q$),
    (2, 't91_update_unknown', $q$update public.grades set grade_code = 'X.XX', encoded_by = auth.uid()
                                 where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r91', format('insert_unknown [%s], update_unknown [%s], a1_grade %s -> %s',
  current_setting('app.t91_insert_unknown'), current_setting('app.t91_update_unknown'),
  coalesce((select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  case when current_setting('app.t91_insert_unknown') like 'fk [23503]: %'
        and current_setting('app.t91_update_unknown') like 'fk [23503]: %'
        and (select grade_code from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint) = '2.00'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-92: encoded_at comes from the database
-- ==========================================
-- step 1: the Registrar cannot name encoded_at at all (column not granted)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 't92_reg_insert_encoded_at', $q$insert into public.grades (enrollment_item_id, grade_code, encoded_by, encoded_at)
                                        values (current_setting('app.item_a2')::bigint, '1.00', auth.uid(), '2000-01-01 00:00:00+00')$q$),
    (2, 't92_reg_update_encoded_at', $q$update public.grades set encoded_at = '2000-01-01 00:00:00+00'
                                        where enrollment_item_id = current_setting('app.item_a1')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.' || r.label,
        case when sqlerrm like 'not approved:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             when sqlstate = '23503' then 'fk [23503]: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- step 2: postgres sends an old encoded_at on INSERT (A2) and on UPDATE (A3); the
-- trigger overwrites it with now() (the transaction time)
insert into public.grades (enrollment_item_id, grade_code, encoded_by, encoded_at)
values (current_setting('app.item_a2')::bigint, '1.00', current_setting('app.reg')::uuid, '2000-01-01 00:00:00+00');
update public.grades set encoded_at = '2000-01-01 00:00:00+00'
where enrollment_item_id = current_setting('app.item_a3')::bigint;
select set_config('app.r92', format('registrar_insert_with_encoded_at [%s], registrar_update_encoded_at [%s], postgres_insert_stored_now %s, postgres_update_stored_now %s, registrar_write_stored_now %s -> %s',
  current_setting('app.t92_reg_insert_encoded_at'), current_setting('app.t92_reg_update_encoded_at'),
  coalesce((select (encoded_at = now())::text from public.grades where enrollment_item_id = current_setting('app.item_a2')::bigint), '-'),
  coalesce((select (encoded_at = now())::text from public.grades where enrollment_item_id = current_setting('app.item_a3')::bigint), '-'),
  coalesce((select (encoded_at = now())::text from public.grades where enrollment_item_id = current_setting('app.item_a1')::bigint), '-'),
  case when current_setting('app.t92_reg_insert_encoded_at') like 'denied: %'
        and current_setting('app.t92_reg_update_encoded_at') like 'denied: %'
        and (select count(*) from public.grades
              where enrollment_item_id in (current_setting('app.item_a1')::bigint, current_setting('app.item_a2')::bigint,
                                           current_setting('app.item_a3')::bigint)
                and encoded_at = now()) = 3
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- TC-93: the Registrar's insert and update of A1 (TC-86) are in the audit log
-- ==========================================
-- Only those two writes of A1 succeeded after the mark; every other attempt on A1 failed.
select set_config('app.r93', (select format('grade_id %s, audit_rows %s, actions %s, actor_is_registrar %s, insert_grade %s, update_old_new %s/%s, new_encoded_by_is_registrar %s -> %s',
    current_setting('app.gid_a1'), a.audit_rows, coalesce(a.actions, '-'), a.actor_is_reg,
    coalesce(a.insert_grade, '-'), coalesce(a.update_old, '-'), coalesce(a.update_new, '-'), a.new_by_reg,
    case when a.audit_rows = 2 and a.actions = 'INSERT,UPDATE' and a.actor_is_reg
          and a.insert_grade = '1.75' and a.update_old = '1.75' and a.update_new = '2.00' and a.new_by_reg
         then 'OK' else 'FAIL' end)
  from (select count(*) as audit_rows,
               string_agg(l.action::text, ',' order by l.log_id) as actions,
               coalesce(bool_and(l.actor_id = current_setting('app.reg')::uuid), false) as actor_is_reg,
               max(case when l.action = 'INSERT' then l.new_data ->> 'grade_code' end) as insert_grade,
               max(case when l.action = 'UPDATE' then l.old_data ->> 'grade_code' end) as update_old,
               max(case when l.action = 'UPDATE' then l.new_data ->> 'grade_code' end) as update_new,
               coalesce(bool_and(l.new_data ->> 'encoded_by' = current_setting('app.reg')), false) as new_by_reg
        from public.audit_logs l
        where l.log_id > current_setting('app.log_mark')::bigint
          and l.table_name = 'grades'
          and l.record_id = current_setting('app.gid_a1')) a), true);

-- ==========================================
-- Result: ONE row. Every cell must end in "-> OK"; all_ok must be true.
-- ==========================================
select (current_setting('app.r83') like '%-> OK' and current_setting('app.r84') like '%-> OK'
        and current_setting('app.r85') like '%-> OK' and current_setting('app.r86') like '%-> OK'
        and current_setting('app.r87') like '%-> OK' and current_setting('app.r88') like '%-> OK'
        and current_setting('app.r89') like '%-> OK' and current_setting('app.r90') like '%-> OK'
        and current_setting('app.r91') like '%-> OK' and current_setting('app.r92') like '%-> OK'
        and current_setting('app.r93') like '%-> OK') as all_ok,
  current_setting('app.r83') as tc83, current_setting('app.r84') as tc84, current_setting('app.r85') as tc85,
  current_setting('app.r86') as tc86, current_setting('app.r87') as tc87, current_setting('app.r88') as tc88,
  current_setting('app.r89') as tc89, current_setting('app.r90') as tc90, current_setting('app.r91') as tc91,
  current_setting('app.r92') as tc92, current_setting('app.r93') as tc93;

rollback;
