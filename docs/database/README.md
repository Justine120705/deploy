# Database SQL (Supabase / PostgreSQL)

SQL scripts needed to recreate the Centralized Student Portal database and to
review its Row Level Security (RLS) policies locally. Owned by the **Backend
team** (see Project Charter, section 5: "ERD and 3NF Tables").

| File                   | Contents                                                                 |
| ---------------------- | ------------------------------------------------------------------------ |
| `schema.sql`           | 23 tables (3NF) in dependency order, plus `document_ticket_seq`          |
| `views.sql`            | The 4 views (`security_invoker = true`), exported from live              |
| `seed.sql`             | Fictional test data: 7 accounts' profiles, 3 students, one full term     |
| `private_functions.sql`| The 6 functions in schema `private`, exported from live                  |
| `rls.sql`              | `ENABLE ROW LEVEL SECURITY` on all 23 tables and all 49 live policies    |
| `hardening.sql`        | Issue #50 fixes: 3 policies, `my_department_id()`, immutable-column triggers; rollback and grant/trigger diagnostics as comments |
| `hardening2.sql`       | Issue #50, part 2, three sections run separately: A `holds_dept_place` checks the student's program department; B audit-log triggers (REQ-ADM-03) and append-only `audit_logs`; C grants cleanup. A rollback block per section |
| `triggers.sql`         | Record (not a script) of the app's table triggers after `hardening.sql` and `hardening2.sql` |
| `views_extend.sql`     | Issue #49: extends `v_grades`, `v_clearance_items`, `v_clearances` to the columns of `types/database.types.ts` (`CREATE OR REPLACE`, still `security_invoker = true`); safety checks, rollback and diagnostics as comments |
| `grants_clearance.sql` | Issue #60: exposes the clearance slice to `authenticated` only (SELECT on 3 views, `charges`, `payments`, `audit_logs`; column-level writes on `clearances`, `clearance_items`, `academic_holds`, `payments`, `charges`), then repeats the anon part of `hardening2.sql` section C; checks before and after, rollback and diagnostics as comments. **Not run yet** |
| `grants_clearance_test.sql` | Tests TC-34 to TC-39 for `grants_clearance.sql` (each block ends in `ROLLBACK`), plus how to rehearse the whole change in a rolled-back transaction (TC-34R) |

`views.sql`, `private_functions.sql` and the policies in `rls.sql` were exported from the
live Supabase project on 2026-10-10 (`pg_views`, `pg_get_functiondef`, `pg_policies`);
their SQL text is verbatim from the export.

## Execution order

Run in the Supabase **SQL Editor** (or `psql`), in exactly this order:

1. **`schema.sql`**
2. **`views.sql`**
3. Create the 7 test accounts in Supabase Auth (see below)
4. **`seed.sql`**
5. **`private_functions.sql`**
6. **`rls.sql`**
7. **`hardening.sql`** (issue #50; run as a whole, then the tests in
   `docs/issue-12-testing-guide.md` Part C and Part F. Undo with its ROLLBACK section.)
8. **`hardening2.sql`**, one section at a time, in this order: **section A**, then
   **section B**, then **section C** (C needs B; save diagnostic (a) before C). Then the
   tests in Part G of `docs/issue-12-testing-guide.md` (TC-24 to TC-28) and Parts C and F
   again. Undo with each section's ROLLBACK block, in reverse order (C, B, A).
9. **`views_extend.sql`** (issue #49; after `hardening2.sql` section C, because its
   checks expect authenticated SELECT and no anon access on the views). Run as a whole;
   save its diagnostics (a) to (c) first. Then the tests in Part H of
   `docs/issue-12-testing-guide.md` (TC-29 to TC-33) and TC-15, TC-16, TC-28 again. Undo
   with its ROLLBACK block (DROP + CREATE, then the grants again).
10. **`grants_clearance.sql`** (issue #60; after `views_extend.sql`). **NOT RUN YET.** First
   rehearse it in a rolled-back transaction (TC-34R, see the top of
   `grants_clearance_test.sql`) and save its diagnostic (a). Then run it as a whole, WITHOUT
   toggling the tables in the dashboard's Data API settings (the file header explains why
   the GRANTs are enough). Then Part I of `docs/issue-12-testing-guide.md` (TC-34 to TC-40)
   and TC-12 to TC-33 again. Undo with its ROLLBACK block.

`triggers.sql` is a record of the triggers, **not** a step: do not run it (it stops itself
and rolls back if run by mistake).

`hardening2.sql` sections A, B and C were run on the live database on 2026-10-10, one at a time, and tested
(TC-24 to TC-28 and the regression TC-12 to TC-23 in `docs/issue-12-testing-guide.md`). The grants before
section C are saved in `grants_snapshot_2026-10-10.txt`. Tables exposed later in the Supabase Data API get
full default rights again, so repeat the anon part of section C afterwards.

`hardening.sql` was run on the live database on 2026-10-10 and tested (TC-18 to TC-23 and the
regression TC-12 to TC-17 in `docs/issue-12-testing-guide.md`). It is a change on top of the live
export: `rls.sql` and `private_functions.sql` still show the policies and function as exported
BEFORE it, so the live versions of `clearance_items_dept_update`, `holds_dept_lift`,
`clearances_registrar_approve` and `private.my_department_id()` are the ones in `hardening.sql`.

## Views (issue #49)

`types/database.types.ts` and `lib/mock-data.ts` expect more view columns than the live
views have. `views_extend.sql` adds them (option A: change the views, not the app):
`v_grades` gets the enrollment, term, section and subject columns; `v_clearance_items`
gets `student_id`, `term_id`, `department_name`, `department_type`; `v_clearances` gets
`total_items` and `cleared_items`. `v_active_holds` already matches. All new joins are
LEFT JOINs, so with `security_invoker` every role keeps exactly the rows it saw before.
For Cashier and Department, `total_items` / `cleared_items` count only their own
department's items (RLS on `clearance_items`).

`views_extend.sql` was run on the live database on 2026-10-10 and Part H (TC-29 to TC-33) passed.
`views.sql` now holds the extended definitions. To recreate the database from scratch, run
`schema.sql`, then `views.sql` (not `views_extend.sql`, which is the change script for a database that
still has the old thin views).

These files were run end to end against an in-memory PostgreSQL (with a stand-in for
`auth.users`/`auth.uid()`): the seed gives 3 students, charges of 45,000 with 20,000
collected, and 3/4, 2/4 and 3/4 offices cleared; with RLS on, each role sees only its
own rows (student: own rows only, Cashier and Department: their own office, Registrar and
Admin: everything).

## Known gaps (Backend team)

Views, `private` functions and policies now match the live database (export of
2026-10-10). These are still **not exported** and are therefore not in this folder:

- **Triggers.** `triggers.sql` records them, but the exact definition of
  `trg_clearances_create_items` on `clearances` (calls `private.create_clearance_items()`)
  is still to be filled in from the live database. List them with:
  `select event_object_table, trigger_name, action_timing, event_manipulation, action_statement from information_schema.triggers where trigger_schema = 'public';`
- **Grants.** No `GRANT` / `REVOKE` statements were exported (schema `private`, functions,
  tables, views). `private_functions.sql` keeps the old draft grants as a comment only;
  verify them against the live database. The grant state before `hardening2.sql` section C
  is in `grants_snapshot_2026-10-10.txt`; `hardening2.sql` section C and (once run)
  `grants_clearance.sql` are the written-down changes since. Grants on sequences and the
  server role's grants are still not written down.
- **Audit triggers.** `hardening2.sql` section B (REQ-ADM-03) is live; `audit_logs` only holds
  changes made after 2026-10-10 (no back-fill).
- **Views vs types (issue #49): fixed** on 2026-10-10 with `views_extend.sql`; the live views have every
  column of `types/database.types.ts`. Open: `v_clearances.status` has no `Ready` value (the mock data does).

## Read before running

- **Create the 7 test accounts in Supabase Auth first.** `seed.sql` links its
  `profiles` rows to existing `auth.users` ids (`profiles.profile_id` ->
  `auth.users.id`). Create the users in the Supabase Dashboard
  (Authentication -> Users) *before* step 4, otherwise the seed will fail.
  Accounts are provisioned by the Admin through Supabase Auth, as stated in the
  SRS, section 2.2. Share test credentials with teammates privately, never in
  this repo.
- **`seed.sql` finds the accounts by e-mail**, so no UUIDs have to be edited. Names and
  student numbers match the Figma screens (`lib/mock-data.ts` is a separate UI-only dataset).
- **Do NOT run `seed.sql` again after `rls.sql`.** Once RLS is enabled the
  database is in its protected state; re-seeding can conflict with existing
  rows and policies. To reset, recreate the schema from step 1.
- **RLS must stay enabled on every table** (SRS SEC-02). Any new table added to
  `schema.sql` needs matching policies in `rls.sql`
  (Developer Onboarding: "Backend developers must enable RLS on each new table").

## Security rules for these files

These come from SRS SEC-05 / SEC-06 and the Developer Onboarding guide:

- No passwords, password hashes, JWTs, API keys, or connection strings.
- The Supabase `service_role` key must never appear in the repo. Only the anon
  key is used client-side, and `.env.local` is never committed.
- No real student data; the Data Privacy Act of 2012 applies (SRS ETH-01), so
  seed data must be fictional.
- Schema changes follow the normal Git flow: branch off `dev`, open a PR, and
  have a teammate review. Only the Project Manager merges `dev` into `main`.

### Pre-commit scrub

Run from the repo root before committing any `.sql` file; it must print nothing:

```bash
grep -rniE "service_role|eyJ[A-Za-z0-9_-]{10,}|sb_secret|postgres(ql)?://|password\s*(=|:)|encrypted_password" docs/database/ --include='*.sql'
```
