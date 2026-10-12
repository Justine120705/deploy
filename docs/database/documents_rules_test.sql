-- ==========================================
-- TESTS FOR documents_rules.sql (GitHub issue #93): TC-95 to TC-108
-- ==========================================
-- One script, one transaction that ends in ROLLBACK, ONE result row. To run the change AND
-- these tests together (before the change is live), use
-- docs/database/documents_rules_rehearsal.sql instead (TC-95R); its test part is this file.
--
-- How to run (AFTER documents_rules.sql is live): Supabase SQL editor, as postgres, a new
-- tab. Paste the whole file (from "begin;" to "rollback;") and click Run on the whole tab,
-- never a selection. Nothing is committed. If the script stops with an error, run
-- "rollback;" as its own query and send the error back.
--
-- Rules (same as the other test files):
--   - Roles are impersonated with the real seed accounts (*@pnc.test, looked up by e-mail
--     as postgres): "set local role authenticated" (or anon) and request.jwt.claims =
--     {"sub": <id>, "role": "authenticated"} via set_config(..., true). After every
--     impersonated step the script goes back to postgres AND clears request.jwt.claims,
--     so "postgres" always means "no user JWT" (auth.uid() NULL).
--   - No temporary GRANT except the one inside TC-104 (a column grant that is revoked
--     again in the same case, to prove the trigger and not only the grant protects
--     processed_by / processed_at). Everything else uses the real grants.
--   - Own data: every request the cases change is created here as postgres (undone by the
--     rollback); the seed requests are never touched. No SKIPPED results: a missing seed
--     account stops the setup with "TC setup: ...".
--   - Expected errors are caught inside do blocks and shown as text:
--       "blocked [P0001]: bad status change: ..." = trigger require_document_status_flow
--       "denied: ..."                             = permission denied (grants)
--       "rls: ..."                                = new row violates row-level security
--       "rows N"                                  = the statement ran and changed N rows
--     Every cell ends in "-> OK" or "-> FAIL"; all_ok is true only if every cell is OK.
--     (Booleans inside the cells may print as t / f.)
--
-- Status: NOT RUN YET.

begin;

-- ==========================================
-- 1. Accounts, ids and throwaway requests (as postgres, no user JWT)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.reg',  coalesce((select id::text from auth.users where email = 'registrar@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.dt',   coalesce((select min(document_type_id)::text from public.document_types), ''), true);
select set_config('app.dt_count', (select count(*)::text from public.document_types), true);
select set_config('app.year', to_char(now(), 'YYYY'), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.reg'),
            current_setting('app.adm'), current_setting('app.cash'), current_setting('app.dt'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or (select count(*) from public.profiles p join public.roles r on r.role_id = p.role_id
          where p.is_active and (p.profile_id::text, r.role_name::text) in (
            (current_setting('app.s1'), 'Student'), (current_setting('app.s2'), 'Student'),
            (current_setting('app.reg'), 'Registrar'), (current_setting('app.adm'), 'Admin'),
            (current_setting('app.cash'), 'Cashier'))) <> 5 then
    raise exception 'TC setup: seed account, student or document type missing, or a seed account is not active with its role (s1 [%], s2 [%], reg [%], adm [%], cash [%], dt [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.reg'),
      current_setting('app.adm'), current_setting('app.cash'), current_setting('app.dt');
  end if;
end $$;

-- Audit mark: every audit row with a higher log_id was written by this script.
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);

-- Throwaway requests (inserted as the owner, so any status can be set directly):
--   q_pend, q_proc, q_ready, q_rel, q_rejd  Student 1, one per status (illegal / final cases)
--   q_flow                                  Student 1, Pending (full legal flow)
--   q_rej1 (Pending), q_rej2 (Processing)   Student 1 (the two Rejected steps)
--   q_note                                  Student 1, Processing (remarks-only edit)
--   q_forge                                 Student 1, Pending (forgery case)
--   q_s2                                    Student 2, Pending (read isolation)
with r as (insert into public.document_requests (student_id, document_type_id, purpose)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC pend') returning request_id)
select set_config('app.q_pend', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose, status, processed_by, processed_at)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC proc', 'Processing',
                   current_setting('app.reg')::uuid, now()) returning request_id)
select set_config('app.q_proc', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose, status, processed_by, processed_at)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC ready', 'Ready',
                   current_setting('app.reg')::uuid, now()) returning request_id)
select set_config('app.q_ready', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose, status, processed_by, processed_at)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC rel', 'Released',
                   current_setting('app.reg')::uuid, now()) returning request_id)
select set_config('app.q_rel', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose, status, processed_by, processed_at, remarks)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC rejd', 'Rejected',
                   current_setting('app.reg')::uuid, now(), 'TC setup') returning request_id)
select set_config('app.q_rejd', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC flow') returning request_id)
select set_config('app.q_flow', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC rej1') returning request_id)
select set_config('app.q_rej1', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose, status, processed_by, processed_at)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC rej2', 'Processing',
                   current_setting('app.reg')::uuid, now()) returning request_id)
select set_config('app.q_rej2', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose, status, processed_by, processed_at)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC note', 'Processing',
                   current_setting('app.reg')::uuid, now() - interval '1 day') returning request_id)
select set_config('app.q_note', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose)
           values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC forge') returning request_id)
select set_config('app.q_forge', request_id::text, true) from r;
with r as (insert into public.document_requests (student_id, document_type_id, purpose)
           values (current_setting('app.s2')::uuid, current_setting('app.dt')::bigint, 'TC s2') returning request_id)
select set_config('app.q_s2', request_id::text, true) from r;

-- Defaults for values that a failing step might not set.
select set_config('app.t96', 'not run', true);
select set_config('app.q96a', '0', true);
select set_config('app.q96b', '0', true);

-- ==========================================
-- 2. TC-95: installed as intended (catalog, as postgres)
-- ==========================================
-- Expected: order "guard_immutable_columns (BEFORE) > require_document_status_flow (BEFORE)
-- > audit_log (AFTER)", trigger "O, type 19, when false", function SECURITY INVOKER with an
-- empty search_path, anon/PUBLIC cannot execute, authenticated can; anon no privilege on
-- the 2 tables and the sequence; authenticated: SELECT only at table level on
-- document_requests, the 6 column grants, SELECT on document_types, USAGE only on the
-- sequence; the 3 policies unchanged.
select set_config('app.r95', (select format('order [%s], trigger [%s], invoker %s, config [%s], fn anon %s / auth %s / public %s, anon_any %s, req sel %s / table_writes %s, columns [%s], types_sel %s, seq usage %s / select_or_update %s, policies [%s] -> %s',
    x.ord, x.trg, x.invoker, x.config, x.fn_anon, x.fn_auth, x.fn_public, x.anon_any, x.req_sel, x.req_writes,
    x.cols, x.types_sel, x.seq_usage, x.seq_other, x.pols,
    case when x.ord = 'guard_immutable_columns (BEFORE) > require_document_status_flow (BEFORE) > audit_log (AFTER)'
          and x.trg = 'O, type 19, when false'
          and x.invoker and x.config in ('search_path=""', 'search_path=''''')
          and not x.fn_anon and x.fn_auth and not x.fn_public and not x.anon_any
          and x.req_sel and not x.req_writes
          and x.cols = 'copies INSERT, document_type_id INSERT, purpose INSERT, student_id INSERT, remarks UPDATE, status UPDATE'
          and x.types_sel and x.seq_usage and not x.seq_other
          and x.pols = 'docreq_read SELECT, docreq_registrar_process UPDATE, docreq_student_submit INSERT'
         then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(tg.tgname::text || ' (' || case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end || ')', ' > '
                       order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.document_requests'::regclass and not tg.tgisinternal) as ord,
    (select tg.tgenabled::text || ', type ' || tg.tgtype || ', when ' || case when tg.tgqual is not null then 'true' else 'false' end
       from pg_trigger tg
      where tg.tgrelid = 'public.document_requests'::regclass and tg.tgname = 'require_document_status_flow'
        and tg.tgfoid = to_regprocedure('private.require_document_status_flow()')) as trg,
    coalesce((select not p.prosecdef from pg_proc p where p.oid = to_regprocedure('private.require_document_status_flow()')), false) as invoker,
    (select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure('private.require_document_status_flow()')) as config,
    coalesce(has_function_privilege('anon', to_regprocedure('private.require_document_status_flow()'), 'EXECUTE'), true) as fn_anon,
    coalesce(has_function_privilege('authenticated', to_regprocedure('private.require_document_status_flow()'), 'EXECUTE'), false) as fn_auth,
    coalesce((select p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
                from pg_proc p where p.oid = to_regprocedure('private.require_document_status_flow()')), true) as fn_public,
    (has_table_privilege('anon', 'public.document_requests', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     or has_any_column_privilege('anon', 'public.document_requests', 'SELECT, INSERT, UPDATE, REFERENCES')
     or has_table_privilege('anon', 'public.document_types', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     or has_any_column_privilege('anon', 'public.document_types', 'SELECT, INSERT, UPDATE, REFERENCES')
     or has_sequence_privilege('anon', 'public.document_ticket_seq', 'USAGE, SELECT, UPDATE')) as anon_any,
    has_table_privilege('authenticated', 'public.document_requests', 'SELECT') as req_sel,
    has_table_privilege('authenticated', 'public.document_requests', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN') as req_writes,
    (select string_agg(a.attname::text || ' ' || x.privilege_type, ', ' order by x.privilege_type, a.attname::text)
       from pg_attribute a cross join lateral aclexplode(a.attacl) x
      where a.attrelid = 'public.document_requests'::regclass and a.attnum > 0 and not a.attisdropped
        and a.attacl is not null and x.grantee = 'authenticated'::regrole) as cols,
    has_table_privilege('authenticated', 'public.document_types', 'SELECT') as types_sel,
    has_sequence_privilege('authenticated', 'public.document_ticket_seq', 'USAGE') as seq_usage,
    has_sequence_privilege('authenticated', 'public.document_ticket_seq', 'SELECT, UPDATE') as seq_other,
    (select string_agg(p.policyname::text || ' ' || p.cmd, ', ' order by p.policyname)
       from pg_policies p where p.schemaname = 'public' and p.tablename = 'document_requests') as pols) x), true);

-- ==========================================
-- 3. TC-96: the student submits own requests; the database makes the ticket
-- ==========================================
-- Expected: insert "rows 2"; both tickets DR-<this year>-<6+ digits>, different, unique in
-- the table, the second one higher; student_id = Student 1, status Pending, processed_*
-- NULL, requested_at = now(); copies 2 and 1 as sent.
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id1 bigint; v_id2 bigint;
begin
  insert into public.document_requests (student_id, document_type_id, purpose, copies)
  values (auth.uid(), current_setting('app.dt')::bigint, 'TC-96 first', 2)
  returning request_id into v_id1;
  insert into public.document_requests (student_id, document_type_id, purpose, copies)
  values (auth.uid(), current_setting('app.dt')::bigint, 'TC-96 second', 1)
  returning request_id into v_id2;
  perform set_config('app.q96a', v_id1::text, true);
  perform set_config('app.q96b', v_id2::text, true);
  perform set_config('app.t96', 'rows 2', true);
exception when others then
  perform set_config('app.t96',
    case when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r96', (select format('insert [%s], tickets [%s | %s], format_ok %s, distinct_unique %s, increasing %s, own_pending_unprocessed %s, requested_now %s, copies [%s] -> %s',
    current_setting('app.t96'), x.t1, x.t2, x.fmt, x.uniq, x.incr, x.own, x.req, x.copies,
    case when current_setting('app.t96') = 'rows 2' and x.fmt and x.uniq and x.incr and x.own and x.req
          and x.copies = '2,1' then 'OK' else 'FAIL' end)
  from (select
    (select ticket_number from public.document_requests where request_id = current_setting('app.q96a')::bigint) as t1,
    (select ticket_number from public.document_requests where request_id = current_setting('app.q96b')::bigint) as t2,
    coalesce((select bool_and(d.ticket_number ~ ('^DR-' || current_setting('app.year') || '-[0-9]{6,}$')) and count(*) = 2
                from public.document_requests d
               where d.request_id in (current_setting('app.q96a')::bigint, current_setting('app.q96b')::bigint)), false) as fmt,
    coalesce((select count(*) = 2 from public.document_requests d
               where d.ticket_number in (select d2.ticket_number from public.document_requests d2
                                          where d2.request_id in (current_setting('app.q96a')::bigint, current_setting('app.q96b')::bigint))), false) as uniq,
    coalesce((select substring(b.ticket_number from '[0-9]+$')::bigint > substring(a.ticket_number from '[0-9]+$')::bigint
                from public.document_requests a, public.document_requests b
               where a.request_id = current_setting('app.q96a')::bigint and b.request_id = current_setting('app.q96b')::bigint), false) as incr,
    coalesce((select bool_and(d.student_id::text = current_setting('app.s1') and d.status = 'Pending'
                              and d.processed_by is null and d.processed_at is null) and count(*) = 2
                from public.document_requests d
               where d.request_id in (current_setting('app.q96a')::bigint, current_setting('app.q96b')::bigint)), false) as own,
    coalesce((select bool_and(d.requested_at = now()) and count(*) = 2 from public.document_requests d
               where d.request_id in (current_setting('app.q96a')::bigint, current_setting('app.q96b')::bigint)), false) as req,
    coalesce((select string_agg(d.copies::text, ',' order by d.request_id) from public.document_requests d
               where d.request_id in (current_setting('app.q96a')::bigint, current_setting('app.q96b')::bigint)), '') as copies) x), true);

-- ==========================================
-- 4. TC-97: the student cannot choose the ticket (or status, dates, processed_*)
-- ==========================================
-- Expected: every statement "denied: permission denied for ..." (no column grant; setval
-- needs UPDATE on the sequence); no row with the chosen ticket exists.
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 's1', 'ticket',       'denied: %', $q$insert into public.document_requests (student_id, document_type_id, purpose, ticket_number)
                                             values (auth.uid(), current_setting('app.dt')::bigint, 'TC-97', 'DR-1999-000001')$q$),
    (2, 's1', 'status',       'denied: %', $q$insert into public.document_requests (student_id, document_type_id, purpose, status)
                                             values (auth.uid(), current_setting('app.dt')::bigint, 'TC-97', 'Released')$q$),
    (3, 's1', 'processed',    'denied: %', $q$insert into public.document_requests (student_id, document_type_id, purpose, processed_by, processed_at)
                                             values (auth.uid(), current_setting('app.dt')::bigint, 'TC-97', auth.uid(), now())$q$),
    (4, 's1', 'requested_at', 'denied: %', $q$insert into public.document_requests (student_id, document_type_id, purpose, requested_at)
                                             values (auth.uid(), current_setting('app.dt')::bigint, 'TC-97', '2000-01-01T00:00:00Z')$q$),
    (5, 's1', 'setval',       'denied: %', $q$select setval('public.document_ticket_seq', 1)$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t97', v_cell, true);
  perform set_config('app.t97_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r97', format('%s, chosen_ticket_rows %s, tc97_rows %s -> %s',
  current_setting('app.t97'),
  (select count(*) from public.document_requests where ticket_number = 'DR-1999-000001'),
  (select count(*) from public.document_requests where purpose = 'TC-97'),
  case when current_setting('app.t97_ok')::boolean
        and (select count(*) from public.document_requests where ticket_number = 'DR-1999-000001') = 0
        and (select count(*) from public.document_requests where purpose = 'TC-97') = 0
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 5. TC-98: no request for another student; only a Student may submit
-- ==========================================
-- Expected: Student 1 for Student 2, the Registrar and the Admin (for Student 1) each
-- "rls: new row violates row-level security policy ..."; no TC-98 row exists.
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 's1',  'student_for_s2', 'rls: %', $q$insert into public.document_requests (student_id, document_type_id, purpose)
                                             values (current_setting('app.s2')::uuid, current_setting('app.dt')::bigint, 'TC-98')$q$),
    (2, 'reg', 'registrar',      'rls: %', $q$insert into public.document_requests (student_id, document_type_id, purpose)
                                             values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC-98')$q$),
    (3, 'adm', 'admin',          'rls: %', $q$insert into public.document_requests (student_id, document_type_id, purpose)
                                             values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC-98')$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t98', v_cell, true);
  perform set_config('app.t98_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r98', format('%s, tc98_rows %s -> %s',
  current_setting('app.t98'),
  (select count(*) from public.document_requests where purpose = 'TC-98'),
  case when current_setting('app.t98_ok')::boolean
        and (select count(*) from public.document_requests where purpose = 'TC-98') = 0
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 6. TC-99: the student cannot change a request (status, remarks, other columns)
-- ==========================================
-- Expected: status and remarks "rows 0" (the Registrar-only policy hides the row from the
-- UPDATE, no error); ticket_number, purpose, processed_by "denied"; q_pend unchanged.
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 's1', 'status',       'rows 0',    $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_pend')::bigint$q$),
    (2, 's1', 'remarks',      'rows 0',    $q$update public.document_requests set remarks = 'TC-99' where request_id = current_setting('app.q_pend')::bigint$q$),
    (3, 's1', 'ticket',       'denied: %', $q$update public.document_requests set ticket_number = 'DR-1999-000002' where request_id = current_setting('app.q_pend')::bigint$q$),
    (4, 's1', 'purpose',      'denied: %', $q$update public.document_requests set purpose = 'TC-99' where request_id = current_setting('app.q_pend')::bigint$q$),
    (5, 's1', 'processed_by', 'denied: %', $q$update public.document_requests set processed_by = auth.uid() where request_id = current_setting('app.q_pend')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t99', v_cell, true);
  perform set_config('app.t99_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r99', format('%s, q_pend_unchanged %s -> %s',
  current_setting('app.t99'),
  coalesce((select status = 'Pending' and remarks is null and purpose = 'TC pend' and processed_by is null
              from public.document_requests where request_id = current_setting('app.q_pend')::bigint), false),
  case when current_setting('app.t99_ok')::boolean
        and coalesce((select status = 'Pending' and remarks is null and purpose = 'TC pend' and processed_by is null
                        from public.document_requests where request_id = current_setting('app.q_pend')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 7. TC-100: who sees which requests; everyone signed in sees the document types
-- ==========================================
-- Expected: Student 1 sees exactly own rows (count = own rows counted as postgres, 0 rows
-- of others, not q_s2); Student 2 does not see q_pend; the Registrar sees every row; the
-- Admin and the Cashier see none (docreq_read); every role sees every document type.
select set_config('app.n_all', (select count(*)::text from public.document_requests), true);
select set_config('app.n_s1', (select count(*)::text from public.document_requests
  where student_id::text = current_setting('app.s1')), true);
select set_config('app.t100', 'not run', true);
select set_config('app.t100_ok', 'false', true);
set local role authenticated;
do $$
declare
  s1_rows bigint; s1_not_own bigint; s1_sees_s2 bigint; s1_types bigint;
  s2_sees_s1 bigint; s2_not_own bigint;
  reg_rows bigint; adm_rows bigint; cash_rows bigint; reg_types bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
  select count(*), count(*) filter (where student_id is distinct from auth.uid()),
         count(*) filter (where request_id = current_setting('app.q_s2')::bigint)
    into s1_rows, s1_not_own, s1_sees_s2 from public.document_requests;
  select count(*) into s1_types from public.document_types;

  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('app.s2'), 'role', 'authenticated')::text, true);
  select count(*) filter (where request_id = current_setting('app.q_pend')::bigint),
         count(*) filter (where student_id is distinct from auth.uid())
    into s2_sees_s1, s2_not_own from public.document_requests;

  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('app.reg'), 'role', 'authenticated')::text, true);
  select count(*) into reg_rows from public.document_requests;
  select count(*) into reg_types from public.document_types;

  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('app.adm'), 'role', 'authenticated')::text, true);
  select count(*) into adm_rows from public.document_requests;

  perform set_config('request.jwt.claims', json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
  select count(*) into cash_rows from public.document_requests;

  perform set_config('app.t100', format('student1 rows %s / own %s, not_own %s, sees_s2 %s, types %s / %s; student2 sees_q_pend %s, not_own %s; registrar rows %s / %s, types %s; admin rows %s; cashier rows %s',
    s1_rows, current_setting('app.n_s1'), s1_not_own, s1_sees_s2, s1_types, current_setting('app.dt_count'),
    s2_sees_s1, s2_not_own, reg_rows, current_setting('app.n_all'), reg_types, adm_rows, cash_rows), true);
  perform set_config('app.t100_ok', (s1_rows = current_setting('app.n_s1')::bigint and s1_not_own = 0 and s1_sees_s2 = 0
    and s1_types = current_setting('app.dt_count')::bigint and s2_sees_s1 = 0 and s2_not_own = 0
    and reg_rows = current_setting('app.n_all')::bigint and reg_types = current_setting('app.dt_count')::bigint
    and adm_rows = 0 and cash_rows = 0)::text, true);
exception when others then
  perform set_config('app.t100', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
  perform set_config('app.t100_ok', 'false', true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r100', current_setting('app.t100') || ' -> '
  || case when current_setting('app.t100_ok')::boolean then 'OK' else 'FAIL' end, true);

-- ==========================================
-- 8. TC-101: the Registrar moves requests through the legal flow
-- ==========================================
-- Expected: every step "rows 1"; q_flow Released, q_rej1 Rejected with its remarks, q_rej2
-- Rejected, q_note still Processing with the new remarks, a remarks edit on Pending q_pend is refused; on all four processed_by = the
-- Registrar and processed_at = now() (set by the trigger; the Registrar never wrote them).
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'reg', 'flow_processing', 'rows 1', $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_flow')::bigint$q$),
    (2, 'reg', 'flow_ready',      'rows 1', $q$update public.document_requests set status = 'Ready' where request_id = current_setting('app.q_flow')::bigint$q$),
    (3, 'reg', 'flow_released',   'rows 1', $q$update public.document_requests set status = 'Released' where request_id = current_setting('app.q_flow')::bigint$q$),
    (4, 'reg', 'pending_reject',  'rows 1', $q$update public.document_requests set status = 'Rejected', remarks = 'TC-101 missing requirements' where request_id = current_setting('app.q_rej1')::bigint$q$),
    (5, 'reg', 'processing_reject','rows 1', $q$update public.document_requests set status = 'Rejected' where request_id = current_setting('app.q_rej2')::bigint$q$),
    (6, 'reg', 'remarks_only',    'rows 1', $q$update public.document_requests set remarks = 'TC-101 note' where request_id = current_setting('app.q_note')::bigint$q$),
    (7, 'reg', 'pending_remarks', 'blocked [P0001]: bad status change: remarks cannot be edited while request % is Pending%', $q$update public.document_requests set remarks = 'TC-101 nope' where request_id = current_setting('app.q_pend')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t101', v_cell, true);
  perform set_config('app.t101_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r101', (select format('%s, final [%s], stamped_by_registrar_now %s -> %s',
    current_setting('app.t101'), x.final, x.stamped,
    case when current_setting('app.t101_ok')::boolean
          and x.final = 'flow Released, rej1 Rejected (TC-101 missing requirements), rej2 Rejected, note Processing (TC-101 note)'
          and x.stamped then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(v.k || ' ' || d.status || coalesce(case when v.k in ('rej1', 'note') then ' (' || d.remarks || ')' end, ''), ', ' order by v.o)
       from (values (1, 'flow', 'app.q_flow'), (2, 'rej1', 'app.q_rej1'), (3, 'rej2', 'app.q_rej2'), (4, 'note', 'app.q_note')) v(o, k, s)
       join public.document_requests d on d.request_id = current_setting(v.s)::bigint) as final,
    coalesce((select bool_and(d.processed_by::text = current_setting('app.reg') and d.processed_at = now()) and count(*) = 4
                from public.document_requests d
               where d.request_id in (current_setting('app.q_flow')::bigint, current_setting('app.q_rej1')::bigint,
                                      current_setting('app.q_rej2')::bigint, current_setting('app.q_note')::bigint)), false) as stamped) x), true);

-- ==========================================
-- 9. TC-102: skipped steps and steps back are refused
-- ==========================================
-- Expected: every statement "blocked [P0001]: bad status change: <old> -> <new> is not
-- allowed ..."; q_pend, q_proc, q_ready keep their status and processed_by.
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'reg', 'pending_ready',      'blocked [P0001]: bad status change: Pending -> Ready is not allowed%',      $q$update public.document_requests set status = 'Ready' where request_id = current_setting('app.q_pend')::bigint$q$),
    (2, 'reg', 'pending_released',   'blocked [P0001]: bad status change: Pending -> Released is not allowed%',   $q$update public.document_requests set status = 'Released' where request_id = current_setting('app.q_pend')::bigint$q$),
    (3, 'reg', 'pending_bogus',      'blocked [P0001]: bad status change: Pending -> Bogus is not allowed%',      $q$update public.document_requests set status = 'Bogus' where request_id = current_setting('app.q_pend')::bigint$q$),
    (4, 'reg', 'processing_released','blocked [P0001]: bad status change: Processing -> Released is not allowed%',$q$update public.document_requests set status = 'Released' where request_id = current_setting('app.q_proc')::bigint$q$),
    (5, 'reg', 'processing_pending', 'blocked [P0001]: bad status change: Processing -> Pending is not allowed%', $q$update public.document_requests set status = 'Pending' where request_id = current_setting('app.q_proc')::bigint$q$),
    (6, 'reg', 'ready_pending',      'blocked [P0001]: bad status change: Ready -> Pending is not allowed%',      $q$update public.document_requests set status = 'Pending' where request_id = current_setting('app.q_ready')::bigint$q$),
    (7, 'reg', 'ready_processing',   'blocked [P0001]: bad status change: Ready -> Processing is not allowed%',   $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_ready')::bigint$q$),
    (8, 'reg', 'ready_rejected',     'blocked [P0001]: bad status change: Ready -> Rejected is not allowed%',     $q$update public.document_requests set status = 'Rejected' where request_id = current_setting('app.q_ready')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t102', v_cell, true);
  perform set_config('app.t102_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r102', (select format('%s, unchanged [%s] -> %s',
    current_setting('app.t102'), x.st,
    case when current_setting('app.t102_ok')::boolean and x.st = 'Pending/none, Processing/registrar, Ready/registrar'
         then 'OK' else 'FAIL' end)
  from (select string_agg(d.status || '/' || case when d.processed_by is null then 'none'
                                                  when d.processed_by::text = current_setting('app.reg') then 'registrar'
                                                  else 'other' end, ', ' order by v.o) as st
          from (values (1, 'app.q_pend'), (2, 'app.q_proc'), (3, 'app.q_ready')) v(o, s)
          join public.document_requests d on d.request_id = current_setting(v.s)::bigint) x), true);

-- ==========================================
-- 10. TC-103: Released and Rejected are final, for the Registrar and for postgres
-- ==========================================
-- Expected: every statement "blocked [P0001]: bad status change: request <id> is
-- <Released|Rejected> (final) ..." (also the remarks-only edits and the two postgres
-- statements); q_rel stays Released without remarks, q_rejd stays Rejected with "TC setup".
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'reg', 'released_ready',      'blocked [P0001]: bad status change: request % is Released (final)%', $q$update public.document_requests set status = 'Ready' where request_id = current_setting('app.q_rel')::bigint$q$),
    (2, 'reg', 'released_rejected',   'blocked [P0001]: bad status change: request % is Released (final)%', $q$update public.document_requests set status = 'Rejected' where request_id = current_setting('app.q_rel')::bigint$q$),
    (3, 'reg', 'released_remarks',    'blocked [P0001]: bad status change: request % is Released (final)%', $q$update public.document_requests set remarks = 'TC-103' where request_id = current_setting('app.q_rel')::bigint$q$),
    (4, 'reg', 'rejected_processing', 'blocked [P0001]: bad status change: request % is Rejected (final)%', $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_rejd')::bigint$q$),
    (5, 'reg', 'rejected_pending',    'blocked [P0001]: bad status change: request % is Rejected (final)%', $q$update public.document_requests set status = 'Pending' where request_id = current_setting('app.q_rejd')::bigint$q$),
    (6, 'reg', 'rejected_remarks',    'blocked [P0001]: bad status change: request % is Rejected (final)%', $q$update public.document_requests set remarks = 'TC-103' where request_id = current_setting('app.q_rejd')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t103', v_cell, true);
  perform set_config('app.t103_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- the same rule as postgres (no user JWT)
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'pg_released_processing', 'blocked [P0001]: bad status change: request % is Released (final)%', $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_rel')::bigint$q$),
    (2, 'pg_rejected_remarks',    'blocked [P0001]: bad status change: request % is Rejected (final)%', $q$update public.document_requests set remarks = 'TC-103 pg' where request_id = current_setting('app.q_rejd')::bigint$q$)
  ) as t(ord, label, expect, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t103_pg', v_cell, true);
  perform set_config('app.t103_pg_ok', v_ok::text, true);
end $$;
select set_config('app.r103', format('%s, %s, unchanged %s -> %s',
  current_setting('app.t103'), current_setting('app.t103_pg'),
  coalesce((select bool_and(case when d.request_id = current_setting('app.q_rel')::bigint
                                 then d.status = 'Released' and d.remarks is null
                                 else d.status = 'Rejected' and d.remarks = 'TC setup' end) and count(*) = 2
              from public.document_requests d
             where d.request_id in (current_setting('app.q_rel')::bigint, current_setting('app.q_rejd')::bigint)), false),
  case when current_setting('app.t103_ok')::boolean and current_setting('app.t103_pg_ok')::boolean
        and coalesce((select bool_and(case when d.request_id = current_setting('app.q_rel')::bigint
                                           then d.status = 'Released' and d.remarks is null
                                           else d.status = 'Rejected' and d.remarks = 'TC setup' end) and count(*) = 2
                        from public.document_requests d
                       where d.request_id in (current_setting('app.q_rel')::bigint, current_setting('app.q_rejd')::bigint)), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 11. TC-104: processed_by / processed_at cannot be forged
-- ==========================================
-- Part a (real grants): writing processed_by or processed_at is "denied".
-- Part b: a TEMPORARY column grant UPDATE (processed_by, processed_at) (revoked again
-- below) shows the trigger overrides them anyway: the status step with a forged
-- processed_by = Admin and processed_at = 2000-01-01 is "rows 1" but stores the Registrar
-- and now(); a forge without a status change is "rows 1" and changes nothing. After the
-- revoke the column grants are the 6 of TC-95 again.
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'reg', 'a_processed_by', 'denied: %', $q$update public.document_requests set status = 'Processing', processed_by = current_setting('app.adm')::uuid where request_id = current_setting('app.q_forge')::bigint$q$),
    (2, 'reg', 'a_processed_at', 'denied: %', $q$update public.document_requests set processed_at = '2000-01-01T00:00:00Z' where request_id = current_setting('app.q_forge')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t104a', v_cell, true);
  perform set_config('app.t104a_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
grant update (processed_by, processed_at) on public.document_requests to authenticated; -- temporary, revoked below
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'reg', 'b_status_and_forge', 'rows 1', $q$update public.document_requests set status = 'Processing', processed_by = current_setting('app.adm')::uuid,
                                                   processed_at = '2000-01-01T00:00:00Z' where request_id = current_setting('app.q_forge')::bigint$q$),
    (2, 'reg', 'b_forge_only',       'rows 1', $q$update public.document_requests set processed_by = current_setting('app.adm')::uuid,
                                                   processed_at = '2000-01-01T00:00:00Z' where request_id = current_setting('app.q_forge')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t104b', v_cell, true);
  perform set_config('app.t104b_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
revoke update (processed_by, processed_at) on public.document_requests from authenticated; -- end of the temporary grant
select set_config('app.r104', (select format('%s, %s, stored [%s], columns_after [%s] -> %s',
    current_setting('app.t104a'), current_setting('app.t104b'), x.stored, x.cols,
    case when current_setting('app.t104a_ok')::boolean and current_setting('app.t104b_ok')::boolean
          and x.stored = 'Processing, by registrar, at now'
          and x.cols = 'copies INSERT, document_type_id INSERT, purpose INSERT, student_id INSERT, remarks UPDATE, status UPDATE'
         then 'OK' else 'FAIL' end)
  from (select
    (select d.status || ', by ' || case when d.processed_by::text = current_setting('app.reg') then 'registrar'
                                        when d.processed_by::text = current_setting('app.adm') then 'ADMIN (forged)'
                                        else coalesce(d.processed_by::text, 'none') end
            || ', at ' || case when d.processed_at = now() then 'now' else coalesce(d.processed_at::text, 'none') end
       from public.document_requests d where d.request_id = current_setting('app.q_forge')::bigint) as stored,
    (select string_agg(a.attname::text || ' ' || x.privilege_type, ', ' order by x.privilege_type, a.attname::text)
       from pg_attribute a cross join lateral aclexplode(a.attacl) x
      where a.attrelid = 'public.document_requests'::regclass and a.attnum > 0 and not a.attisdropped
        and a.attacl is not null and x.grantee = 'authenticated'::regrole) as cols) x), true);

-- ==========================================
-- 12. TC-105: the Registrar can change only status and remarks
-- ==========================================
-- Expected: every statement "denied: permission denied for table document_requests";
-- q_pend unchanged.
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'reg', 'purpose',          'denied: %', $q$update public.document_requests set purpose = 'TC-105' where request_id = current_setting('app.q_pend')::bigint$q$),
    (2, 'reg', 'copies',           'denied: %', $q$update public.document_requests set copies = 5 where request_id = current_setting('app.q_pend')::bigint$q$),
    (3, 'reg', 'document_type_id', 'denied: %', $q$update public.document_requests set document_type_id = document_type_id where request_id = current_setting('app.q_pend')::bigint$q$),
    (4, 'reg', 'requested_at',     'denied: %', $q$update public.document_requests set requested_at = '2000-01-01T00:00:00Z' where request_id = current_setting('app.q_pend')::bigint$q$),
    (5, 'reg', 'student_id',       'denied: %', $q$update public.document_requests set student_id = current_setting('app.s2')::uuid where request_id = current_setting('app.q_pend')::bigint$q$),
    (6, 'reg', 'ticket_number',    'denied: %', $q$update public.document_requests set ticket_number = 'DR-1999-000003' where request_id = current_setting('app.q_pend')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t105', v_cell, true);
  perform set_config('app.t105_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r105', format('%s, q_pend_unchanged %s -> %s',
  current_setting('app.t105'),
  coalesce((select status = 'Pending' and purpose = 'TC pend' and copies = 1 and student_id::text = current_setting('app.s1')
              from public.document_requests where request_id = current_setting('app.q_pend')::bigint), false),
  case when current_setting('app.t105_ok')::boolean
        and coalesce((select status = 'Pending' and purpose = 'TC pend' and copies = 1 and student_id::text = current_setting('app.s1')
                        from public.document_requests where request_id = current_setting('app.q_pend')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 13. TC-106: anon gets nothing
-- ==========================================
-- Expected: every statement "denied: permission denied for table / sequence ...".
set local role anon;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 'select_requests', 'denied: %', $q$select count(*) from public.document_requests$q$),
    (2, 'select_types',    'denied: %', $q$select count(*) from public.document_types$q$),
    (3, 'insert',          'denied: %', $q$insert into public.document_requests (student_id, document_type_id, purpose)
                                          values (current_setting('app.s1')::uuid, current_setting('app.dt')::bigint, 'TC-106')$q$),
    (4, 'update',          'denied: %', $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_pend')::bigint$q$),
    (5, 'delete',          'denied: %', $q$delete from public.document_requests where request_id = current_setting('app.q_pend')::bigint$q$),
    (6, 'nextval',         'denied: %', $q$select nextval('public.document_ticket_seq')$q$)
  ) as t(ord, label, expect, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'permission denied%' then 'denied: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t106', v_cell, true);
  perform set_config('app.t106_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r106', current_setting('app.t106') || ' -> '
  || case when current_setting('app.t106_ok')::boolean then 'OK' else 'FAIL' end, true);

-- ==========================================
-- 14. TC-107: no DELETE for anybody; other roles cannot process
-- ==========================================
-- Expected: DELETE by Student 1 (own row), Registrar and Admin "denied"; the Admin's and
-- the Cashier's status update "rows 0" (policy USING hides the row); no role has DELETE
-- in the catalog; q_pend still exists and is Pending.
set local role authenticated;
do $$
declare r record; n bigint; v_res text; v_cell text := ''; v_ok boolean := true;
begin
  for r in select * from (values
    (1, 's1',   'student_delete',   'denied: %', $q$delete from public.document_requests where request_id = current_setting('app.q_pend')::bigint$q$),
    (2, 'reg',  'registrar_delete', 'denied: %', $q$delete from public.document_requests where request_id = current_setting('app.q_pend')::bigint$q$),
    (3, 'adm',  'admin_delete',     'denied: %', $q$delete from public.document_requests where request_id = current_setting('app.q_pend')::bigint$q$),
    (4, 'adm',  'admin_status',     'rows 0',    $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_pend')::bigint$q$),
    (5, 'cash', 'cashier_status',   'rows 0',    $q$update public.document_requests set status = 'Processing' where request_id = current_setting('app.q_pend')::bigint$q$)
  ) as t(ord, who, label, expect, stmt) order by ord
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', current_setting('app.' || r.who), 'role', 'authenticated')::text, true);
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      v_res := 'rows ' || n;
    exception when others then
      v_res := case when sqlerrm like 'bad status change:%' then 'blocked [' || sqlstate || ']: '
                    when sqlerrm like 'permission denied%' then 'denied: '
                    when sqlerrm like 'new row violates row-level security%' then 'rls: '
                    else 'ERROR [' || sqlstate || ']: ' end || sqlerrm;
    end;
    v_ok := v_ok and v_res like r.expect;
    v_cell := v_cell || case when v_cell = '' then '' else ', ' end || r.label || ' [' || v_res || ']';
  end loop;
  perform set_config('app.t107', v_cell, true);
  perform set_config('app.t107_ok', v_ok::text, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r107', format('%s, delete_grant anon %s / authenticated %s, q_pend_pending %s -> %s',
  current_setting('app.t107'),
  has_table_privilege('anon', 'public.document_requests', 'DELETE'),
  has_table_privilege('authenticated', 'public.document_requests', 'DELETE'),
  coalesce((select status = 'Pending' from public.document_requests where request_id = current_setting('app.q_pend')::bigint), false),
  case when current_setting('app.t107_ok')::boolean
        and not has_table_privilege('anon', 'public.document_requests', 'DELETE')
        and not has_table_privilege('authenticated', 'public.document_requests', 'DELETE')
        and coalesce((select status = 'Pending' from public.document_requests where request_id = current_setting('app.q_pend')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 15. TC-108: the audit log records submissions and processing, nothing for refused changes
-- ==========================================
-- Expected: the 2 TC-96 requests have 1 INSERT row each with actor = Student 1; q_flow has
-- exactly 3 UPDATE rows, actor = the Registrar, steps "Pending>Processing,
-- Processing>Ready, Ready>Released"; q_forge has 1 UPDATE row (the status step; the forge
-- without a status change wrote nothing); q_pend, q_proc, q_ready, q_rel, q_rejd (only
-- refused or 0-row attempts) have 0 UPDATE rows.
select set_config('app.r108', (select format('student_inserts %s (actor_student %s), flow [%s] (actor_registrar %s), forge_updates %s, refused_updates %s -> %s',
    x.ins, x.ins_actor, x.flow, x.flow_actor, x.forge, x.refused,
    case when x.ins = 2 and x.ins_actor and x.flow = 'Pending>Processing, Processing>Ready, Ready>Released'
          and x.flow_actor and x.forge = 1 and x.refused = 0 then 'OK' else 'FAIL' end)
  from (select
    (select count(*) from public.audit_logs l
      where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'document_requests' and l.action = 'INSERT'
        and l.record_id in (current_setting('app.q96a'), current_setting('app.q96b'))) as ins,
    coalesce((select bool_and(l.actor_id::text = current_setting('app.s1')) from public.audit_logs l
               where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'document_requests' and l.action = 'INSERT'
                 and l.record_id in (current_setting('app.q96a'), current_setting('app.q96b'))), false) as ins_actor,
    coalesce((select string_agg((l.old_data ->> 'status') || '>' || (l.new_data ->> 'status'), ', ' order by l.log_id)
                from public.audit_logs l
               where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'document_requests' and l.action = 'UPDATE'
                 and l.record_id = current_setting('app.q_flow')), '') as flow,
    coalesce((select bool_and(l.actor_id::text = current_setting('app.reg')) from public.audit_logs l
               where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'document_requests' and l.action = 'UPDATE'
                 and l.record_id = current_setting('app.q_flow')), false) as flow_actor,
    (select count(*) from public.audit_logs l
      where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'document_requests' and l.action = 'UPDATE'
        and l.record_id = current_setting('app.q_forge')) as forge,
    (select count(*) from public.audit_logs l
      where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'document_requests' and l.action = 'UPDATE'
        and l.record_id in (current_setting('app.q_pend'), current_setting('app.q_proc'), current_setting('app.q_ready'),
                            current_setting('app.q_rel'), current_setting('app.q_rejd'))) as refused) x), true);

-- ==========================================
-- Result: ONE row
-- ==========================================
select (current_setting('app.r95') like '%-> OK' and current_setting('app.r96') like '%-> OK'
        and current_setting('app.r97') like '%-> OK' and current_setting('app.r98') like '%-> OK'
        and current_setting('app.r99') like '%-> OK' and current_setting('app.r100') like '%-> OK'
        and current_setting('app.r101') like '%-> OK' and current_setting('app.r102') like '%-> OK'
        and current_setting('app.r103') like '%-> OK' and current_setting('app.r104') like '%-> OK'
        and current_setting('app.r105') like '%-> OK' and current_setting('app.r106') like '%-> OK'
        and current_setting('app.r107') like '%-> OK' and current_setting('app.r108') like '%-> OK') as all_ok,
  current_setting('app.r95') as tc95, current_setting('app.r96') as tc96, current_setting('app.r97') as tc97,
  current_setting('app.r98') as tc98, current_setting('app.r99') as tc99, current_setting('app.r100') as tc100,
  current_setting('app.r101') as tc101, current_setting('app.r102') as tc102, current_setting('app.r103') as tc103,
  current_setting('app.r104') as tc104, current_setting('app.r105') as tc105, current_setting('app.r106') as tc106,
  current_setting('app.r107') as tc107, current_setting('app.r108') as tc108;

rollback;
