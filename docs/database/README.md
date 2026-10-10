# Database SQL (Supabase / PostgreSQL)

SQL scripts needed to recreate the Centralized Student Portal database and to
review its Row Level Security (RLS) policies locally. Owned by the **Backend
team** (see Project Charter, section 5: "ERD and 3NF Tables").

| File                   | Contents                                                                 |
| ---------------------- | ------------------------------------------------------------------------ |
| `schema.sql`           | 23 tables (3NF) in dependency order, plus `document_ticket_seq`          |
| `seed.sql`             | Fictional test data: 7 accounts' profiles, 3 students, one full term     |
| `private_functions.sql`| Helper functions used by the policies (schema `private`) - **draft**     |
| `rls.sql`              | `ENABLE ROW LEVEL SECURITY` on all 23 tables and the policies (41)       |

## Execution order

Run in the Supabase **SQL Editor** (or `psql`), in exactly this order:

1. **`schema.sql`**
2. Create the 7 test accounts in Supabase Auth (see below)
3. **`seed.sql`**
4. **`private_functions.sql`**
5. **`rls.sql`**

These files were run end to end against an in-memory PostgreSQL (with a stand-in for
`auth.users`/`auth.uid()`): the seed gives 3 students, charges of 45,000 with 20,000
collected, and 3/4, 2/4 and 3/4 offices cleared; with RLS on, each role sees only its
own rows (student: own rows only, Cashier and Department: their own office, Registrar and
Admin: everything).

## Known gaps (Backend team)

The files above were rebuilt from the exported schema and the policies, so a few things
still need to be copied from the live Supabase project. Run these in the SQL Editor and
paste the output into the matching file:

- **Views.** `v_active_holds`, `v_clearance_items`, `v_clearances` and `v_grades` are used
  by `types/database.types.ts` but are not in `schema.sql`:
  `select viewname, definition from pg_views where schemaname = 'public';`
- **Helper functions.** `private_functions.sql` is a reconstruction. Replace it with:
  `select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private';`
- **Policies.** The project notes count 49 policies; `rls.sql` has 41. List the live ones with:
  `select tablename, policyname from pg_policies where schemaname = 'public' order by 1, 2;`
  and add the missing ones (likely the INSERT and UPDATE policies of the Student, Cashier and
  Registrar modules).
- **Audit triggers.** `audit_logs` is empty until the Sprint 3 triggers (REQ-ADM-03) exist.

## Read before running

- **Create the 7 test accounts in Supabase Auth first.** `seed.sql` links its
  `profiles` rows to existing `auth.users` ids (`profiles.profile_id` ->
  `auth.users.id`). Create the users in the Supabase Dashboard
  (Authentication -> Users) *before* step 2, otherwise the seed will fail.
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
