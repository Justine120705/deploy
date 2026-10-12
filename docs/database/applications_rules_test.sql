-- ==========================================
-- TESTS TC-123 to TC-135 for applications_rules.sql (enrollment site for new applicants)
-- ==========================================
-- Run AFTER applications_rules.sql is live (or use applications_rules_rehearsal.sql, which
-- runs the change and these tests together, TC-123R). This file is the same as the test
-- part of the rehearsal (from its "TESTS START HERE" marker).
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file and click
-- Run on the whole tab, never a selection. It ends in rollback: nothing is committed. If it
-- stops with an error, run "rollback;" as its own query and send the error back.
-- One exception to "nothing is committed": sequences are not transactional. TC-133 moves
-- public.student_number_seq and puts it back exactly (setval to the saved state), so run
-- the tests while nobody is provisioning a new student.
--
-- Data: applicant emails under @applicant.test (no profile / Auth user may exist there;
-- checked; old test rows are deleted INSIDE the transaction), plus the seed accounts
-- student1/2/3, registrar, cashier, dept, admin @pnc.test. Every application is created
-- inside the transaction (by anon through submit_application, or as postgres through the
-- same trigger), so every row satisfies the table's CHECK constraints. TC-123 prints every
-- CHECK / UNIQUE constraint on profiles, students, programs and applications
-- (informational) so a surprise constraint is visible in the result. Provisioning (TC-131)
-- links seed students (their profiles already exist), so no Auth user is created.
-- Users are simulated with SET LOCAL ROLE authenticated + request.jwt.claims (sub = the
-- user's id); anon with SET LOCAL ROLE anon; "postgres" = no JWT (auth.uid() NULL), which
-- is also how the server role reaches the table (no user JWT; triggers fire for both).
-- now() is the same for the whole transaction, so submitted_at / reviewed_at /
-- provisioned_at = now() is exact.
--
-- Result: ONE row, one cell per case ending in "-> OK" or "-> FAIL", plus all_ok. Every
-- statement that is expected to fail runs inside a do block with an exception handler, so
-- the transaction is never aborted by an expected error. Each step is recorded as
-- "rows N" or "ERR [SQLSTATE]: message". Booleans inside cells may print as t / f.
--
--   TC-123 installed as intended (columns, CHECKs, partial unique index, RLS + 2 Registrar
--          policies, triggers, function properties and grants, table / column / sequence
--          privileges, sequence after the highest student number) + list of constraints
--   TC-124 anon and a student get the programs through list_programs(); anon cannot read
--          programs or applications directly
--   TC-125 anon submits a valid application: stored normalised (trimmed, single spaces,
--          lower-case email), Pending, submitted_at = now(), audited with actor NULL; a
--          signed-in user can submit too
--   TC-126 input validation: 25 bad inputs -> 22023 "invalid application:", nothing
--          written; 4 boundary inputs accepted (100-character names, 64-character local
--          part, blank mobile -> NULL, accented letters and typographic apostrophe)
--   TC-127 no enumeration: a duplicate open application and an existing account give the
--          same success and insert nothing; cap of 3 applications per email
--   TC-128 the Registrar accepts: reviewed_by / reviewed_at by the database (sending
--          reviewed_by is refused by the grant), audited with the Registrar as actor
--   TC-129 the Registrar rejects: remarks required (missing or blank), trimmed; the
--          applicant may apply again after a rejection
--   TC-130 Accepted / Rejected are final; Pending -> Pending and unknown status refused;
--          applicant data immutable; owner INSERT must be Pending and gets DB values;
--          owner decision needs a reviewer
--   TC-131 provisioning link (as postgres = server-role path): only once, only Accepted,
--          only a matching Student (email + program); provisioned_at by the database; the
--          Registrar cannot link
--   TC-132 roles: Student / Cashier / Department / Admin see and change nothing; nobody
--          signed in can INSERT or DELETE; anon has no table or sequence access
--   TC-133 next_student_number(): anon and authenticated refused; 'YYYY-NNNN' with the
--          Manila year, after the highest number, skips a taken number; sequence restored;
--          a server (bypass-RLS) role can execute it
--   TC-134 anon cannot call the private helpers; the anon-executable functions in public
--          are exactly the two lockout functions and the two new ones
--   TC-135 flood valve: at the hourly cap every submission gets "try later:" (fresh,
--          duplicate or existing email alike); validation still answers first
--
-- Status: NOT RUN YET (written 2026-10-12 without a local PostgreSQL).

begin;

-- ==========================================
-- 1. Accounts, ids and a clean start (as postgres, no user JWT)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.s3',   coalesce((select id::text from auth.users where email = 'student3@pnc.test'), ''), true);
select set_config('app.reg',  coalesce((select id::text from auth.users where email = 'registrar@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.dept', coalesce((select id::text from auth.users where email = 'dept@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.s1email', coalesce((select lower(btrim(email)) from public.profiles where profile_id::text = current_setting('app.s1')), ''), true);
select set_config('app.s2email', coalesce((select lower(btrim(email)) from public.profiles where profile_id::text = current_setting('app.s2')), ''), true);
select set_config('app.s3email', coalesce((select lower(btrim(email)) from public.profiles where profile_id::text = current_setting('app.s3')), ''), true);
select set_config('app.s1prog', coalesce((select program_id::text from public.students where student_id::text = current_setting('app.s1')), ''), true);
select set_config('app.s2prog', coalesce((select program_id::text from public.students where student_id::text = current_setting('app.s2')), ''), true);
select set_config('app.s3prog', coalesce((select program_id::text from public.students where student_id::text = current_setting('app.s3')), ''), true);
select set_config('app.prog_other3', coalesce((select min(program_id)::text from public.programs
                                               where program_id::text <> current_setting('app.s3prog')), ''), true);
select set_config('app.prog_missing', (select (coalesce(max(program_id), 0) + 1000)::text from public.programs), true);
do $$
declare v_bad text;
begin
  if to_regprocedure('public.submit_application(text, text, text, text, bigint)') is null
     or to_regprocedure('public.next_student_number()') is null
     or to_regclass('public.applications') is null then
    raise exception 'TC setup: applications_rules.sql is not installed (run it, or use applications_rules_rehearsal.sql)';
  end if;
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
  if current_setting('app.s1email') = '' or current_setting('app.s2email') = '' or current_setting('app.s3email') = ''
     or current_setting('app.prog_other3') = '' then
    raise exception 'TC setup: seed emails / programs missing (s1 [%], s2 [%], s3 [%], other program [%]); at least 2 programs are needed',
      current_setting('app.s1email'), current_setting('app.s2email'), current_setting('app.s3email'), current_setting('app.prog_other3');
  end if;
  if exists (select 1 from public.profiles where lower(email) like '%@applicant.test')
     or exists (select 1 from auth.users where lower(email) like '%@applicant.test') then
    raise exception 'TC setup: a profile or Auth user under @applicant.test exists; the tests need that domain free';
  end if;
end $$;
delete from public.applications
where email like '%@applicant.test'
   or email in (current_setting('app.s1email'), current_setting('app.s2email'), current_setting('app.s3email'));

-- ==========================================
-- 2. TC-123: installed as intended (catalog)
-- ==========================================
select set_config('app.r123', (select format('columns_diff [%s], checks %s, open_email_index %s, rls %s, policies [%s], triggers [%s], public_fns_ok %s/3, private_fns_ok %s/5, anon_privs [%s], auth_select %s, auth_table_writes [%s], auth_column_grants [%s], seq_privs [%s], seq_after_max %s, constraints [%s] -> %s',
    x.cols_diff, x.checks, x.open_idx, x.rls, x.pol, x.trg, x.pub_ok, x.priv_ok, x.anon_privs, x.auth_select,
    x.auth_writes, x.auth_cols, x.seq_privs, x.seq_ok, x.constraints,
    case when x.cols_diff = '' and x.checks = 6 and x.open_idx and x.rls
          and x.pol = 'applications_registrar_read (SELECT), applications_registrar_review (UPDATE)'
          and x.trg = 'audit_log 29 O, require_application_rules 23 O'
          and x.pub_ok = 3 and x.priv_ok = 5 and x.anon_privs = '' and x.auth_select and x.auth_writes = ''
          and x.auth_cols = 'remarks UPDATE, status UPDATE' and x.seq_privs = '' and x.seq_ok
         then 'OK' else 'FAIL' end)
  from (select
    coalesce((with expected(col, typ) as (values
                ('application_id', 'bigint'), ('first_name', 'character varying'),
                ('last_name', 'character varying'), ('email', 'character varying'),
                ('mobile', 'character varying'), ('program_id', 'bigint'),
                ('status', 'character varying'), ('submitted_at', 'timestamp with time zone'),
                ('reviewed_by', 'uuid'), ('reviewed_at', 'timestamp with time zone'),
                ('remarks', 'character varying'), ('student_id', 'uuid'),
                ('provisioned_at', 'timestamp with time zone')),
              live as (
                select a.attname::text as col, format_type(a.atttypid, null) as typ
                from pg_attribute a
                where a.attrelid = 'public.applications'::regclass and a.attnum > 0 and not a.attisdropped)
              select string_agg(d, '; ' order by d) from (
                (select 'missing ' || col || ' ' || typ as d from (select * from expected except select * from live) m)
                union all
                (select 'unexpected ' || col || ' ' || typ from (select * from live except select * from expected) u)) dd), '') as cols_diff,
    (select count(*) from pg_constraint c
      where c.conrelid = 'public.applications'::regclass and c.contype = 'c'
        and c.conname in ('ck_applications_status', 'ck_applications_names', 'ck_applications_email',
                          'ck_applications_review', 'ck_applications_rejected_remarks', 'ck_applications_provisioned')) as checks,
    exists (select 1 from pg_index i
             where i.indexrelid = to_regclass('public.uq_applications_open_email')
               and i.indrelid = 'public.applications'::regclass and i.indisunique and i.indpred is not null
               and pg_get_indexdef(i.indexrelid) like '%(email)%Pending%Accepted%') as open_idx,
    (select c.relrowsecurity from pg_class c where c.oid = 'public.applications'::regclass) as rls,
    coalesce((select string_agg(p.policyname || ' (' || p.cmd || ')', ', ' order by p.policyname)
                from pg_policies p where p.schemaname = 'public' and p.tablename = 'applications'), '') as pol,
    coalesce((select string_agg(t.tgname || ' ' || t.tgtype || ' ' || t.tgenabled::text, ', ' order by t.tgname)
                from pg_trigger t
               where t.tgrelid = 'public.applications'::regclass and not t.tgisinternal
                 and t.tgfoid in (to_regprocedure('private.audit_log()'), to_regprocedure('private.require_application_rules()'))), '') as trg,
    (select count(*) from pg_proc p
      where p.oid in (to_regprocedure('public.list_programs()'),
                      to_regprocedure('public.submit_application(text, text, text, text, bigint)'),
                      to_regprocedure('public.next_student_number()'))
        and p.prosecdef and array_to_string(p.proconfig, ',') in ('search_path=""', 'search_path=''''')
        and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
        and has_function_privilege('anon', p.oid, 'EXECUTE') = (p.proname <> 'next_student_number')
        and has_function_privilege('authenticated', p.oid, 'EXECUTE') = (p.proname <> 'next_student_number')
        and exists (select 1 from pg_roles r join pg_class c on c.oid = 'public.students'::regclass
                     where r.oid = p.proowner
                       and (r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity)))) as pub_ok,
    (select count(*) from pg_proc p
      where p.oid in (to_regprocedure('private.application_settings()'),
                      to_regprocedure('private.application_name(text, text)'),
                      to_regprocedure('private.application_email(text)'),
                      to_regprocedure('private.application_mobile(text)'),
                      to_regprocedure('private.require_application_rules()'))
        and not p.prosecdef and array_to_string(p.proconfig, ',') in ('search_path=""', 'search_path=''''')
        and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
        and not has_function_privilege('anon', p.oid, 'EXECUTE')
        and (p.proname = 'require_application_rules' or not has_function_privilege('authenticated', p.oid, 'EXECUTE'))) as priv_ok,
    coalesce((select string_agg(e.t || ' ' || e.priv, ', ')
                from (values ('applications'), ('programs')) as tt(t)
                cross join lateral (select tt.t as t, v.priv from (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                                    ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) as v(priv)) e
               where has_table_privilege('anon', 'public.' || e.t, e.priv)
                  or (e.priv in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
                      and has_any_column_privilege('anon', 'public.' || e.t, e.priv))), '') as anon_privs,
    has_table_privilege('authenticated', 'public.applications', 'SELECT') as auth_select,
    coalesce((select string_agg(v.priv, ', ') from (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                ('REFERENCES'), ('TRIGGER')) as v(priv)
               where has_table_privilege('authenticated', 'public.applications', v.priv)), '') as auth_writes,
    coalesce((select string_agg(a.attname || ' ' || x.privilege_type, ', ' order by a.attname, x.privilege_type)
                from pg_attribute a cross join lateral aclexplode(a.attacl) x
               where a.attrelid = 'public.applications'::regclass and a.attnum > 0 and not a.attisdropped
                 and a.attacl is not null and x.grantee = 'authenticated'::regrole), '') as auth_cols,
    coalesce((select string_agg(s.s || ' ' || w.who, ', ')
                from (values ('public.student_number_seq'),
                             (pg_get_serial_sequence('public.applications', 'application_id'))) as s(s)
                cross join (values ('anon'), ('authenticated')) as w(who)
               where has_sequence_privilege(w.who, s.s, 'USAGE, SELECT, UPDATE')), '') as seq_privs,
    ((select q.is_called from public.student_number_seq q)
     and (select q.last_value from public.student_number_seq q)
         >= greatest(3, (select coalesce(max(substring(s.student_number::text from '^[0-9]{4}-([0-9]{1,15})$')::bigint), 0)
                           from public.students s))) as seq_ok,
    coalesce((select string_agg(c.conrelid::regclass::text || '.' || c.conname || ' ' || pg_get_constraintdef(c.oid), '; '
                                order by c.conrelid::regclass::text, c.conname)
                from pg_constraint c
               where c.contype in ('c', 'u')
                 and c.conrelid in ('public.profiles'::regclass, 'public.students'::regclass,
                                    'public.programs'::regclass, 'public.applications'::regclass)), '') as constraints
  ) x), true);

-- ==========================================
-- 3. TC-124: programs for the public form
-- ==========================================
select set_config('app.t124_expected', (select coalesce(string_agg(p.program_id || ':' || p.code || ':' || p.name, ',' order by p.code), '')
                                          from public.programs p), true);
set local role anon;
do $$
declare v text; n bigint;
begin
  begin
    select coalesce(string_agg(l.program_id || ':' || l.code || ':' || l.name, ',' order by l.code), '') into v
    from public.list_programs() l;
    perform set_config('app.t124_anon', v, true);
  exception when others then
    perform set_config('app.t124_anon', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
  end;
  begin
    execute 'select * from public.programs';
    get diagnostics n = row_count;
    perform set_config('app.t124_anon_programs', 'ALLOWED rows ' || n, true);
  exception when others then
    perform set_config('app.t124_anon_programs', case when sqlerrm like 'permission denied%' then 'denied' else 'ERR [' || sqlstate || ']: ' || sqlerrm end, true);
  end;
  begin
    execute 'select * from public.applications';
    get diagnostics n = row_count;
    perform set_config('app.t124_anon_applications', 'ALLOWED rows ' || n, true);
  exception when others then
    perform set_config('app.t124_anon_applications', case when sqlerrm like 'permission denied%' then 'denied' else 'ERR [' || sqlstate || ']: ' || sqlerrm end, true);
  end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v text;
begin
  select coalesce(string_agg(l.program_id || ':' || l.code || ':' || l.name, ',' order by l.code), '') into v
  from public.list_programs() l;
  perform set_config('app.t124_student', v, true);
exception when others then
  perform set_config('app.t124_student', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r124', format('anon_same_as_table %s, student_same_as_table %s, programs %s, anon_programs_table [%s], anon_applications_table [%s] -> %s',
  current_setting('app.t124_anon') = current_setting('app.t124_expected'),
  current_setting('app.t124_student') = current_setting('app.t124_expected'),
  (select count(*) from public.programs),
  current_setting('app.t124_anon_programs'), current_setting('app.t124_anon_applications'),
  case when current_setting('app.t124_expected') <> ''
        and current_setting('app.t124_anon') = current_setting('app.t124_expected')
        and current_setting('app.t124_student') = current_setting('app.t124_expected')
        and current_setting('app.t124_anon_programs') = 'denied'
        and current_setting('app.t124_anon_applications') = 'denied'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 4. TC-125: anon submits a valid application
-- ==========================================
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role anon;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c125_anon', $q$select public.submit_application(U&'  Ma.  Pe\00F1a ', 'O''Brien-Dela Cruz', '  TC125.Juan@Applicant.TEST ',
                                                          '+63 917-123-4567', current_setting('app.s1prog')::bigint)$q$)
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
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c125_signed_in', 's2', $q$select public.submit_application('Ben', 'Santos', 'tc125-signed-in@applicant.test',
                                                                     null, current_setting('app.s2prog')::bigint)$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
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
select set_config('request.jwt.claims', '', true);
select set_config('app.a125', coalesce((select application_id::text from public.applications
                                         where email = 'tc125.juan@applicant.test'), '0'), true);
select set_config('app.r125', format('anon [%s], signed_in [%s], row [%s], signed_in_rows %s, audit_insert_actor_null %s -> %s',
  current_setting('app.c125_anon'), current_setting('app.c125_signed_in'),
  coalesce((select a.first_name || ' | ' || a.last_name || ' | ' || a.email || ' | ' || coalesce(a.mobile, 'NULL')
                   || ' | ' || a.status || ' | submitted_now ' || (a.submitted_at = now())
                   || ' | reviewed ' || coalesce(a.reviewed_by::text, 'NULL') || ' / ' || coalesce(a.reviewed_at::text, 'NULL')
                   || ' | student ' || coalesce(a.student_id::text, 'NULL')
              from public.applications a where a.application_id = current_setting('app.a125')::bigint), 'none'),
  (select count(*) from public.applications where email = 'tc125-signed-in@applicant.test' and status = 'Pending'),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'applications'
      and l.record_id = current_setting('app.a125') and l.action = 'INSERT' and l.actor_id is null),
  case when current_setting('app.c125_anon') = 'rows 1' and current_setting('app.c125_signed_in') = 'rows 1'
        and coalesce((select a.first_name = U&'Ma. Pe\00F1a' and a.last_name = 'O''Brien-Dela Cruz'
                             and a.email = 'tc125.juan@applicant.test' and a.mobile = '+63 917-123-4567'
                             and a.program_id::text = current_setting('app.s1prog')
                             and a.status = 'Pending' and a.submitted_at = now()
                             and a.reviewed_by is null and a.reviewed_at is null and a.remarks is null
                             and a.student_id is null and a.provisioned_at is null
                        from public.applications a where a.application_id = current_setting('app.a125')::bigint), false)
        and (select count(*) from public.applications where email = 'tc125-signed-in@applicant.test' and status = 'Pending') = 1
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'applications'
                and l.record_id = current_setting('app.a125') and l.action = 'INSERT' and l.actor_id is null) = 1
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 5. TC-126: input validation
-- ==========================================
select set_config('app.t126_rows_before', (select count(*)::text from public.applications), true);
set local role anon;
do $$
declare
  r     record;
  v_ok  integer := 0;
  v_bad text := '';
begin
  for r in select * from (values
    (1,  'first null',      $q$select public.submit_application(null, 'Cruz', 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (2,  'first blank',     $q$select public.submit_application('   ', 'Cruz', 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (3,  'first 101',       $q$select public.submit_application(repeat('a', 101), 'Cruz', 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (4,  'first digit',     $q$select public.submit_application('Juan2', 'Cruz', 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (5,  'first newline',   $q$select public.submit_application('Ju' || chr(10) || 'an', 'Cruz', 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (6,  'first symbol',    $q$select public.submit_application('Juan<b>', 'Cruz', 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (7,  'first period',    $q$select public.submit_application('.Juan', 'Cruz', 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (8,  'last null',       $q$select public.submit_application('Juan', null, 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (9,  'last tab',        $q$select public.submit_application('Juan', 'Cruz' || chr(9), 'tc126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (10, 'email null',      $q$select public.submit_application('Juan', 'Cruz', null, null, current_setting('app.s1prog')::bigint)$q$),
    (11, 'email blank',     $q$select public.submit_application('Juan', 'Cruz', '   ', null, current_setting('app.s1prog')::bigint)$q$),
    (12, 'email no at',     $q$select public.submit_application('Juan', 'Cruz', 'tc126.applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (13, 'email two at',    $q$select public.submit_application('Juan', 'Cruz', 'tc126@x@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (14, 'email space',     $q$select public.submit_application('Juan', 'Cruz', 'tc 126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (15, 'email no tld',    $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant', null, current_setting('app.s1prog')::bigint)$q$),
    (16, 'email dots',      $q$select public.submit_application('Juan', 'Cruz', 'tc..126@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (17, 'email 255',       $q$select public.submit_application('Juan', 'Cruz', repeat('a', 240) || '@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (18, 'email local 65',  $q$select public.submit_application('Juan', 'Cruz', repeat('a', 65) || '@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (19, 'email control',   $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant.test' || chr(13), null, current_setting('app.s1prog')::bigint)$q$),
    (20, 'mobile letters',  $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant.test', '0917-ABC-4567', current_setting('app.s1prog')::bigint)$q$),
    (21, 'mobile 6',        $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant.test', '123456', current_setting('app.s1prog')::bigint)$q$),
    (22, 'mobile 6 digits', $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant.test', '12-34-56', current_setting('app.s1prog')::bigint)$q$),
    (23, 'mobile 21',       $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant.test', repeat('1', 21), current_setting('app.s1prog')::bigint)$q$),
    (24, 'program null',    $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant.test', null, null)$q$),
    (25, 'program missing', $q$select public.submit_application('Juan', 'Cruz', 'tc126@applicant.test', null, current_setting('app.prog_missing')::bigint)$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      v_bad := v_bad || case when v_bad = '' then '' else ', ' end || r.label || ' ACCEPTED';
    exception when others then
      if sqlstate = '22023' and sqlerrm like 'invalid application:%' then
        v_ok := v_ok + 1;
      else
        v_bad := v_bad || case when v_bad = '' then '' else ', ' end || r.label || ' ' || sqlstate || ' ' || sqlerrm;
      end if;
    end;
  end loop;
  perform set_config('app.t126_ok', v_ok::text, true);
  perform set_config('app.t126_bad', v_bad, true);
end $$;
reset role;
select set_config('app.t126_rows_mid', (select count(*)::text from public.applications), true);
set local role anon;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c126_max',   $q$select public.submit_application(repeat('a', 100), repeat('b', 100), 'tc126-max@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (2, 'c126_blank', $q$select public.submit_application('Ana  Marie', 'Dela  Cruz', 'tc126-blank@applicant.test', '   ', current_setting('app.s1prog')::bigint)$q$),
    (3, 'c126_local', $q$select public.submit_application('Jo', 'Li', repeat('c', 64) || '@applicant.test', '0917 123 4567', current_setting('app.s1prog')::bigint)$q$),
    (4, 'c126_utf',   $q$select public.submit_application(U&'\00C9lise', U&'D\2019Souza', 'tc126.d+tag@sub.applicant.test', '1234567', current_setting('app.s1prog')::bigint)$q$)
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
select set_config('app.r126', format('rejected_22023 %s/25, unexpected [%s], rows_written_by_bad_input %s, max [%s], blank [%s], local64 [%s], accented [%s], stored [%s] -> %s',
  current_setting('app.t126_ok'), current_setting('app.t126_bad'),
  current_setting('app.t126_rows_mid')::bigint - current_setting('app.t126_rows_before')::bigint,
  current_setting('app.c126_max'), current_setting('app.c126_blank'), current_setting('app.c126_local'), current_setting('app.c126_utf'),
  coalesce((select string_agg(a.first_name || ' ' || a.last_name || ' ' || coalesce(a.mobile, 'NULL'), '; ' order by a.application_id)
              from public.applications a
             where a.email in ('tc126-blank@applicant.test', 'tc126.d+tag@sub.applicant.test')), 'none'),
  case when current_setting('app.t126_ok') = '25' and current_setting('app.t126_bad') = ''
        and current_setting('app.t126_rows_mid') = current_setting('app.t126_rows_before')
        and current_setting('app.c126_max') = 'rows 1' and current_setting('app.c126_blank') = 'rows 1'
        and current_setting('app.c126_local') = 'rows 1' and current_setting('app.c126_utf') = 'rows 1'
        and (select count(*) from public.applications) - current_setting('app.t126_rows_before')::bigint = 4
        and exists (select 1 from public.applications a where a.email = 'tc126-blank@applicant.test'
                      and a.first_name = 'Ana Marie' and a.last_name = 'Dela Cruz' and a.mobile is null)
        and exists (select 1 from public.applications a where a.email = 'tc126-max@applicant.test'
                      and length(a.first_name) = 100 and length(a.last_name) = 100)
        and exists (select 1 from public.applications a where a.email = 'tc126.d+tag@sub.applicant.test'
                      and a.first_name = U&'\00C9lise' and a.last_name = U&'D\2019Souza' and a.mobile = '1234567')
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 6. TC-127: no enumeration; per-email cap
-- ==========================================
select set_config('app.t127_s1_before', (select count(*)::text from public.applications
                                          where email = current_setting('app.s1email')), true);
set local role anon;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c127_first',   $q$select public.submit_application('Tc', 'Seven', 'tc127@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (2, 'c127_again',   $q$select public.submit_application('Other', 'Person', 'tc127@applicant.test', '09171234567', current_setting('app.s2prog')::bigint)$q$),
    (3, 'c127_case',    $q$select public.submit_application('Tc', 'Seven', '  TC127@Applicant.Test ', null, current_setting('app.s1prog')::bigint)$q$),
    (4, 'c127_account', $q$select public.submit_application('Ana', 'Reyes', current_setting('app.s1email'), null, current_setting('app.s1prog')::bigint)$q$),
    (5, 'c127_account2', $q$select public.submit_application('Ana', 'Reyes', '  ' || upper(current_setting('app.s1email')) || ' ', null, current_setting('app.s1prog')::bigint)$q$)
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
-- Cap: submit, reject (as postgres, the reviewer given), 4 times. The caller role does not
-- matter here (submit_application runs as its owner); anon is covered above.
do $$
declare i integer; v text := '';
begin
  for i in 1..4 loop
    perform public.submit_application('Cap', 'Test', 'tc127cap@applicant.test', null, current_setting('app.s1prog')::bigint);
    update public.applications
       set status = 'Rejected', remarks = 'TC-127 cap', reviewed_by = current_setting('app.reg')::uuid
     where email = 'tc127cap@applicant.test' and status = 'Pending';
    v := v || case when v = '' then '' else ',' end
           || (select count(*) from public.applications where email = 'tc127cap@applicant.test');
  end loop;
  perform set_config('app.t127_cap', v, true);
exception when others then
  perform set_config('app.t127_cap', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select set_config('app.r127', format('first [%s], duplicate [%s], case_variant [%s], existing_account [%s], account_variant [%s], tc127_rows %s, account_rows_added %s, cap_counts [%s] -> %s',
  current_setting('app.c127_first'), current_setting('app.c127_again'), current_setting('app.c127_case'),
  current_setting('app.c127_account'), current_setting('app.c127_account2'),
  (select count(*) from public.applications where email = 'tc127@applicant.test'),
  (select count(*) from public.applications where email = current_setting('app.s1email')) - current_setting('app.t127_s1_before')::bigint,
  current_setting('app.t127_cap'),
  case when current_setting('app.c127_first') = 'rows 1' and current_setting('app.c127_again') = 'rows 1'
        and current_setting('app.c127_case') = 'rows 1' and current_setting('app.c127_account') = 'rows 1'
        and current_setting('app.c127_account2') = 'rows 1'
        and (select count(*) from public.applications where email = 'tc127@applicant.test') = 1
        and coalesce((select a.first_name = 'Tc' and a.program_id::text = current_setting('app.s1prog') and a.mobile is null
                        from public.applications a where a.email = 'tc127@applicant.test'), false)
        and (select count(*) from public.applications where email = current_setting('app.s1email')) = current_setting('app.t127_s1_before')::bigint
        and current_setting('app.t127_cap') = '1,2,3,3'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 7. TC-128: the Registrar accepts
-- ==========================================
with a as (insert into public.applications (first_name, last_name, email, mobile, program_id)
           values ('Tc', 'OneTwoEight', 'tc128@applicant.test', null, current_setting('app.s1prog')::bigint)
           returning application_id)
select set_config('app.a128', application_id::text, true) from a;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
set local role authenticated;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c128_spoof',  'reg', $q$update public.applications set status = 'Accepted', reviewed_by = current_setting('app.adm')::uuid
                                where application_id = current_setting('app.a128')::bigint$q$),
    (2, 'c128_accept', 'reg', $q$update public.applications set status = 'Accepted', remarks = 'TC-128 accepted'
                                where application_id = current_setting('app.a128')::bigint$q$),
    (3, 'c128_read',   'reg', $q$select * from public.applications where application_id = current_setting('app.a128')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
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
select set_config('request.jwt.claims', '', true);
select set_config('app.r128', format('spoof_reviewer [%s], accept [%s], registrar_reads [%s], row [%s], audit_ok %s -> %s',
  current_setting('app.c128_spoof'), current_setting('app.c128_accept'), current_setting('app.c128_read'),
  coalesce((select a.status || ', by_registrar ' || (a.reviewed_by::text = current_setting('app.reg'))
                   || ', at_now ' || (a.reviewed_at = now()) || ', remarks ' || coalesce(a.remarks, 'NULL')
                   || ', student ' || coalesce(a.student_id::text, 'NULL')
              from public.applications a where a.application_id = current_setting('app.a128')::bigint), 'none'),
  coalesce((select count(*) = 1 and bool_and(l.action = 'UPDATE' and l.actor_id::text = current_setting('app.reg')
                                         and l.old_data ->> 'status' = 'Pending' and l.new_data ->> 'status' = 'Accepted'
                                         and l.new_data ->> 'reviewed_by' = current_setting('app.reg'))
              from public.audit_logs l
             where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'applications'
               and l.record_id = current_setting('app.a128')), false),
  case when current_setting('app.c128_spoof') like 'ERR [42501]: permission denied%'
        and current_setting('app.c128_accept') = 'rows 1' and current_setting('app.c128_read') = 'rows 1'
        and coalesce((select a.status = 'Accepted' and a.reviewed_by::text = current_setting('app.reg')
                             and a.reviewed_at = now() and a.remarks = 'TC-128 accepted'
                             and a.student_id is null and a.provisioned_at is null
                        from public.applications a where a.application_id = current_setting('app.a128')::bigint), false)
        and coalesce((select count(*) = 1 and bool_and(l.action = 'UPDATE' and l.actor_id::text = current_setting('app.reg')
                                                   and l.old_data ->> 'status' = 'Pending' and l.new_data ->> 'status' = 'Accepted'
                                                   and l.new_data ->> 'reviewed_by' = current_setting('app.reg'))
                        from public.audit_logs l
                       where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'applications'
                         and l.record_id = current_setting('app.a128')), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 8. TC-129: the Registrar rejects (remarks required); the applicant may apply again
-- ==========================================
with a as (insert into public.applications (first_name, last_name, email, mobile, program_id)
           values ('Tc', 'OneTwoNine', 'tc129@applicant.test', null, current_setting('app.s1prog')::bigint)
           returning application_id)
select set_config('app.a129', application_id::text, true) from a;
set local role authenticated;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c129_none',  'reg', $q$update public.applications set status = 'Rejected'
                               where application_id = current_setting('app.a129')::bigint$q$),
    (2, 'c129_blank', 'reg', $q$update public.applications set status = 'Rejected', remarks = '   '
                               where application_id = current_setting('app.a129')::bigint$q$),
    (3, 'c129_ok',    'reg', $q$update public.applications set status = 'Rejected', remarks = '  Incomplete requirements  '
                               where application_id = current_setting('app.a129')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
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
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform public.submit_application('Tc', 'OneTwoNine', 'tc129@applicant.test', null, current_setting('app.s1prog')::bigint);
  perform set_config('app.c129_again', 'ok', true);
exception when others then
  perform set_config('app.c129_again', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select set_config('app.r129', format('no_remarks [%s], blank_remarks [%s], with_remarks [%s], row [%s], apply_again [%s], rows_for_email %s -> %s',
  current_setting('app.c129_none'), current_setting('app.c129_blank'), current_setting('app.c129_ok'),
  coalesce((select a.status || ', remarks [' || coalesce(a.remarks, 'NULL') || '], by_registrar '
                   || (a.reviewed_by::text = current_setting('app.reg')) || ', at_now ' || (a.reviewed_at = now())
              from public.applications a where a.application_id = current_setting('app.a129')::bigint), 'none'),
  current_setting('app.c129_again'),
  (select string_agg(a.status, ', ' order by a.application_id) from public.applications a where a.email = 'tc129@applicant.test'),
  case when current_setting('app.c129_none') = 'ERR [P0001]: remarks required: application ' || current_setting('app.a129')
                                                || ' cannot be rejected without remarks'
        and current_setting('app.c129_blank') like 'ERR [P0001]: remarks required:%'
        and current_setting('app.c129_ok') = 'rows 1'
        and coalesce((select a.status = 'Rejected' and a.remarks = 'Incomplete requirements'
                             and a.reviewed_by::text = current_setting('app.reg') and a.reviewed_at = now()
                        from public.applications a where a.application_id = current_setting('app.a129')::bigint), false)
        and current_setting('app.c129_again') = 'ok'
        and (select string_agg(a.status, ', ' order by a.application_id) from public.applications a
              where a.email = 'tc129@applicant.test') = 'Rejected, Pending'
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 9. TC-130: final states, bad transitions, immutable data, owner paths
-- ==========================================
with a as (insert into public.applications (first_name, last_name, email, mobile, program_id)
           values ('Tc', 'OneThreeZeroA', 'tc130a@applicant.test', null, current_setting('app.s1prog')::bigint)
           returning application_id)
select set_config('app.a130a', application_id::text, true) from a;
with a as (insert into public.applications (first_name, last_name, email, mobile, program_id)
           values ('Tc', 'OneThreeZeroB', 'tc130b@applicant.test', null, current_setting('app.s1prog')::bigint)
           returning application_id)
select set_config('app.a130b', application_id::text, true) from a;
with a as (insert into public.applications (first_name, last_name, email, mobile, program_id)
           values ('Tc', 'OneThreeZeroC', 'tc130c@applicant.test', null, current_setting('app.s1prog')::bigint)
           returning application_id)
select set_config('app.a130c', application_id::text, true) from a;
do $$
begin
  update public.applications set status = 'Accepted', reviewed_by = current_setting('app.reg')::uuid
  where application_id = current_setting('app.a130a')::bigint;
  update public.applications set status = 'Rejected', remarks = 'TC-130', reviewed_by = current_setting('app.reg')::uuid
  where application_id = current_setting('app.a130b')::bigint;
  perform set_config('app.c130_setup', 'ok', true);
exception when others then
  perform set_config('app.c130_setup', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
set local role authenticated;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c130_a_reject',  'reg', $q$update public.applications set status = 'Rejected', remarks = 'x'
                                   where application_id = current_setting('app.a130a')::bigint$q$),
    (2, 'c130_a_pending', 'reg', $q$update public.applications set status = 'Pending'
                                   where application_id = current_setting('app.a130a')::bigint$q$),
    (3, 'c130_a_remarks', 'reg', $q$update public.applications set remarks = 'changed'
                                   where application_id = current_setting('app.a130a')::bigint$q$),
    (4, 'c130_b_accept',  'reg', $q$update public.applications set status = 'Accepted'
                                   where application_id = current_setting('app.a130b')::bigint$q$),
    (5, 'c130_b_remarks', 'reg', $q$update public.applications set remarks = 'changed'
                                   where application_id = current_setting('app.a130b')::bigint$q$),
    (6, 'c130_c_pending', 'reg', $q$update public.applications set status = 'Pending', remarks = 'note'
                                   where application_id = current_setting('app.a130c')::bigint$q$),
    (7, 'c130_c_other',   'reg', $q$update public.applications set status = 'Enrolled'
                                   where application_id = current_setting('app.a130c')::bigint$q$),
    (8, 'c130_c_name',    'reg', $q$update public.applications set first_name = 'X'
                                   where application_id = current_setting('app.a130c')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
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
select set_config('request.jwt.claims', '', true);
do $$
declare r record; n bigint; v_id bigint;
begin
  for r in select * from (values
    (1, 'c130_pg_email',      $q$update public.applications set email = 'other130@applicant.test'
                                 where application_id = current_setting('app.a130c')::bigint$q$),
    (2, 'c130_pg_a_pending',  $q$update public.applications set status = 'Pending', reviewed_by = null, reviewed_at = null
                                 where application_id = current_setting('app.a130a')::bigint$q$),
    (3, 'c130_pg_insert_acc', $q$insert into public.applications (first_name, last_name, email, program_id, status, reviewed_by)
                                 values ('Tc', 'Owner', 'tc130-acc@applicant.test', current_setting('app.s1prog')::bigint,
                                         'Accepted', current_setting('app.reg')::uuid)$q$),
    (4, 'c130_pg_noreviewer', $q$update public.applications set status = 'Accepted'
                                 where application_id = current_setting('app.a130c')::bigint$q$),
    (5, 'c130_pg_noop',       $q$update public.applications set status = status
                                 where application_id = current_setting('app.a130a')::bigint$q$)
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
  -- Owner INSERT with values the database must replace.
  begin
    insert into public.applications (first_name, last_name, email, mobile, program_id, reviewed_by, reviewed_at,
                                     remarks, submitted_at, student_id, provisioned_at)
    values ('  Tc ', ' Owner ', ' TC130-Owner@Applicant.TEST ', null, current_setting('app.s1prog')::bigint,
            current_setting('app.reg')::uuid, '2000-01-01', 'x', '2000-01-01', current_setting('app.s1')::uuid, '2000-01-01')
    returning application_id into v_id;
    perform set_config('app.a130d', v_id::text, true);
    perform set_config('app.c130_pg_insert', 'rows 1', true);
  exception when others then
    perform set_config('app.a130d', '0', true);
    perform set_config('app.c130_pg_insert', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
  end;
end $$;
select set_config('app.r130', format('setup [%s], reg: a_reject [%s], a_pending [%s], a_remarks [%s], b_accept [%s], b_remarks [%s], c_pending [%s], c_other [%s], c_name [%s]; postgres: email [%s], a_pending [%s], insert_accepted [%s], no_reviewer [%s], noop [%s], insert [%s], inserted [%s], final [%s] -> %s',
  current_setting('app.c130_setup'),
  current_setting('app.c130_a_reject'), current_setting('app.c130_a_pending'), current_setting('app.c130_a_remarks'),
  current_setting('app.c130_b_accept'), current_setting('app.c130_b_remarks'), current_setting('app.c130_c_pending'),
  current_setting('app.c130_c_other'), current_setting('app.c130_c_name'),
  current_setting('app.c130_pg_email'), current_setting('app.c130_pg_a_pending'), current_setting('app.c130_pg_insert_acc'),
  current_setting('app.c130_pg_noreviewer'), current_setting('app.c130_pg_noop'), current_setting('app.c130_pg_insert'),
  coalesce((select a.first_name || ' | ' || a.last_name || ' | ' || a.email || ' | ' || a.status || ' | submitted_now ' || (a.submitted_at = now())
                   || ' | reviewed ' || coalesce(a.reviewed_by::text, 'NULL') || ' | remarks ' || coalesce(a.remarks, 'NULL')
                   || ' | student ' || coalesce(a.student_id::text, 'NULL')
              from public.applications a where a.application_id = current_setting('app.a130d')::bigint), 'none'),
  (select string_agg(a.status || ' ' || coalesce(a.remarks, 'NULL'), ', ' order by a.application_id)
     from public.applications a
    where a.application_id in (current_setting('app.a130a')::bigint, current_setting('app.a130b')::bigint,
                               current_setting('app.a130c')::bigint)),
  case when current_setting('app.c130_setup') = 'ok'
        and current_setting('app.c130_a_reject') = 'ERR [P0001]: bad decision: application ' || current_setting('app.a130a') || ' is Accepted and final'
        and current_setting('app.c130_a_pending') like 'ERR [P0001]: bad decision:%'
        and current_setting('app.c130_a_remarks') like 'ERR [P0001]: bad decision:%'
        and current_setting('app.c130_b_accept') = 'ERR [P0001]: bad decision: application ' || current_setting('app.a130b') || ' is Rejected and final'
        and current_setting('app.c130_b_remarks') like 'ERR [P0001]: bad decision:%'
        and current_setting('app.c130_c_pending') like 'ERR [P0001]: bad decision: application ' || current_setting('app.a130c') || ' is Pending and can only become%'
        and current_setting('app.c130_c_other') like 'ERR [P0001]: bad decision:%not Enrolled'
        and current_setting('app.c130_c_name') like 'ERR [42501]: permission denied%'
        and current_setting('app.c130_pg_email') like 'ERR [P0001]: bad decision: the applicant''s data%'
        and current_setting('app.c130_pg_a_pending') like 'ERR [P0001]: bad decision:%final'
        and current_setting('app.c130_pg_insert_acc') like 'ERR [P0001]: bad decision: a new application must be Pending%'
        and current_setting('app.c130_pg_noreviewer') like 'ERR [P0001]: bad decision: reviewer required:%'
        and current_setting('app.c130_pg_noop') like 'ERR [P0001]: bad decision:%only the one-time account link%'
        and current_setting('app.c130_pg_insert') = 'rows 1'
        and coalesce((select a.first_name = 'Tc' and a.last_name = 'Owner' and a.email = 'tc130-owner@applicant.test'
                             and a.status = 'Pending' and a.submitted_at = now() and a.reviewed_by is null
                             and a.reviewed_at is null and a.remarks is null and a.student_id is null and a.provisioned_at is null
                        from public.applications a where a.application_id = current_setting('app.a130d')::bigint), false)
        and (select string_agg(a.status || ' ' || coalesce(a.remarks, 'NULL'), ', ' order by a.application_id)
               from public.applications a
              where a.application_id in (current_setting('app.a130a')::bigint, current_setting('app.a130b')::bigint,
                                         current_setting('app.a130c')::bigint)) = 'Accepted NULL, Rejected TC-130, Pending NULL'
        and not exists (select 1 from public.applications where email = 'tc130-acc@applicant.test')
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 10. TC-131: provisioning link (as postgres, the server-role path)
-- ==========================================
-- a131  Accepted, student1's email and program  -> the real link
-- a131r Rejected and a131p Pending, student2's email and program
-- a131m Accepted, student3's email, ANOTHER program -> program mismatch
-- a131w Accepted, another email, student2's program  -> email mismatch
do $$
declare v_id bigint;
begin
  insert into public.applications (first_name, last_name, email, program_id)
  values ('Ana', 'Reyes', current_setting('app.s1email'), current_setting('app.s1prog')::bigint) returning application_id into v_id;
  perform set_config('app.a131', v_id::text, true);
  update public.applications set status = 'Accepted', reviewed_by = current_setting('app.reg')::uuid where application_id = v_id;

  insert into public.applications (first_name, last_name, email, program_id)
  values ('Ben', 'Santos', current_setting('app.s2email'), current_setting('app.s2prog')::bigint) returning application_id into v_id;
  perform set_config('app.a131r', v_id::text, true);
  update public.applications set status = 'Rejected', remarks = 'TC-131', reviewed_by = current_setting('app.reg')::uuid
  where application_id = v_id;

  insert into public.applications (first_name, last_name, email, program_id)
  values ('Ben', 'Santos', current_setting('app.s2email'), current_setting('app.s2prog')::bigint) returning application_id into v_id;
  perform set_config('app.a131p', v_id::text, true);

  insert into public.applications (first_name, last_name, email, program_id)
  values ('Carla', 'Mendoza', current_setting('app.s3email'), current_setting('app.prog_other3')::bigint) returning application_id into v_id;
  perform set_config('app.a131m', v_id::text, true);
  update public.applications set status = 'Accepted', reviewed_by = current_setting('app.reg')::uuid where application_id = v_id;

  insert into public.applications (first_name, last_name, email, program_id)
  values ('Tc', 'Wrong', 'tc131-wrong@applicant.test', current_setting('app.s2prog')::bigint) returning application_id into v_id;
  perform set_config('app.a131w', v_id::text, true);
  update public.applications set status = 'Accepted', reviewed_by = current_setting('app.reg')::uuid where application_id = v_id;

  perform set_config('app.c131_setup', 'ok', true);
exception when others then
  perform set_config('app.c131_setup', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
  perform set_config('app.a131', coalesce(nullif(current_setting('app.a131', true), ''), '0'), true);
end $$;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1,  'c131_pending',   $q$update public.applications set student_id = current_setting('app.s2')::uuid
                              where application_id = current_setting('app.a131p')::bigint$q$),
    (2,  'c131_rejected',  $q$update public.applications set student_id = current_setting('app.s2')::uuid
                              where application_id = current_setting('app.a131r')::bigint$q$),
    (3,  'c131_bad_email', $q$update public.applications set student_id = current_setting('app.s2')::uuid
                              where application_id = current_setting('app.a131w')::bigint$q$),
    (4,  'c131_bad_prog',  $q$update public.applications set student_id = current_setting('app.s3')::uuid
                              where application_id = current_setting('app.a131m')::bigint$q$),
    (5,  'c131_missing',   $q$update public.applications set student_id = '00000000-0000-4000-8000-000000000131'
                              where application_id = current_setting('app.a131')::bigint$q$),
    (6,  'c131_time_only', $q$update public.applications set provisioned_at = now()
                              where application_id = current_setting('app.a131')::bigint$q$),
    (7,  'c131_link',      $q$update public.applications set student_id = current_setting('app.s1')::uuid, provisioned_at = '2000-01-01'
                              where application_id = current_setting('app.a131')::bigint$q$),
    (8,  'c131_relink',    $q$update public.applications set student_id = current_setting('app.s2')::uuid
                              where application_id = current_setting('app.a131')::bigint$q$),
    (9,  'c131_retime',    $q$update public.applications set provisioned_at = '2001-01-01'
                              where application_id = current_setting('app.a131')::bigint$q$),
    (10, 'c131_noop',      $q$update public.applications set status = status
                              where application_id = current_setting('app.a131')::bigint$q$)
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
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c131_reg', 'reg', $q$update public.applications set student_id = current_setting('app.s3')::uuid
                             where application_id = current_setting('app.a131m')::bigint$q$)
  ) as t(ord, label, who, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
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
select set_config('request.jwt.claims', '', true);
select set_config('app.r131', format('setup [%s], pending [%s], rejected [%s], bad_email [%s], bad_program [%s], missing [%s], time_only [%s], link [%s], relink [%s], retime [%s], noop [%s], registrar [%s], row [%s], audit_ok %s, others_unlinked %s -> %s',
  current_setting('app.c131_setup'), current_setting('app.c131_pending'), current_setting('app.c131_rejected'),
  current_setting('app.c131_bad_email'), current_setting('app.c131_bad_prog'), current_setting('app.c131_missing'),
  current_setting('app.c131_time_only'), current_setting('app.c131_link'), current_setting('app.c131_relink'),
  current_setting('app.c131_retime'), current_setting('app.c131_noop'), current_setting('app.c131_reg'),
  coalesce((select a.status || ', student_is_s1 ' || (a.student_id::text = current_setting('app.s1'))
                   || ', provisioned_now ' || (a.provisioned_at = now())
              from public.applications a where a.application_id = current_setting('app.a131')::bigint), 'none'),
  coalesce((select count(*) = 1 and bool_and(l.action = 'UPDATE' and l.actor_id is null
                                         and l.old_data ->> 'student_id' is null
                                         and l.new_data ->> 'student_id' = current_setting('app.s1'))
              from public.audit_logs l
             where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'applications'
               and l.record_id = current_setting('app.a131')), false),
  (select count(*) = 4 from public.applications
    where application_id in (current_setting('app.a131r')::bigint, current_setting('app.a131p')::bigint,
                             current_setting('app.a131m')::bigint, current_setting('app.a131w')::bigint)
      and student_id is null and provisioned_at is null),
  case when current_setting('app.c131_setup') = 'ok'
        and current_setting('app.c131_pending') = 'ERR [P0001]: bad decision: application ' || current_setting('app.a131p') || ' must be Accepted before an account is linked'
        and current_setting('app.c131_rejected') like 'ERR [P0001]: bad decision: application ' || current_setting('app.a131r') || ' is Rejected; only an Accepted application%'
        and current_setting('app.c131_bad_email') like 'ERR [P0001]: bad decision: student % does not match application ' || current_setting('app.a131w') || ' %'
        and current_setting('app.c131_bad_prog') like 'ERR [P0001]: bad decision: student % does not match application ' || current_setting('app.a131m') || ' %'
        and current_setting('app.c131_missing') like 'ERR [P0001]: bad decision: student % does not exist%'
        and current_setting('app.c131_time_only') like 'ERR [P0001]: bad decision:%only the one-time account link%'
        and current_setting('app.c131_link') = 'rows 1'
        and current_setting('app.c131_relink') like 'ERR [P0001]: bad decision:%already linked%'
        and current_setting('app.c131_retime') like 'ERR [P0001]: bad decision:%already linked%'
        and current_setting('app.c131_noop') like 'ERR [P0001]: bad decision:%already linked%'
        and current_setting('app.c131_reg') like 'ERR [42501]: permission denied%'
        and coalesce((select a.status = 'Accepted' and a.student_id::text = current_setting('app.s1') and a.provisioned_at = now()
                        from public.applications a where a.application_id = current_setting('app.a131')::bigint), false)
        and coalesce((select count(*) = 1 and bool_and(l.action = 'UPDATE' and l.actor_id is null
                                                   and l.old_data ->> 'student_id' is null
                                                   and l.new_data ->> 'student_id' = current_setting('app.s1'))
                        from public.audit_logs l
                       where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'applications'
                         and l.record_id = current_setting('app.a131')), false)
        and (select count(*) = 4 from public.applications
              where application_id in (current_setting('app.a131r')::bigint, current_setting('app.a131p')::bigint,
                                       current_setting('app.a131m')::bigint, current_setting('app.a131w')::bigint)
                and student_id is null and provisioned_at is null)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 11. TC-132: roles and direct table access
-- ==========================================
select set_config('app.t132_test_rows', (select count(*)::text from public.applications where email like '%@applicant.test'), true);
set local role authenticated;
do $$
declare r record; n bigint; v_res text;
begin
  for r in
    select w.who, s.ord, s.label, s.stmt
    from (values ('s1'), ('cash'), ('dept'), ('adm'), ('reg')) as w(who)
    cross join (values
      (1, 'select', $q$select * from public.applications where email like '%@applicant.test'$q$),
      (2, 'update', $q$update public.applications set status = 'Rejected', remarks = 'TC-132'
                       where application_id = current_setting('app.a130c')::bigint$q$),
      (3, 'insert', $q$insert into public.applications (first_name, last_name, email, program_id)
                       values ('Tc', 'OneThreeTwo', 'tc132@applicant.test', current_setting('app.s1prog')::bigint)$q$),
      (4, 'delete', $q$delete from public.applications where application_id = current_setting('app.a130c')::bigint$q$)
    ) as s(ord, label, stmt)
    where not (w.who = 'reg' and s.label = 'update')
    order by w.who, s.ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'permission denied%' then 'denied' else 'ERR [' || sqlstate || ']: ' || sqlerrm end;
    end;
    perform set_config('app.t132_' || r.who,
      coalesce(nullif(current_setting('app.t132_' || r.who, true), '') || ', ', '') || r.label || ' ' || v_res, true);
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
declare r record; n bigint; v_res text; v_out text := '';
begin
  for r in select * from (values
    (1, 'select',   $q$select * from public.applications$q$),
    (2, 'insert',   $q$insert into public.applications (first_name, last_name, email, program_id)
                       values ('Tc', 'OneThreeTwo', 'tc132@applicant.test', current_setting('app.s1prog')::bigint)$q$),
    (3, 'update',   $q$update public.applications set status = 'Accepted' where application_id = current_setting('app.a130c')::bigint$q$),
    (4, 'delete',   $q$delete from public.applications$q$),
    (5, 'programs', $q$select * from public.programs$q$),
    (6, 'sequence', $q$select nextval('public.student_number_seq')$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'ALLOWED rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'permission denied%' then 'denied' else 'ERR [' || sqlstate || ']: ' || sqlerrm end;
    end;
    v_out := v_out || case when v_out = '' then '' else ', ' end || r.label || ' ' || v_res;
  end loop;
  perform set_config('app.t132_anon', v_out, true);
end $$;
reset role;
select set_config('app.r132', format('student [%s], cashier [%s], department [%s], admin [%s], registrar [%s] (test rows %s), anon [%s], a130c [%s] -> %s',
  current_setting('app.t132_s1'), current_setting('app.t132_cash'), current_setting('app.t132_dept'),
  current_setting('app.t132_adm'), current_setting('app.t132_reg'), current_setting('app.t132_test_rows'),
  current_setting('app.t132_anon'),
  coalesce((select status from public.applications where application_id = current_setting('app.a130c')::bigint), 'none'),
  case when current_setting('app.t132_s1') = 'select rows 0, update rows 0, insert denied, delete denied'
        and current_setting('app.t132_cash') = 'select rows 0, update rows 0, insert denied, delete denied'
        and current_setting('app.t132_dept') = 'select rows 0, update rows 0, insert denied, delete denied'
        and current_setting('app.t132_adm') = 'select rows 0, update rows 0, insert denied, delete denied'
        and current_setting('app.t132_reg') = 'select rows ' || current_setting('app.t132_test_rows') || ', insert denied, delete denied'
        and current_setting('app.t132_test_rows')::bigint > 0
        and current_setting('app.t132_anon') = 'select denied, insert denied, update denied, delete denied, programs denied, sequence denied'
        and coalesce((select status = 'Pending' from public.applications where application_id = current_setting('app.a130c')::bigint), false)
        and not exists (select 1 from public.applications where email = 'tc132@applicant.test')
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 12. TC-133: next_student_number()
-- ==========================================
-- The number after the current sequence position is given to student3 for this test (rolled
-- back), so the function must skip it. The sequence is put back to the saved state at the end.
set local role anon;
do $$
begin
  perform public.next_student_number();
  perform set_config('app.c133_anon', 'ALLOWED', true);
exception when others then
  perform set_config('app.c133_anon', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
do $$
begin
  perform public.next_student_number();
  perform set_config('app.c133_reg', 'ALLOWED', true);
exception when others then
  perform set_config('app.c133_reg', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.t133_year', to_char(now() at time zone 'Asia/Manila', 'YYYY'), true);
select set_config('app.t133_max', (select coalesce(max(substring(s.student_number::text from '^[0-9]{4}-([0-9]{1,15})$')::bigint), 0)::text
                                     from public.students s), true);
select set_config('app.t133_last', (select q.last_value::text from public.student_number_seq q), true);
select set_config('app.t133_called', (select q.is_called::text from public.student_number_seq q), true);
select set_config('app.t133_k', (select case when q.is_called then q.last_value else q.last_value - 1 end::text
                                   from public.student_number_seq q), true);
do $$
declare
  v_k    bigint := current_setting('app.t133_k')::bigint;
  v_take text;
  v_want text;
begin
  v_take := current_setting('app.t133_year') || '-' || case when v_k + 1 < 10000 then lpad((v_k + 1)::text, 4, '0') else (v_k + 1)::text end;
  v_want := current_setting('app.t133_year') || '-' || case when v_k + 2 < 10000 then lpad((v_k + 2)::text, 4, '0') else (v_k + 2)::text end;
  perform set_config('app.t133_take', v_take, true);
  perform set_config('app.t133_want', v_want, true);
  update public.students set student_number = v_take where student_id = current_setting('app.s3')::uuid;
  perform set_config('app.t133_got', public.next_student_number(), true);
exception when others then
  perform set_config('app.t133_got', 'ERR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
select setval('public.student_number_seq', current_setting('app.t133_last')::bigint, current_setting('app.t133_called')::boolean);
select set_config('app.r133', format('anon [%s], registrar [%s], taken [%s], got [%s], expected [%s], highest_before %s, sequence_restored %s, server_role_can_execute %s -> %s',
  current_setting('app.c133_anon'), current_setting('app.c133_reg'), current_setting('app.t133_take'),
  current_setting('app.t133_got'), current_setting('app.t133_want'), current_setting('app.t133_max'),
  (select q.last_value::text = current_setting('app.t133_last') and q.is_called::text = current_setting('app.t133_called')
     from public.student_number_seq q),
  exists (select 1 from pg_roles r
           where r.rolbypassrls and not r.rolsuper and r.rolname <> current_user
             and has_function_privilege(r.oid, 'public.next_student_number()', 'EXECUTE')),
  case when current_setting('app.c133_anon') like 'ERR [42501]: permission denied%'
        and current_setting('app.c133_reg') like 'ERR [42501]: permission denied%'
        and current_setting('app.t133_got') = current_setting('app.t133_want')
        and current_setting('app.t133_got') ~ ('^' || current_setting('app.t133_year') || '-[0-9]{4,}$')
        and substring(current_setting('app.t133_got') from '-([0-9]+)$')::bigint > greatest(current_setting('app.t133_max')::bigint, 3)
        and (select q.last_value::text = current_setting('app.t133_last') and q.is_called::text = current_setting('app.t133_called')
               from public.student_number_seq q)
        and exists (select 1 from pg_roles r
                     where r.rolbypassrls and not r.rolsuper and r.rolname <> current_user
                       and has_function_privilege(r.oid, 'public.next_student_number()', 'EXECUTE'))
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 13. TC-134: anon cannot call anything else
-- ==========================================
set local role anon;
do $$
declare r record; v_out text := '';
begin
  for r in select * from (values
    (1, 'settings', $q$select private.application_settings()$q$),
    (2, 'name',     $q$select private.application_name('Juan', 'first_name')$q$),
    (3, 'email',    $q$select private.application_email('tc134@applicant.test')$q$),
    (4, 'mobile',   $q$select private.application_mobile('09171234567')$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label || ' ALLOWED';
    exception when others then
      v_out := v_out || case when v_out = '' then '' else ', ' end || r.label
             || case when sqlerrm like 'permission denied%' then ' denied' else ' ERROR ' || sqlstate end;
    end;
  end loop;
  perform set_config('app.t134_anon', v_out, true);
end $$;
reset role;
select set_config('app.t134_list', coalesce((select string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')', ', ' order by p.proname)
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and has_function_privilege('anon', p.oid, 'EXECUTE')
    and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass
                    and d.objid = p.oid and d.deptype = 'e')), ''), true);
select set_config('app.r134', format('anon calls [%s], anon-executable in public [%s], trigger_fn_anon_or_public %s -> %s',
  current_setting('app.t134_anon'), current_setting('app.t134_list'),
  (select has_function_privilege('anon', p.oid, 'EXECUTE')
          or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
     from pg_proc p where p.oid = to_regprocedure('private.require_application_rules()')),
  case when current_setting('app.t134_anon') = 'settings denied, name denied, email denied, mobile denied'
        and current_setting('app.t134_list') = 'check_login_lockout(text), list_programs(), record_login_attempt(text, boolean, inet), submit_application(text, text, text, text, bigint)'
        and not (select has_function_privilege('anon', p.oid, 'EXECUTE')
                        or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
                   from pg_proc p where p.oid = to_regprocedure('private.require_application_rules()'))
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 14. TC-135: flood valve (hourly cap)
-- ==========================================
-- Fill the last hour up to the cap as postgres (through the trigger, so submitted_at =
-- now()), then anon submits.
select set_config('app.t135_cap', (select s.max_per_hour::text from private.application_settings() s), true);
insert into public.applications (first_name, last_name, email, program_id)
select 'Flood', 'Test', 'tc135-' || g || '@applicant.test', current_setting('app.s1prog')::bigint
from generate_series(1, greatest(current_setting('app.t135_cap')::bigint
                                 - (select count(*) from public.applications where submitted_at > now() - interval '1 hour'), 0)) g;
select set_config('app.t135_hour_before', (select count(*)::text from public.applications
                                             where submitted_at > now() - interval '1 hour'), true);
set local role anon;
do $$
declare r record; n bigint;
begin
  for r in select * from (values
    (1, 'c135_fresh',   $q$select public.submit_application('Tc', 'Flood', 'tc135-new@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (2, 'c135_dup',     $q$select public.submit_application('Tc', 'Flood', 'tc135-1@applicant.test', null, current_setting('app.s1prog')::bigint)$q$),
    (3, 'c135_account', $q$select public.submit_application('Ana', 'Reyes', current_setting('app.s1email'), null, current_setting('app.s1prog')::bigint)$q$),
    (4, 'c135_invalid', $q$select public.submit_application('Tc', 'Flood', 'not-an-email', null, current_setting('app.s1prog')::bigint)$q$)
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
select set_config('app.r135', format('cap %s, last_hour %s, fresh [%s], duplicate [%s], existing_account [%s], invalid [%s], rows_added %s -> %s',
  current_setting('app.t135_cap'), current_setting('app.t135_hour_before'),
  current_setting('app.c135_fresh'), current_setting('app.c135_dup'), current_setting('app.c135_account'),
  current_setting('app.c135_invalid'),
  (select count(*) from public.applications where submitted_at > now() - interval '1 hour') - current_setting('app.t135_hour_before')::bigint,
  case when current_setting('app.t135_hour_before')::bigint >= current_setting('app.t135_cap')::bigint
        and current_setting('app.c135_fresh') like 'ERR [P0001]: try later:%'
        and current_setting('app.c135_dup') = current_setting('app.c135_fresh')
        and current_setting('app.c135_account') = current_setting('app.c135_fresh')
        and current_setting('app.c135_invalid') like 'ERR [22023]: invalid application: email%'
        and (select count(*) from public.applications where submitted_at > now() - interval '1 hour')
            = current_setting('app.t135_hour_before')::bigint
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- Result: ONE row
-- ==========================================
select (current_setting('app.r123') like '%-> OK' and current_setting('app.r124') like '%-> OK'
        and current_setting('app.r125') like '%-> OK' and current_setting('app.r126') like '%-> OK'
        and current_setting('app.r127') like '%-> OK' and current_setting('app.r128') like '%-> OK'
        and current_setting('app.r129') like '%-> OK' and current_setting('app.r130') like '%-> OK'
        and current_setting('app.r131') like '%-> OK' and current_setting('app.r132') like '%-> OK'
        and current_setting('app.r133') like '%-> OK' and current_setting('app.r134') like '%-> OK'
        and current_setting('app.r135') like '%-> OK') as all_ok,
  current_setting('app.r123') as tc123, current_setting('app.r124') as tc124, current_setting('app.r125') as tc125,
  current_setting('app.r126') as tc126, current_setting('app.r127') as tc127, current_setting('app.r128') as tc128,
  current_setting('app.r129') as tc129, current_setting('app.r130') as tc130, current_setting('app.r131') as tc131,
  current_setting('app.r132') as tc132, current_setting('app.r133') as tc133, current_setting('app.r134') as tc134,
  current_setting('app.r135') as tc135;

rollback;
