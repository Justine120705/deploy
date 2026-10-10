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

These files were run end to end against an in-memory PostgreSQL (with a stand-in for
`auth.users`/`auth.uid()`): the seed gives 3 students, charges of 45,000 with 20,000
collected, and 3/4, 2/4 and 3/4 offices cleared; with RLS on, each role sees only its
own rows (student: own rows only, Cashier and Department: their own office, Registrar and
Admin: everything).

## Known gaps (Backend team)

Views, `private` functions and policies now match the live database (export of
2026-10-10). These are still **not exported** and are therefore not in this folder:

- **Triggers.** For example the trigger on `clearances` that calls
  `private.create_clearance_items()` (the function is in `private_functions.sql`, the
  `CREATE TRIGGER` is not). List them with:
  `select event_object_table, trigger_name, action_timing, event_manipulation, action_statement from information_schema.triggers where trigger_schema = 'public';`
- **Grants.** No `GRANT` / `REVOKE` statements were exported (schema `private`, functions,
  tables, views). `private_functions.sql` keeps the old draft grants as a comment only;
  verify them against the live database.
- **Audit triggers.** `audit_logs` is empty until the Sprint 3 triggers (REQ-ADM-03) exist.
- **`types/database.types.ts`** lists more view columns than the live views have; regenerate
  the types or update the views.

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
