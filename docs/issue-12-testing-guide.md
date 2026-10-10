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
| TC-10 | Admin, open `/student/grades` and `/department` | Redirect to `/admin` | | |
| TC-11 | Deactivated user with a valid session opens their module | Signed out, sent to `/login` | | |
| TC-12 | Student 1 reads Student 2's grades (Part C) | 0 rows | | |
| TC-13 | Student 1 reads Student 2's charges and payments | 0 rows | | |
| TC-14 | Student 1 reads Student 2's clearances, holds, enrollments, document requests | 0 rows | | |
| TC-15 | Student 1 reads the 4 views (Part B and C) | Only Student 1's rows | | |
| TC-16 | Anonymous role reads `grades` and `v_grades` | 0 rows or denied | | |
| TC-17 | Student 1 updates own `role_id` | `UPDATE 0` | | |

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
