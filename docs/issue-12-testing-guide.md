# Issue 12 guide: test role-based routing and data isolation

Covers REQ-ADM-02, SEC-02, ETH-01. GitHub issue #19. Branch: `chore/role-routing-tests` (from `dev`). Result: the test cases in Step 6 filled in with real results.

Rules for everyone running this guide:
- Use only the seeded test accounts (`*@pnc.test`). Never paste a password, API key or `service_role` key into chat, a doc or a commit.
- Do not read or share `.env.local`.
- Everything in Part B and C runs inside a transaction that ends with `ROLLBACK`, so nothing in the database changes.

## What we already know (code review, not run live)

- Routing is checked twice: in `lib/supabase/proxy.ts` and with `requireRole` in every page. A wrong role is redirected to its own dashboard, a signed-out user to `/login`.
- The RLS policies in `docs/database/rls.sql` stop a student from reading another student's rows.
- Not proven: the 4 views (`v_grades`, `v_clearance_items`, `v_clearances`, `v_active_holds`) are in no SQL file. If they lack `security_invoker = true` they bypass RLS and show every student's rows. Also not proven: the live helper functions match `private_functions.sql`, and `rls.sql` has 41 of 49 policies.

## Step 0: Prepare

1. `git checkout dev && git pull`, then `git checkout -b chore/role-routing-tests` (already done if you are reading this on that branch).
2. Run `npm run dev` and open http://localhost:3000.
3. Get the password for each test account from the PM (never in chat). Accounts, from `docs/database/seed.sql` section 7:

| Role | Email |
|---|---|
| Admin | admin@pnc.test |
| Registrar | registrar@pnc.test |
| Cashier | cashier@pnc.test |
| Department | dept@pnc.test |
| Student 1 (Ana Reyes) | student1@pnc.test |
| Student 2 (Ben Santos) | student2@pnc.test |
| Student 3 (Carla Mendoza) | student3@pnc.test |

The seed links each profile to the matching `auth.users` row by email, so the SQL below looks the IDs up by email. If the live accounts use other emails, adjust them.

## Part A: Routing tests (browser, about 20 minutes)

Use a private window per role, or sign out between roles. For each role: sign in, then type each URL in the address bar (do not click links).

| Signed in as | Type these URLs | Expected |
|---|---|---|
| nobody | `/student/grades`, `/admin/users`, `/registrar` | Redirect to `/login` |
| Student | `/registrar`, `/registrar/grades`, `/cashier/charges`, `/department/holds`, `/admin`, `/admin/audit-log` | Redirect to `/student` |
| Registrar | `/student`, `/cashier/payments`, `/department`, `/admin/users` | Redirect to `/registrar` |
| Cashier | `/student`, `/registrar/enrollments`, `/department/holds`, `/admin` | Redirect to `/cashier` |
| Department | `/student`, `/registrar/clearance`, `/cashier/clearance`, `/admin` | Redirect to `/department` |
| Admin | `/student/grades`, `/registrar`, `/cashier`, `/department` | Redirect to `/admin` |

Also test: an account with `is_active = false` and a valid session should be signed out and sent to `/login` (TC-11; do this only on a test account and restore it afterwards, or skip and mark "not run").

Record each result in the Step 6 table: Pass if the redirect matches, Fail with what you saw otherwise. A Fail here is a security bug: stop and tell the PM.

## Part B: Check the views (Supabase SQL editor, about 5 minutes)

1. Open the Supabase project, SQL editor.
2. Run:

```sql
select c.relname, c.reloptions
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname like 'v\_%';
```

3. Expected: each of the 4 views shows `{security_invoker=true}`. A view with `null` runs as its owner and ignores RLS.
4. Save the view definitions (this also closes a known gap in the repo):

```sql
select viewname, definition from pg_views where schemaname = 'public' and viewname like 'v\_%';
```

5. If any view is not `security_invoker=true`, record TC-15 and TC-16 as Fail and go to Part E.

## Part C: Data isolation as a student (Supabase SQL editor, about 15 minutes)

This acts as a student without a password by setting the same claims the API would use. Run each block on its own, as a whole. The first lines save the two student IDs (looked up by email) before switching to the restricted role.

Student 1 trying to read Student 2's data (TC-12, TC-13, TC-14):

```sql
begin;
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('app.s2', (select id::text from auth.users where email = 'student2@pnc.test'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);

select 'own profile' as test, count(*) from public.profiles where profile_id = auth.uid();
select 'other student grades' as test, count(*) from public.grades g
  join public.enrollment_items ei on ei.enrollment_item_id = g.enrollment_item_id
  join public.enrollments e on e.enrollment_id = ei.enrollment_id
  where e.student_id = current_setting('app.s2')::uuid;
select 'other student charges' as test, count(*) from public.charges
  where student_id = current_setting('app.s2')::uuid;
select 'other student clearances' as test, count(*) from public.clearances
  where student_id = current_setting('app.s2')::uuid;
select 'other student holds' as test, count(*) from public.academic_holds
  where student_id = current_setting('app.s2')::uuid;
rollback;
```

Expected: "own profile" is 1; every "other student" count is 0. Then run `select count(*)` on each table with no `where` and check the count equals only Student 1's own rows.

If a table or column name errors, check the real names in `docs/database/schema.sql` and adjust.

Views as Student 1 (TC-15):

```sql
begin;
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
select count(*) as rows, count(distinct student_id) as students from public.v_grades;
select count(*) as rows, count(distinct student_id) as students from public.v_clearance_items;
rollback;
```

Expected: `students` is 1 (or 0) for each view. 2 or more means the view leaks.

Anonymous access (TC-16):

```sql
begin;
set local role anon;
select count(*) from public.grades;
select count(*) from public.v_grades;
rollback;
```

Expected: 0 rows or a "permission denied" error. Any number above 0 is a Fail.

A student must not change their own role (TC-17):

```sql
begin;
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
update public.profiles set role_id = (select role_id from public.roles where role_name = 'Admin')
  where profile_id = auth.uid();
rollback;
```

Expected: `UPDATE 0`. If it says `UPDATE 1`, a student can make themselves Admin: critical, stop and tell the PM.

Repeat the first block with the roles of the two students swapped (Student 2 reading Student 1) to test the other direction.

## Part F: Hardening tests (issue #50, after running `docs/database/hardening.sql`)

Important: the live `authenticated` role has no INSERT or UPDATE permission on most tables (see the grants finding below), so without help every write fails with "permission denied" before RLS or the triggers run. Each block therefore starts with a temporary `grant` that the closing `rollback` undoes, so nothing is changed in the database. If a block ends in an error instead of `rollback`, run `rollback;` as its own query afterwards (a GRANT is also undone by that). For TC-18, TC-20 and TC-22 the expected error is the RLS or trigger error, not "permission denied".

Same style as Part C. Run each block on its own, as a whole (never a selection: a partial run can commit). Each block ends with `rollback`, or stops at its expected error, which also leaves nothing committed. The expected results assume the seed data; if live rows differ (for example Ben's hold is already lifted), a count can be 0 instead of 1: check the row first.

Registrar approves a clearance with `approved_by` NULL (TC-18, fix 1):

```sql
begin;
grant insert, update on all tables in schema public to authenticated; -- temporary, undone by the rollback
select set_config('app.reg', (select id::text from auth.users where email = 'registrar@pnc.test'), true);
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
update public.clearances set approved_at = now(), approved_by = null
  where student_id = current_setting('app.s1')::uuid;
rollback;
```

Expected: `ERROR: new row violates row-level security policy for table "clearances"`. (Before hardening: `UPDATE 1`.)

Registrar normal updates still work (TC-19, fixes 1 and 2):

```sql
begin;
grant insert, update on all tables in schema public to authenticated; -- temporary, undone by the rollback
select set_config('app.reg', (select id::text from auth.users where email = 'registrar@pnc.test'), true);
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
with u as (
  update public.clearances set approved_at = now(), approved_by = auth.uid()
  where student_id = current_setting('app.s1')::uuid returning 1)
select 'approve clearance' as test, count(*) as rows_changed from u;
with u as (
  update public.grades set grade_code = '1.25', encoded_by = auth.uid(), encoded_at = now()
  where grade_id = (select min(grade_id) from public.grades) returning 1)
select 'correct a grade' as test, count(*) as rows_changed from u;
rollback;
```

Expected: both `rows_changed` are 1.

Cashier changes `charges.student_id` (TC-20, fix 2):

```sql
begin;
grant insert, update on all tables in schema public to authenticated; -- temporary, undone by the rollback
select set_config('app.cash', (select id::text from auth.users where email = 'cashier@pnc.test'), true);
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('app.s2', (select id::text from auth.users where email = 'student2@pnc.test'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
update public.charges set student_id = current_setting('app.s1')::uuid
  where student_id = current_setting('app.s2')::uuid;
rollback;
```

Expected: `ERROR: column charges.student_id cannot be changed`. (Before hardening: `UPDATE 1`.)

Cashier normal update and department lookup (TC-21, fixes 2 and 4). The first select runs as `postgres` with the Cashier's claims, so it does not depend on grants on schema `private`:

```sql
begin;
grant insert, update on all tables in schema public to authenticated; -- temporary, undone by the rollback
select set_config('app.cash', (select id::text from auth.users where email = 'cashier@pnc.test'), true);
select set_config('app.s2', (select id::text from auth.users where email = 'student2@pnc.test'), true);
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
select 'cashier department' as test, private.my_department_id() as dept_id,
  (select min(department_id) from public.departments where department_type = 'Financial') as expected;
set local role authenticated;
with u as (
  update public.charges set status = 'Cleared'
  where student_id = current_setting('app.s2')::uuid returning 1)
select 'cashier marks charge cleared' as test, count(*) as rows_changed from u;
rollback;
```

Expected: `dept_id` equals `expected`; `rows_changed` is 1.

Department clears an item with `cleared_by` NULL (TC-22, fixes 1, 3 and 4):

```sql
begin;
grant insert, update on all tables in schema public to authenticated; -- temporary, undone by the rollback
select set_config('app.dept', (select id::text from auth.users where email = 'dept@pnc.test'), true);
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
select 'dept department' as test, private.my_department_id() as dept_id,
  (select department_id from public.departments where code = 'CCS') as expected;
set local role authenticated;
update public.clearance_items set cleared_at = now(), cleared_by = null
  where department_id = private.my_department_id()
    and clearance_id in (select clearance_id from public.clearances where student_id = current_setting('app.s1')::uuid);
rollback;
```

Expected: `dept_id` equals `expected`, then `ERROR: new row violates row-level security policy for table "clearance_items"`. (Before hardening: `UPDATE 1`.) If the update fails with "permission denied for schema private", replace `private.my_department_id()` in the `where` with `(select department_id from public.departments where code = 'CCS')` and run again.

Department valid updates still work (TC-23, fixes 1 and 2):

```sql
begin;
grant insert, update on all tables in schema public to authenticated; -- temporary, undone by the rollback
select set_config('app.dept', (select id::text from auth.users where email = 'dept@pnc.test'), true);
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
select set_config('app.s2', (select id::text from auth.users where email = 'student2@pnc.test'), true);
select set_config('app.ccs', (select department_id::text from public.departments where code = 'CCS'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
with u as (
  update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
  where department_id = current_setting('app.ccs')::bigint
    and clearance_id in (select clearance_id from public.clearances where student_id = current_setting('app.s1')::uuid)
  returning 1)
select 'clear item as self' as test, count(*) as rows_changed from u;
with u as (
  update public.academic_holds set lifted_at = now(), lifted_by = auth.uid()
  where student_id = current_setting('app.s2')::uuid and lifted_at is null returning 1)
select 'lift hold as self' as test, count(*) as rows_changed from u;
with u as (
  insert into public.academic_holds (student_id, department_id, reason, placed_by)
  values (current_setting('app.s1')::uuid, current_setting('app.ccs')::bigint, 'Hardening test', auth.uid())
  returning 1)
select 'place hold as self' as test, count(*) as rows_changed from u;
rollback;
```

Expected: the three `rows_changed` are 1.

After Part F, run Part C again: TC-12 to TC-17 must still pass.

## Part G: tests for hardening2.sql (issue #50)

Run after `docs/database/hardening2.sql`: TC-26 needs section A, TC-24 and TC-25 need section B, TC-27 and TC-28 need section C. Same rules as Part F: run each block on its own, as a whole (never a selection); each block ends with `rollback`, so nothing is changed; if a block stops at an unexpected error, run `rollback;` as its own query. The temporary `grant` lines are needed for the same reason as in Part F and are undone by the rollback.

The Supabase SQL editor shows only the last result, so each block ends with ONE result row that holds everything. Where an error is the expected result, the block catches it in a `do` block and shows the error text (`sqlerrm`) in that row instead of stopping.

After Part G, run Part C and Part F again (TC-12 to TC-23 must still pass; TC-16 may now show "permission denied" instead of 0 rows, which is an accepted result). Part F now also writes audit rows, which its `rollback` removes.

Registrar grade correction is written to the audit log (TC-24, section B). The audit row is read back as `postgres` inside the same transaction:

```sql
begin;
grant update on public.grades to authenticated; -- temporary, undone by the rollback
select set_config('app.reg', (select id::text from auth.users where email = 'registrar@pnc.test'), true);
select set_config('app.gid', (select min(grade_id)::text from public.grades), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
update public.grades set grade_code = '1.25', encoded_by = auth.uid(), encoded_at = now()
  where grade_id = current_setting('app.gid')::bigint;
reset role; -- back to postgres to read audit_logs
select count(*) as audit_rows,
  bool_and(a.actor_id = current_setting('app.reg')::uuid) as actor_is_registrar,
  max(a.old_data ->> 'grade_code') as old_grade,
  max(a.new_data ->> 'grade_code') as new_grade
from public.audit_logs a
where a.table_name = 'grades' and a.action = 'UPDATE'
  and a.record_id = current_setting('app.gid') and a.created_at = now();
rollback;
```

Expected: `audit_rows` 1, `actor_is_registrar` true, `new_grade` 1.25 (`old_grade` is the grade before). `audit_rows` 0 means the trigger is missing.

`audit_logs` cannot be changed, deleted or truncated, even as `postgres` (TC-25, section B). The block adds its own test row first (as `postgres`, undone by the rollback). The `truncate` is inside the same rolled-back transaction, so even if it were not blocked nothing would be lost; it briefly locks `audit_logs`, so run it at a quiet time:

```sql
begin;
insert into public.audit_logs (action, table_name, record_id) values ('INSERT', 'tc25_test', 'tc25'); -- undone by the rollback
do $$
begin
  begin
    update public.audit_logs set table_name = 'changed' where record_id = 'tc25';
    perform set_config('app.r_update', 'NOT BLOCKED', true);
  exception when others then
    perform set_config('app.r_update', 'blocked: ' || sqlerrm, true);
  end;
  begin
    delete from public.audit_logs where record_id = 'tc25';
    perform set_config('app.r_delete', 'NOT BLOCKED', true);
  exception when others then
    perform set_config('app.r_delete', 'blocked: ' || sqlerrm, true);
  end;
  begin
    truncate public.audit_logs;
    perform set_config('app.r_truncate', 'NOT BLOCKED', true);
  exception when others then
    perform set_config('app.r_truncate', 'blocked: ' || sqlerrm, true);
  end;
end $$;
select current_user as ran_as,
  current_setting('app.r_update') as update_result,
  current_setting('app.r_delete') as delete_result,
  current_setting('app.r_truncate') as truncate_result,
  (select count(*) from public.audit_logs where record_id = 'tc25') as test_row_still_there;
rollback;
```

Expected: `ran_as` postgres; the three results are `blocked: audit_logs is append-only: UPDATE is not allowed` (DELETE, TRUNCATE for the others); `test_row_still_there` 1. Any `NOT BLOCKED` is a Fail.

Department places a hold for a student of its own department and for a student of another department (TC-26, section A). The students are picked by query: "own" is a student whose program belongs to the department of `dept@pnc.test`, "other" a student whose program belongs to another department (with the seed: Ana Reyes, BSCS/CCS, and Carla Mendoza, BSBA/CBA). If the data has no such student, that column says SKIPPED with the reason:

```sql
begin;
grant insert on public.academic_holds to authenticated; -- temporary, undone by the rollback
select set_config('app.dept', (select id::text from auth.users where email = 'dept@pnc.test'), true);
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
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
begin
  if current_setting('app.mydept') = '' then
    perform set_config('app.r_own', 'SKIPPED: dept@pnc.test has no department', true);
    perform set_config('app.r_other', 'SKIPPED: dept@pnc.test has no department', true);
    return;
  end if;
  if current_setting('app.own') = '' then
    perform set_config('app.r_own', 'SKIPPED: no student in a program of this department', true);
  else
    begin
      insert into public.academic_holds (student_id, department_id, reason, placed_by)
      values (current_setting('app.own')::uuid, current_setting('app.mydept')::bigint, 'Hardening2 test', auth.uid());
      perform set_config('app.r_own', 'inserted', true);
    exception when others then
      perform set_config('app.r_own', 'ERROR: ' || sqlerrm, true);
    end;
  end if;
  if current_setting('app.other') = '' then
    perform set_config('app.r_other', 'SKIPPED: every student is in a program of this department; add a student in another department''s program to test this', true);
  else
    begin
      insert into public.academic_holds (student_id, department_id, reason, placed_by)
      values (current_setting('app.other')::uuid, current_setting('app.mydept')::bigint, 'Hardening2 test', auth.uid());
      perform set_config('app.r_other', 'inserted', true);
    exception when others then
      perform set_config('app.r_other', 'ERROR: ' || sqlerrm, true);
    end;
  end if;
end $$;
select current_setting('app.r_own') as own_department_student,
  current_setting('app.r_other') as other_department_student;
rollback;
```

Expected: `own_department_student` = `inserted`; `other_department_student` = `ERROR: new row violates row-level security policy for table "academic_holds"`. (Before section A the second one is also `inserted`.) A SKIPPED column is "not run" for that half, not a Pass.

Grants after section C (TC-27). Read-only, no transaction needed:

```sql
select
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
   and has_function_privilege('authenticated', 'private.audit_logs_readonly()', 'EXECUTE')) as auth_exec_all_4;
```

Expected: `any_truncate_refs_trigger` false, `anon_select_any` false, `anon_profiles_insert` false, `auth_profiles_update` true, `auth_select_all` true, `auth_audit_insert` false, the four `anon_exec_*` false, `auth_exec_all_4` true.

Regression: anonymous read and student isolation (TC-28, section C; repeats TC-16 and TC-12):

```sql
begin;
select set_config('app.s1', (select id::text from auth.users where email = 'student1@pnc.test'), true);
set local role anon;
do $$
begin
  begin
    perform set_config('app.r_grades', 'rows: ' || (select count(*) from public.grades), true);
  exception when others then
    perform set_config('app.r_grades', 'denied: ' || sqlerrm, true);
  end;
  begin
    perform set_config('app.r_v_grades', 'rows: ' || (select count(*) from public.v_grades), true);
  exception when others then
    perform set_config('app.r_v_grades', 'denied: ' || sqlerrm, true);
  end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
select current_setting('app.r_grades') as anon_grades,
  current_setting('app.r_v_grades') as anon_v_grades,
  (select count(*) from public.grades) as student1_visible_grades,
  (select count(*) from public.grades g
     join public.enrollment_items ei on ei.enrollment_item_id = g.enrollment_item_id
     join public.enrollments e on e.enrollment_id = ei.enrollment_id
     where e.student_id = auth.uid()) as student1_own_grades;
rollback;
```

Expected: `anon_grades` and `anon_v_grades` are `denied: permission denied for ...` (after section C) or `rows: 0` (both accepted; any other number is a Fail); `student1_visible_grades` = `student1_own_grades` (3 with the seed).

## Part D (optional, later): test through the real Supabase client

When the student pages use real data instead of mock data, repeat Part C by signing in as Student 1 and loading `/student/grades` while logged in. The page must show only Student 1's rows. Until then Part C is the real evidence.

## Step 6: Record the results

Fill in this table (copy into `docs/testing-plan.md` for Sprint 4). Actual = what really happened, with the date and who ran it.

| ID | Steps | Expected | Actual | Result |
|---|---|---|---|---|
| TC-01 | Signed out, open `/student/grades` | Redirect to `/login` | curl: 307 to /login (2026-10-10, Claude, localhost dev server) | Pass |
| TC-02 | Signed out, open `/admin/users` | Redirect to `/login` | curl: 307 to /login (2026-10-10, Claude, localhost dev server) | Pass |
| TC-03 | Student, open `/registrar/grades` | Redirect to `/student` | Redirect, ends at /student (2026-10-10, Claude, localhost dev server, signed in as student1) | Pass |
| TC-04 | Student, open `/cashier/charges` | Redirect to `/student` | Redirect (2026-10-10, Claude, localhost dev server, student1) | Pass |
| TC-05 | Student, open `/department/holds` | Redirect to `/student` | Redirect (2026-10-10, Claude, localhost dev server, student1) | Pass |
| TC-06 | Student, open `/admin` and `/admin/audit-log` | Redirect to `/student` | Both redirect, end at /student (2026-10-10, Claude, localhost dev server, student1) | Pass |
| TC-07 | Cashier, open `/registrar/enrollments` and `/student` | Redirect to `/cashier` | `/student`, `/registrar/enrollments`, `/department/holds`, `/admin` all end at /cashier (2026-10-10, Claude, localhost, signed in as the Cashier account) | Pass |
| TC-08 | Registrar, open `/admin/users` and `/cashier/payments` | Redirect to `/registrar` | `/admin/users`, `/cashier/payments`, `/student`, `/department` all end at /registrar (2026-10-10, Claude, localhost, signed in as the Registrar account) | Pass |
| TC-09 | Department, open `/cashier/clearance` and `/registrar/clearance` | Redirect to `/department` | `/cashier/clearance`, `/registrar/clearance`, `/student`, `/admin` all end at /department (2026-10-10, Claude, localhost, signed in as the Department account) | Pass |
| TC-10 | Admin, open `/student/grades` and `/department` | Redirect to `/admin` | `/student/grades`, `/registrar`, `/cashier`, `/department` all end at /admin (2026-10-10, Claude, localhost, signed in as the Admin account) | Pass |
| TC-11 | Deactivated user with a valid session opens their module | Signed out, sent to `/login` | student3 set to is_active=false, reload signed the user out and went to /login; after restoring is_active=true the user could sign in again (2026-10-10, run by the PM, reported in chat) | Pass |
| TC-12 | Student 1 reads Student 2's grades (Part C) | 0 rows | 0 rows (2026-10-10, run by the PM in the Supabase SQL editor as student1 via request.jwt.claims) | Pass |
| TC-13 | Student 1 reads Student 2's charges and payments | 0 rows | charges: 0 rows, payments: 0 rows; student1 sees only their own 1 payment (2026-10-10, PM, Supabase SQL editor as student1 via request.jwt.claims) | Pass |
| TC-14 | Student 1 reads Student 2's clearances, holds, enrollments, document requests | 0 rows | clearances 0, holds 0, enrollments 0, document_requests 0; student1 sees only their own 1 enrollment and 1 document request (2026-10-10, PM, Supabase SQL editor as student1 via request.jwt.claims) | Pass |
| TC-15 | Student 1 reads the 4 views (Part B and C) | Only Student 1's rows | All 4 views (v_active_holds, v_clearance_items, v_clearances, v_grades) have reloptions security_invoker=true, so RLS applies. Row test as student1: v_grades 3 = grades table 3, v_clearance_items 4 = clearance_items table 4, no extra rows (2026-10-10, PM, Supabase SQL editor) | Pass |
| TC-16 | Anonymous role reads `grades` and `v_grades` | 0 rows or denied | set local role anon: grades 0 rows, v_grades 0 rows (2026-10-10, PM, Supabase SQL editor) | Pass |
| TC-17 | Student 1 updates own `role_id` | `UPDATE 0` | UPDATE inside a CTE as student1 (set role_id to Admin): rows_changed = 0 (2026-10-10, PM, Supabase SQL editor) | Pass |
| TC-18 | Registrar approves a clearance with `approved_by` NULL (Part F, after `hardening.sql`) | RLS error | ERROR 42501: new row violates row-level security policy for table "clearances" (before the temporary grant it failed earlier with permission denied) (2026-10-10, PM clicked Run in the Supabase SQL editor, Claude loaded and read the result; temporary grant inside a rolled-back transaction) | Pass |
| TC-19 | Registrar approves a clearance as self and corrects a grade (Part F) | 1 row each | approve_clearance = 1, correct_grade = 1 (2026-10-10, PM clicked Run in the Supabase SQL editor, Claude loaded and read the result; temporary grant inside a rolled-back transaction) | Pass |
| TC-20 | Cashier changes `charges.student_id` (Part F) | Error: column cannot be changed | ERROR 42501: column charges.student_id cannot be changed, raised by private.guard_immutable_columns (2026-10-10, PM clicked Run in the Supabase SQL editor, Claude loaded and read the result; temporary grant inside a rolled-back transaction) | Pass |
| TC-21 | Cashier marks a charge Cleared; `my_department_id()` is the Financial department (Part F) | 1 row; ids match | dept_id = 1, expected = 1, rows_changed = 1 (2026-10-10, PM clicked Run in the Supabase SQL editor, Claude loaded and read the result; temporary grant inside a rolled-back transaction) | Pass |
| TC-22 | Department clears an item with `cleared_by` NULL (Part F) | RLS error | dept_id = 2 = expected 2; blocked: new row violates row-level security policy for table "clearance_items" (2026-10-10, PM clicked Run in the Supabase SQL editor, Claude loaded and read the result; temporary grant inside a rolled-back transaction) | Pass |
| TC-23 | Department clears an item and lifts a hold as self, places a valid hold (Part F) | 1, 1, 1 | clear_item_as_self = 1, lift_hold_as_self = 1, place_hold_as_self = 1 (2026-10-10, PM clicked Run in the Supabase SQL editor, Claude loaded and read the result; temporary grant inside a rolled-back transaction) | Pass |
| TC-24 | Registrar grade correction is written to the audit log (Part G, section B) | 1 audit row, actor = registrar, new grade 1.25 | audit_rows = 1, actor_is_registrar = true, old_grade = 1.75, new_grade = 1.25 (2026-10-10, PM ran section B and clicked Run, Claude loaded and read the test; rolled back) | Pass |
| TC-25 | audit_logs cannot be updated, deleted or truncated, even as postgres (Part G, section B) | all three blocked | ran_as = postgres; update, delete and truncate each blocked: audit_logs is append-only; test_row_still_there = 1 (2026-10-10, PM ran section B and clicked Run, Claude loaded and read the test; rolled back) | Pass |
| TC-26 | Department places a hold for an own-department student and for another department's student (Part G, section A) | `inserted`; RLS error | own_department_student = inserted; other_department_student = ERROR: new row violates row-level security policy for table "academic_holds" (2026-10-10, PM ran section A and clicked Run, Claude loaded and read the test; temporary grant in a rolled-back transaction) | Pass |
| TC-27 | Grants after section C (Part G) | no TRUNCATE/REFERENCES/TRIGGER/MAINTAIN, anon cannot read or write, authenticated still reads and updates profiles | any_truncate_refs_trigger false, any_maintain false, anon_select_any false, anon_profiles_insert false, auth_profiles_update true, auth_select_all true, auth_audit_insert false, all four anon_exec_* false, auth_exec_all_4 true (2026-10-10, PM ran section C and clicked Run, Claude loaded and read the check) | Pass |
| TC-28 | Regression: anonymous read of `grades` / `v_grades`; Student 1 sees only own grades (Part G) | Denied or 0 rows; visible = own | Not run yet | NOT RUN |

## Step 7: Fix what failed (before closing the issue)

- A routing Fail: stop, tell the PM, fix with `backend-db` (opus, security work), re-test.
- A view without `security_invoker`: the fix is `alter view public.<name> set (security_invoker = true);` plus revoking anon access, in a new SQL file. This is security work: use `backend-db` (opus) and have the PM review it.
- Save the 4 view definitions and the 8 missing policies from Part B into `docs/database/` so the repo matches the live database.

## Step 8: Finish

1. `npx tsc --noEmit`, `npx eslint .`, `npm run build` (only code changes need these, but run them before the PR).
2. Commit the filled-in guide or test table on `chore/role-routing-tests`.
3. Ask the PM for a yes, then push and open a PR into `dev` (never `main`).
4. In the PR: say which test cases were run live and which were not.
5. Tick the issue's checkboxes only for what actually passed.

## Done when

- [ ] All routing cases TC-01 to TC-10 have a real result
- [ ] TC-12 to TC-17 have a real result from the live database
- [ ] Any Fail has a fix or an open issue
- [ ] The test table is in the repo for Sprint 4

## Findings from the live checks (2026-10-10)

- All 4 views have `security_invoker=true`. The RLS-bypass risk from the code review does not apply.
- The live views have far fewer columns than `types/database.types.ts` and `lib/mock-data.ts` assume, so the generated types are out of date or the views were never finished:
  - `v_grades` (live): grade_id, enrollment_item_id, grade_code, numeric_value, is_passing, encoded_by, encoded_at. Missing: student_id, term_id, enrollment_id, section_id, subject_id, subject_code, subject_title, units.
  - `v_clearance_items` (live): clearance_item_id, clearance_id, department_id, cleared_by, cleared_at, remarks, status. Missing: student_id, term_id, department_name, department_type.
  - `v_clearances` (live): clearance_id, student_id, term_id, created_at, approved_by, approved_at, status. Missing: total_items, cleared_items.
  - `v_active_holds` matches.
  - Effect: the student Grades and Clearance pages cannot read these views as written once they use real data. Decision needed (separate issue): extend the views, or change the app to join the base tables. Types are not regenerated in this PR for that reason.
- The definitions of the 4 views, the 6 `private` helper functions and all 49 live policies were exported on 2026-10-10 and saved in `docs/database/` (`views.sql`, `private_functions.sql`, `rls.sql`). The repo's old `rls.sql` had only 41 policies; the live database has 49 (the 8 missing ones are all INSERT policies).
- Not exported yet: table triggers (for example the trigger that calls `private.create_clearance_items`) and grants.
- TC-16 (anonymous) and TC-17 (a student cannot change their own role) pass.


## Policy observations from the live export (not fixed here, for the backend owner)

Read from the exported policies; none of these was exploited or tested live.
Issue #50: `docs/database/hardening.sql` addresses 1 to 4 and adds read-only diagnostic queries for 6 (not run yet; tests TC-18 to TC-23 in Part F).

1. The "who did it" checks accept NULL: `clearance_items_dept_update` (`cleared_by IS NULL`), `holds_dept_lift` (`lifted_by IS NULL`) and `clearances_registrar_approve` (`approved_by IS NULL`) let a change be saved without recording who made it.
2. UPDATE policies check the role only, not which columns change: Cashier on `charges` (student_id, amount); Registrar on `enrollments`, `grades`, `document_requests`, `clearances`; Department and Cashier on `clearance_items` and Department on `academic_holds`. There are no audit triggers yet (REQ-ADM-03).
3. `clearance_items_dept_update` checks the role in USING but not in WITH CHECK (the department test still covers it in practice).
4. `private.my_department_id()`: for a Cashier it uses `LIMIT 1` with no ORDER BY on Financial departments, and for Department staff a scalar subquery that errors if a profile has two `department_staff` rows.
5. `holds_dept_place` does not check that the student belongs to the Department user's department. Not fixed in `hardening.sql`: the only available check (`private.student_in_my_department`) means "the student has requested any clearance", which protects little and would block holds placed before a clearance request. It needs a real student-to-department link first (open in #50).
6. Grants on the 6 `SECURITY DEFINER` functions and on the `private` schema were not exported; check that `private` is not exposed through the API.

## Grants found in the live database (2026-10-10, PM, Supabase SQL editor)

Query: `information_schema.role_table_grants` for `anon` and `authenticated`, schema public.

- `authenticated` can only SELECT on every table, except `profiles` (also INSERT, UPDATE, DELETE). So the INSERT and UPDATE policies on all other tables cannot take effect through the API until grants are added. This fails safe; the app will need targeted grants when it starts writing.
- `authenticated` also has TRUNCATE, REFERENCES and TRIGGER on every table. TRUNCATE is not covered by RLS. PostgREST does not expose TRUNCATE, so it is not reachable through the API today, but nobody needs it. To review: `REVOKE TRUNCATE, REFERENCES, TRIGGER ... FROM authenticated`.
- `anon` can SELECT every table and has DELETE, INSERT and UPDATE on `profiles`. RLS blocks it (the `profiles` policies are `TO authenticated`), so RLS is the only protection there. To review: revoke everything from `anon` that the login page does not need.
- No GRANT or REVOKE statements exist in the repo; the live grants come from Supabase defaults plus changes that were never written down.
- Found by TC-18: `permission denied for table clearances` (error 42501) before RLS ran.


## Regression after hardening.sql (2026-10-10)

After `hardening.sql` was run on the live database, TC-12 to TC-17 were run again (PM clicked Run in the Supabase SQL editor, Claude read the results):

- TC-12 to TC-14: own profile 1; every `student2` count (grades, charges, payments, clearances, holds, enrollments, document_requests) is 0. Pass.
- TC-15: `v_grades` 3 = `grades` 3; `v_clearance_items` 4 = `clearance_items` 4. Pass.
- TC-16: anonymous role reads 0 `grades` rows and 0 `v_grades` rows. Pass.
- TC-17: a student updating their own `role_id` to Admin changes 0 rows. Pass.

## Grants on schema private and Data API exposure (2026-10-10)

Read-only checks, run in the Supabase SQL editor and the dashboard (Integrations, Data API, Settings):

- Schema `private`: `anon` has no USAGE; `authenticated` has USAGE (the RLS policies need it).
- The 5 helper functions (`active_uid`, `current_role_name`, `my_department_id`, `clearance_in_my_department`, `student_in_my_department`): `anon` cannot EXECUTE them, `authenticated` can.
- `private.create_clearance_items()` and `private.guard_immutable_columns()` are trigger functions and `anon` can EXECUTE them (default PUBLIC execute). They cannot be called directly, only as triggers, so this is hygiene, not an exploit. To review: `REVOKE EXECUTE ... FROM PUBLIC`.
- Data API exposed schemas: `graphql_public` and `public`. `private` is NOT exposed, so the `private` functions cannot be reached through the API.
- Data API exposed tables: "1 of 27 tables exposed". This matches the grants export: only `profiles` allows writes for `authenticated`. When the app starts writing data, the needed tables must be exposed and given targeted GRANTs on purpose.
- Table triggers found: one app trigger, `trg_clearances_create_items` on `clearances` (calls `private.create_clearance_items()`), plus Supabase's own `realtime` and `storage` triggers. No audit triggers (REQ-ADM-03) exist yet.
