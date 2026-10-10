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

Same style as Part C. Run each block on its own, as a whole (never a selection: a partial run can commit). Each block ends with `rollback`, or stops at its expected error, which also leaves nothing committed. The expected results assume the seed data; if live rows differ (for example Ben's hold is already lifted), a count can be 0 instead of 1: check the row first.

Registrar approves a clearance with `approved_by` NULL (TC-18, fix 1):

```sql
begin;
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
| TC-18 | Registrar approves a clearance with `approved_by` NULL (Part F, after `hardening.sql`) | RLS error | | NOT RUN |
| TC-19 | Registrar approves a clearance as self and corrects a grade (Part F) | 1 row each | | NOT RUN |
| TC-20 | Cashier changes `charges.student_id` (Part F) | Error: column cannot be changed | | NOT RUN |
| TC-21 | Cashier marks a charge Cleared; `my_department_id()` is the Financial department (Part F) | 1 row; ids match | | NOT RUN |
| TC-22 | Department clears an item with `cleared_by` NULL (Part F) | RLS error | | NOT RUN |
| TC-23 | Department clears an item and lifts a hold as self, places a valid hold (Part F) | 1, 1, 1 | | NOT RUN |

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
