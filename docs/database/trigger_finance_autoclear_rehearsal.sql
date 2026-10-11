-- ==========================================
-- REHEARSAL: trigger_finance_autoclear.sql + TC-49 to TC-61 in ONE rolled-back transaction
-- ==========================================
-- GitHub issue #62 (issue 23). One paste, one run, ONE result row, nothing committed.
--
-- How to run: Supabase SQL editor, as postgres, a new tab. Paste the whole file (from
-- "begin;" to "rollback;") and click Run on the whole tab, never a selection. If the
-- script stops with an error, run "rollback;" as its own query and send the error back.
--
-- What it does:
--   1. begin;
--   2. the body of docs/database/trigger_finance_autoclear.sql (everything between its
--      "BEGIN;" and "COMMIT;" lines, copied verbatim: safety checks, function, grants,
--      triggers, checks after the change). A "trigger_finance_autoclear: ..." error here
--      means the live state is not what the file assumes: do NOT run the file live.
--   3. TC-49 to TC-61 (docs/database/trigger_finance_autoclear_test.sql), combined. Every
--      case creates its own throwaway term, clearance, charges and holds as postgres, and
--      first lifts every active hold of Student 1, so the cases do not depend on each
--      other. Each result is stored with set_config('app.rNN', ...).
--   4. One final row: one cell per case, each ending in "-> OK" or "-> FAIL", plus
--      "all_ok". Compare with Part K of docs/issue-12-testing-guide.md. (Booleans inside
--      the cells may print as t / f.)
--   5. rollback; (the triggers, the function, the grants and all test data disappear)
--
-- RUNNING ONLY THE TESTS (after the change is live): the test part starts at the line
-- "-- TESTS START HERE" (line 414 of this file; its "begin;" is line 421) and is self-contained: copy from
-- the "begin;" line right below that marker to the end of the file into a new tab and
-- run it. It ends in rollback, so it changes nothing.
--
-- Every statement that is expected to fail runs inside a do block with an exception
-- handler, so the transaction is never aborted by an expected error.
--
-- Status: run 2026-10-11 on the live project (rolled back): all_ok true.

begin;

-- ==========================================
-- 1. The change (body of trigger_finance_autoclear.sql, verbatim)
-- ==========================================

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
DO $$
DECLARE
  v_bad text;
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.finance_autoclear()');
BEGIN
  -- a) The tables exist.
  SELECT string_agg(e.t, ', ') INTO v_bad
  FROM (VALUES ('charges'), ('clearance_items'), ('clearances'), ('departments'),
               ('academic_holds'), ('audit_logs'), ('profiles'), ('roles')) AS e(t)
  WHERE pg_catalog.to_regclass('public.' || e.t) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: missing table(s) public.%; stop', v_bad;
  END IF;

  -- b) The columns the function reads or writes exist with the expected types.
  SELECT string_agg(e.t || '.' || e.col || ' ' || e.typ, ', ') INTO v_bad
  FROM (VALUES
    ('charges', 'charge_id', 'bigint'),
    ('charges', 'student_id', 'uuid'),
    ('charges', 'term_id', 'bigint'),
    ('charges', 'status', 'character varying'),
    ('clearance_items', 'clearance_item_id', 'bigint'),
    ('clearance_items', 'clearance_id', 'bigint'),
    ('clearance_items', 'department_id', 'bigint'),
    ('clearance_items', 'cleared_at', 'timestamp with time zone'),
    ('clearance_items', 'cleared_by', 'uuid'),
    ('clearances', 'clearance_id', 'bigint'),
    ('clearances', 'student_id', 'uuid'),
    ('clearances', 'term_id', 'bigint'),
    ('departments', 'department_id', 'bigint'),
    ('departments', 'department_type', 'character varying'),
    ('academic_holds', 'student_id', 'uuid'),
    ('academic_holds', 'department_id', 'bigint'),
    ('academic_holds', 'lifted_at', 'timestamp with time zone'),
    ('audit_logs', 'log_id', 'bigint'),
    ('audit_logs', 'actor_id', 'uuid'),
    ('audit_logs', 'action', 'character varying'),
    ('audit_logs', 'table_name', 'character varying'),
    ('audit_logs', 'record_id', 'character varying'),
    ('audit_logs', 'old_data', 'jsonb'),
    ('audit_logs', 'new_data', 'jsonb'),
    ('profiles', 'profile_id', 'uuid'),
    ('profiles', 'role_id', 'smallint'),
    ('profiles', 'is_active', 'boolean'),
    ('roles', 'role_id', 'smallint'),
    ('roles', 'role_name', 'character varying')) AS e(t, col, typ)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.t)
      AND a.attname = e.col AND a.attnum > 0 AND NOT a.attisdropped
      AND pg_catalog.format_type(a.atttypid, NULL) = e.typ);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: missing column or other type: %; stop', v_bad;
  END IF;

  -- c) The data the rule depends on: the status CHECK on charges allows exactly Unpaid,
  --    Cleared and Waived (schema.sql), a Financial department and the role Cashier exist.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                 WHERE k.conrelid = 'public.charges'::pg_catalog.regclass AND k.contype = 'c'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%status%'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%''Unpaid''%'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%''Cleared''%'
                   AND pg_catalog.pg_get_constraintdef(k.oid) LIKE '%''Waived''%')
     OR EXISTS (SELECT 1 FROM public.charges ch
                WHERE ch.status::text NOT IN ('Unpaid', 'Cleared', 'Waived')) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: charges.status is not limited to Unpaid / Cleared / Waived; stop and review the rule';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments d WHERE d.department_type = 'Financial') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: no department with department_type Financial; stop';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles r WHERE r.role_name = 'Cashier') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: no role named Cashier; stop';
  END IF;

  -- d) auth.uid() exists and returns uuid (it is how the Cashier is recognised).
  IF pg_catalog.to_regprocedure('auth.uid()') IS NULL
     OR (SELECT p.prorettype FROM pg_catalog.pg_proc p
         WHERE p.oid = pg_catalog.to_regprocedure('auth.uid()')) <> 'pg_catalog.uuid'::pg_catalog.regtype THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: auth.uid() missing or not returning uuid; stop';
  END IF;

  -- e) The function is absent (first run) or is this file's trigger function (re-run).
  IF v_fn IS NOT NULL AND (SELECT p.prorettype FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
                          <> 'pg_catalog.trigger'::pg_catalog.regtype THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: private.finance_autoclear() exists and is not a trigger function; stop and review';
  END IF;

  -- f) No trigger named finance_autoclear / finance_autoclear_on_create anywhere calls a
  --    different function.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
             WHERE t.tgname IN ('finance_autoclear', 'finance_autoclear_on_create') AND NOT t.tgisinternal
               AND (v_fn IS NULL OR t.tgfoid <> v_fn)) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: a different trigger named finance_autoclear(_on_create) already exists; stop and review';
  END IF;

  -- g) The triggers on charges are exactly guard_immutable_columns (BEFORE UPDATE,
  --    hardening.sql) and audit_log (AFTER, hardening2.sql B; the creation path reads its
  --    rows), both enabled, plus this file's trigger on a re-run.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'audit_log'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'finance_autoclear' AND v_fn IS NOT NULL AND t.tgfoid = v_fn));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: unexpected trigger(s) on charges: %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('audit_log')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger(s) missing or disabled on charges: %; stop', v_bad;
  END IF;

  -- h) The triggers on clearance_items are exactly guard_immutable_columns (hardening.sql),
  --    require_no_active_hold (trigger_dept_approval.sql) and audit_log (hardening2.sql B),
  --    all enabled, plus this file's trigger on a re-run. On clearances,
  --    trg_clearances_create_items (calls private.create_clearance_items()) is enabled.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass AND NOT t.tgisinternal
    AND NOT ((t.tgname = 'guard_immutable_columns'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.guard_immutable_columns()'))
          OR (t.tgname = 'require_no_active_hold'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.require_no_active_hold()'))
          OR (t.tgname = 'audit_log'
              AND t.tgfoid = pg_catalog.to_regprocedure('private.audit_log()'))
          OR (t.tgname = 'finance_autoclear_on_create' AND v_fn IS NOT NULL AND t.tgfoid = v_fn));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: unexpected trigger(s) on clearance_items: %; stop and review', v_bad;
  END IF;

  SELECT string_agg(e.n, ', ') INTO v_bad
  FROM (VALUES ('guard_immutable_columns'), ('require_no_active_hold'), ('audit_log')) AS e(n)
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                    WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass
                      AND t.tgname = e.n AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger(s) missing or disabled on clearance_items: %; stop', v_bad;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.clearances'::pg_catalog.regclass
                   AND t.tgname = 'trg_clearances_create_items' AND NOT t.tgisinternal
                   AND t.tgenabled <> 'D'
                   AND t.tgfoid = pg_catalog.to_regprocedure('private.create_clearance_items()')) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trg_clearances_create_items missing or disabled on clearances; stop and review';
  END IF;

  -- i) SECURITY DEFINER only sees every row if its owner (the role running this file)
  --    bypasses RLS on the tables it reads and writes: owner of the tables without FORCE
  --    ROW LEVEL SECURITY, or a role with BYPASSRLS.
  SELECT string_agg(c.relname, ', ') INTO v_bad
  FROM pg_catalog.pg_class c
  WHERE c.oid IN ('public.charges'::pg_catalog.regclass, 'public.clearance_items'::pg_catalog.regclass,
                  'public.clearances'::pg_catalog.regclass, 'public.departments'::pg_catalog.regclass,
                  'public.academic_holds'::pg_catalog.regclass, 'public.audit_logs'::pg_catalog.regclass,
                  'public.profiles'::pg_catalog.regclass, 'public.roles'::pg_catalog.regclass)
    AND NOT (SELECT r.rolbypassrls FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
    AND NOT (c.relowner = (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
             AND NOT c.relforcerowsecurity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: % (running as %) would not bypass RLS on %; run as the table owner (postgres); stop', current_user, current_user, v_bad;
  END IF;
END
$$;

-- ------------------------------------------
-- 2. The trigger function (one function, two triggers)
-- ------------------------------------------
CREATE OR REPLACE FUNCTION private.finance_autoclear()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_student uuid;
  v_term    bigint;
  v_item    bigint;
  v_actor   uuid;
BEGIN
  IF TG_WHEN <> 'AFTER' OR TG_LEVEL <> 'ROW' OR TG_TABLE_SCHEMA <> 'public'
     OR NOT ((TG_TABLE_NAME = 'charges' AND TG_OP IN ('INSERT', 'UPDATE'))
             OR (TG_TABLE_NAME = 'clearance_items' AND TG_OP = 'INSERT')) THEN
    RAISE EXCEPTION 'private.finance_autoclear must be an AFTER INSERT OR UPDATE FOR EACH ROW trigger on public.charges or an AFTER INSERT FOR EACH ROW trigger on public.clearance_items';
  END IF;

  IF TG_TABLE_NAME = 'charges' THEN
    -- Same test as the trigger's WHEN clause: only a settled charge can complete the set.
    IF NEW.status::text NOT IN ('Cleared', 'Waived') THEN
      RETURN NULL;
    END IF;
    v_student := NEW.student_id;
    v_term    := NEW.term_id;
    v_item    := NULL;   -- every pending Financial item of that student and term

    -- The caller who tagged this charge, only if an active Cashier (header, decision 4).
    -- auth.uid() reads the request's JWT claims, so it is the API caller here too.
    SELECT p.profile_id INTO v_actor
    FROM public.profiles p
    JOIN public.roles r ON r.role_id = p.role_id
    WHERE p.profile_id = auth.uid() AND p.is_active AND r.role_name = 'Cashier';
  ELSE
    -- Same test as the trigger's WHEN clause, then: only the Financial item.
    IF NEW.cleared_at IS NOT NULL THEN
      RETURN NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.departments d
                   WHERE d.department_id = NEW.department_id AND d.department_type = 'Financial') THEN
      RETURN NULL;
    END IF;

    SELECT c.student_id, c.term_id INTO v_student, v_term
    FROM public.clearances c
    WHERE c.clearance_id = NEW.clearance_id;
    v_item := NEW.clearance_item_id;

    -- The Cashier who tagged the last charge: the actor of the newest audit row in which a
    -- charge of this student and term became settled; only if still an active Cashier.
    SELECT p.profile_id INTO v_actor
    FROM (SELECT l.actor_id
          FROM public.audit_logs l
          JOIN public.charges ch ON l.record_id = ch.charge_id::text
          WHERE l.table_name = 'charges'
            AND ch.student_id = v_student AND ch.term_id = v_term
            AND l.action IN ('INSERT', 'UPDATE')
            AND (l.new_data ->> 'status') IN ('Cleared', 'Waived')
            AND (l.action = 'INSERT' OR (l.old_data ->> 'status') IS DISTINCT FROM (l.new_data ->> 'status'))
          ORDER BY l.log_id DESC
          LIMIT 1) last_tag
    JOIN public.profiles p ON p.profile_id = last_tag.actor_id
    JOIN public.roles r ON r.role_id = p.role_id
    WHERE p.is_active AND r.role_name = 'Cashier';
  END IF;

  -- No Cashier to record (SQL editor, server role, seed, no audit row): leave it pending.
  IF v_actor IS NULL OR v_student IS NULL OR v_term IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    UPDATE public.clearance_items ci
    SET cleared_at = pg_catalog.now(), cleared_by = v_actor
    FROM public.clearances c, public.departments d
    WHERE c.clearance_id = ci.clearance_id
      AND d.department_id = ci.department_id
      AND c.student_id = v_student
      AND c.term_id = v_term
      AND d.department_type = 'Financial'
      AND ci.cleared_at IS NULL                                   -- decision 7
      AND (v_item IS NULL OR ci.clearance_item_id = v_item)
      -- at least one charge for that term (decision 2) ...
      AND EXISTS (SELECT 1 FROM public.charges ch
                  WHERE ch.student_id = v_student AND ch.term_id = v_term)
      -- ... and every one of them settled (decision 1)
      AND NOT EXISTS (SELECT 1 FROM public.charges ch
                      WHERE ch.student_id = v_student AND ch.term_id = v_term
                        AND ch.status::text NOT IN ('Cleared', 'Waived'))
      -- no active hold of the item's department (decision 6)
      AND NOT EXISTS (SELECT 1 FROM public.academic_holds h
                      WHERE h.student_id = v_student
                        AND h.department_id = ci.department_id
                        AND h.lifted_at IS NULL);
  EXCEPTION WHEN raise_exception THEN
    -- Only the race of decision 6 (a hold committed a moment ago): leave the item pending.
    IF SQLERRM NOT LIKE 'active hold:%' THEN
      RAISE;
    END IF;
  END;

  RETURN NULL;
END
$function$;

-- Same grant style as the other trigger functions (hardening2.sql section C).
REVOKE EXECUTE ON FUNCTION private.finance_autoclear() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.finance_autoclear() TO authenticated;

-- ------------------------------------------
-- 3. The triggers (both fire after audit_log of their table; see header 10)
-- ------------------------------------------
DROP TRIGGER IF EXISTS finance_autoclear ON public.charges;
CREATE TRIGGER finance_autoclear AFTER INSERT OR UPDATE OF status, student_id, term_id ON public.charges
  FOR EACH ROW
  WHEN (NEW.status::text IN ('Cleared', 'Waived'))
  EXECUTE FUNCTION private.finance_autoclear();

DROP TRIGGER IF EXISTS finance_autoclear_on_create ON public.clearance_items;
CREATE TRIGGER finance_autoclear_on_create AFTER INSERT ON public.clearance_items
  FOR EACH ROW
  WHEN (NEW.cleared_at IS NULL)
  EXECUTE FUNCTION private.finance_autoclear();

-- ------------------------------------------
-- 4. Checks after the change (any failure rolls back the whole file)
-- ------------------------------------------
DO $$
DECLARE
  v_fn  regprocedure := pg_catalog.to_regprocedure('private.finance_autoclear()');
  v_bad text;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: function not created; rolled back';
  END IF;

  -- a) Function: SECURITY DEFINER, empty search_path.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.oid = v_fn AND p.prosecdef
                   AND p.proconfig && ARRAY['search_path=""', 'search_path=''''']) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: function is not SECURITY DEFINER with an empty search_path; rolled back';
  END IF;

  -- b) Grants: no PUBLIC entry in the ACL, anon cannot execute, authenticated can.
  IF (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a WHERE a.grantee = 0)
      FROM pg_catalog.pg_proc p WHERE p.oid = v_fn)
     OR pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: function grants are not PUBLIC none / anon none / authenticated EXECUTE; rolled back';
  END IF;

  -- c) Trigger on charges: AFTER INSERT OR UPDATE FOR EACH ROW (tgtype 1 ROW + 4 INSERT +
  --    16 UPDATE = 21; AFTER has no bit), enabled (origin), with the WHEN clause, on the
  --    columns status, student_id, term_id only, calling the function.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass
                   AND t.tgname = 'finance_autoclear' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn AND t.tgtype = 21 AND t.tgenabled = 'O'
                   AND t.tgqual IS NOT NULL
                   AND (SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
                          FROM pg_catalog.pg_attribute a
                         WHERE a.attrelid = t.tgrelid AND a.attnum = ANY (t.tgattr))
                       = 'status,student_id,term_id') THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger finance_autoclear missing or not AFTER INSERT OR UPDATE OF status, student_id, term_id ROW enabled with WHEN; rolled back';
  END IF;

  -- d) Trigger on clearance_items: AFTER INSERT FOR EACH ROW (1 + 4 = 5), enabled, WHEN.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass
                   AND t.tgname = 'finance_autoclear_on_create' AND NOT t.tgisinternal
                   AND t.tgfoid = v_fn AND t.tgtype = 5 AND t.tgenabled = 'O'
                   AND t.tgqual IS NOT NULL) THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: trigger finance_autoclear_on_create missing or not AFTER INSERT ROW enabled with WHEN; rolled back';
  END IF;

  -- e) Exactly the expected triggers on both tables now.
  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.charges'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, finance_autoclear, guard_immutable_columns' THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: triggers on charges are [%]; rolled back', v_bad;
  END IF;

  SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) INTO v_bad
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.clearance_items'::pg_catalog.regclass AND NOT t.tgisinternal;
  IF v_bad IS DISTINCT FROM 'audit_log, finance_autoclear_on_create, guard_immutable_columns, require_no_active_hold' THEN
    RAISE EXCEPTION 'trigger_finance_autoclear: triggers on clearance_items are [%]; rolled back', v_bad;
  END IF;
END
$$;



-- ==========================================
-- TESTS START HERE (TC-49 to TC-61)
-- ==========================================
-- To run ONLY the tests once trigger_finance_autoclear.sql is live: copy from the next
-- line ("begin;") to the end of this file into a new tab and run that tab as a whole.
-- In the full rehearsal the next line is a second BEGIN inside the open transaction;
-- PostgreSQL only answers "WARNING: there is already a transaction in progress" and
-- carries on (nothing is committed either way; the file ends in rollback).
begin;

-- ==========================================
-- 2. Accounts and ids used by every case (as postgres, no user JWT)
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.s1',   coalesce((select id::text from auth.users where email = 'student1@pnc.test'), ''), true);
select set_config('app.s2',   coalesce((select id::text from auth.users where email = 'student2@pnc.test'), ''), true);
select set_config('app.s3',   coalesce((select id::text from auth.users where email = 'student3@pnc.test'), ''), true);
select set_config('app.cash', coalesce((select id::text from auth.users where email = 'cashier@pnc.test'), ''), true);
select set_config('app.adm',  coalesce((select id::text from auth.users where email = 'admin@pnc.test'), ''), true);
select set_config('app.fin',  coalesce((select min(department_id)::text from public.departments
  where department_type = 'Financial'), ''), true);
select set_config('app.fee',  coalesce((select min(fee_type_id)::text from public.fee_types), ''), true);
select set_config('app.ndept', (select count(*)::text from public.departments), true);
select set_config('app.cur',  coalesce((select min(term_id)::text from public.terms where is_current), ''), true);
do $$
begin
  if '' in (current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
            current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s1'))
     or not exists (select 1 from public.students where student_id::text = current_setting('app.s2'))
     or not exists (select 1 from public.profiles p join public.roles r on r.role_id = p.role_id
                    where p.profile_id::text = current_setting('app.cash') and p.is_active and r.role_name = 'Cashier') then
    raise exception 'TC setup: seed account, student, Financial department or fee type missing, or cashier@pnc.test is not an active Cashier (s1 [%], s2 [%], cash [%], adm [%], fin [%], fee [%])',
      current_setting('app.s1'), current_setting('app.s2'), current_setting('app.cash'),
      current_setting('app.adm'), current_setting('app.fin'), current_setting('app.fee');
  end if;
end $$;

-- Every case below creates its OWN throwaway term (and its own clearance and charges),
-- and first lifts every active hold of Student 1, so the cases do not depend on each
-- other. After each impersonated step the script goes back to postgres and clears
-- request.jwt.claims ("postgres" = no user JWT, auth.uid() NULL).

-- ==========================================
-- 3. TC-49: installed as intended (catalog)
-- ==========================================
select set_config('app.r49', (select format('charges [%s], items [%s], charges_trigger [%s], items_trigger [%s], secdef %s, config [%s], owner %s, owner_bypasses_rls %s -> %s',
    x.charges_order, x.items_order, x.charges_trigger, x.items_trigger, x.secdef, x.config, x.owner, x.bypass,
    case when x.charges_order = 'guard_immutable_columns (BEFORE) > audit_log (AFTER) > finance_autoclear (AFTER)'
          and x.items_order = 'guard_immutable_columns (BEFORE) > require_no_active_hold (BEFORE) > audit_log (AFTER) > finance_autoclear_on_create (AFTER)'
          and x.charges_trigger = 'O, type 21, when true, columns status,student_id,term_id'
          and x.items_trigger = 'O, type 5, when true'
          and x.secdef and x.config in ('search_path=""', 'search_path=''''') and x.bypass
         then 'OK' else 'FAIL' end)
  from (select
    (select string_agg(tg.tgname::text || ' (' || case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end || ')', ' > '
                       order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.charges'::regclass and not tg.tgisinternal) as charges_order,
    (select string_agg(tg.tgname::text || ' (' || case when (tg.tgtype::int & 2) = 2 then 'BEFORE' else 'AFTER' end || ')', ' > '
                       order by case when (tg.tgtype::int & 2) = 2 then 0 else 1 end, tg.tgname)
       from pg_trigger tg where tg.tgrelid = 'public.clearance_items'::regclass and not tg.tgisinternal) as items_order,
    (select tg.tgenabled::text || ', type ' || tg.tgtype || ', when ' || case when tg.tgqual is not null then 'true' else 'false' end
            || ', columns ' || coalesce((select string_agg(a.attname::text, ',' order by a.attname)
                                           from pg_attribute a
                                          where a.attrelid = tg.tgrelid and a.attnum = any (tg.tgattr)), '-')
       from pg_trigger tg
      where tg.tgrelid = 'public.charges'::regclass and tg.tgname = 'finance_autoclear'
        and tg.tgfoid = to_regprocedure('private.finance_autoclear()')) as charges_trigger,
    (select tg.tgenabled::text || ', type ' || tg.tgtype || ', when ' || case when tg.tgqual is not null then 'true' else 'false' end
       from pg_trigger tg
      where tg.tgrelid = 'public.clearance_items'::regclass and tg.tgname = 'finance_autoclear_on_create'
        and tg.tgfoid = to_regprocedure('private.finance_autoclear()')) as items_trigger,
    (select p.prosecdef from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) as secdef,
    (select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) as config,
    (select pg_get_userbyid(p.proowner)::text from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) as owner,
    (select bool_and(r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
       from pg_class c
       cross join pg_proc p
       join pg_roles r on r.oid = p.proowner
      where p.oid = to_regprocedure('private.finance_autoclear()')
        and c.oid in ('public.charges'::regclass, 'public.clearance_items'::regclass, 'public.clearances'::regclass,
                      'public.departments'::regclass, 'public.academic_holds'::regclass, 'public.audit_logs'::regclass,
                      'public.profiles'::regclass, 'public.roles'::regclass)) as bypass) x), true);

-- ==========================================
-- 4. TC-50: the seed data (current term), 3 charges, 20,000 of 45,000 collected
-- ==========================================
select set_config('request.jwt.claims', '', true);
select set_config('app.t50_seed', (select format('charges %s, total %s, collected %s', count(*), coalesce(sum(ch.amount), 0),
    (select coalesce(sum(p.amount_paid), 0) from public.payments p join public.charges c2 on c2.charge_id = p.charge_id
      where c2.term_id::text = current_setting('app.cur')))
  from public.charges ch where ch.term_id::text = current_setting('app.cur')), true);
select set_config('app.t50_seed_ok', ((select count(*) from public.charges where term_id::text = current_setting('app.cur')) = 3
  and (select coalesce(sum(amount), 0) from public.charges where term_id::text = current_setting('app.cur')) = 45000
  and (select coalesce(sum(p.amount_paid), 0) from public.payments p join public.charges c2 on c2.charge_id = p.charge_id
        where c2.term_id::text = current_setting('app.cur')) = 20000)::text, true);
select set_config('app.s2_charge', coalesce((select min(charge_id)::text from public.charges
  where student_id::text = current_setting('app.s2') and term_id::text = current_setting('app.cur')), ''), true);
select set_config('app.s1_item', coalesce((select min(ci.clearance_item_id)::text from public.clearance_items ci
  join public.clearances c on c.clearance_id = ci.clearance_id
  where c.student_id::text = current_setting('app.s1') and c.term_id::text = current_setting('app.cur')
    and ci.department_id::text = current_setting('app.fin')), ''), true);
select set_config('app.s2_item', coalesce((select min(ci.clearance_item_id)::text from public.clearance_items ci
  join public.clearances c on c.clearance_id = ci.clearance_id
  where c.student_id::text = current_setting('app.s2') and c.term_id::text = current_setting('app.cur')
    and ci.department_id::text = current_setting('app.fin')), ''), true);
select set_config('app.s3_item', coalesce((select min(ci.clearance_item_id)::text from public.clearance_items ci
  join public.clearances c on c.clearance_id = ci.clearance_id
  where c.student_id::text = current_setting('app.s3') and c.term_id::text = current_setting('app.cur')
    and ci.department_id::text = current_setting('app.fin')), ''), true);
-- known start: no active Financial hold for Students 2 and 3 (Student 2's CCS hold stays)
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id::text in (current_setting('app.s2'), current_setting('app.s3'))
  and department_id::text = current_setting('app.fin') and lifted_at is null;
select set_config('app.t50_pre_ok', (
  (select count(*) from public.charges where student_id::text = current_setting('app.s2')
     and term_id::text = current_setting('app.cur')) = 1
  and (select count(*) from public.charges where student_id::text = current_setting('app.s2')
         and term_id::text = current_setting('app.cur') and status = 'Unpaid') = 1
  and exists (select 1 from public.charges where student_id::text = current_setting('app.s3')
                and term_id::text = current_setting('app.cur') and status = 'Unpaid')
  and coalesce((select cleared_at is null from public.clearance_items
                 where clearance_item_id::text = current_setting('app.s2_item')), false)
  and coalesce((select cleared_at is null from public.clearance_items
                 where clearance_item_id::text = current_setting('app.s3_item')), false))::text, true);
select set_config('app.t50_s1_before', coalesce((select cleared_at::text || ' ' || coalesce(cleared_by::text, '-')
  from public.clearance_items where clearance_item_id::text = current_setting('app.s1_item')), 'none'), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Cleared' where charge_id::text = current_setting('app.s2_charge');
  get diagnostics n = row_count;
  perform set_config('app.t50_tag', 'rows ' || n, true);
exception when others then
  perform set_config('app.t50_tag',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r50', format('seed [%s], seed_ok %s, preconditions_ok %s, cashier_tags_s2 [%s], s2_cleared_by_cashier %s, s3_pending %s, s1_unchanged %s -> %s',
  current_setting('app.t50_seed'), current_setting('app.t50_seed_ok'), current_setting('app.t50_pre_ok'),
  current_setting('app.t50_tag'),
  coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
              from public.clearance_items where clearance_item_id::text = current_setting('app.s2_item')), false),
  coalesce((select cleared_at is null from public.clearance_items
             where clearance_item_id::text = current_setting('app.s3_item')), false),
  coalesce((select cleared_at::text || ' ' || coalesce(cleared_by::text, '-') from public.clearance_items
             where clearance_item_id::text = current_setting('app.s1_item')), 'none') = current_setting('app.t50_s1_before'),
  case when current_setting('app.t50_seed_ok') = 'true' and current_setting('app.t50_pre_ok') = 'true'
        and current_setting('app.t50_tag') = 'rows 1'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id::text = current_setting('app.s2_item')), false)
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id::text = current_setting('app.s3_item')), false)
        and coalesce((select cleared_at::text || ' ' || coalesce(cleared_by::text, '-') from public.clearance_items
                       where clearance_item_id::text = current_setting('app.s1_item')), 'none')
            = current_setting('app.t50_s1_before')
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 5. TC-51 (a): mixed Cleared / Waived, the item clears on the last tag
-- ==========================================
-- reset and arrange (as postgres, no user JWT)
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2091-2092', '1st', '2091-08-01', '2092-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2091-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
insert into public.payments (charge_id, amount_paid, receipt_number, recorded_by)
values (current_setting('app.ch1')::bigint, 15000, 'TC51R-' || txid_current() || '-1', current_setting('app.cash')::uuid),
       (current_setting('app.ch2')::bigint,  5000, 'TC51R-' || txid_current() || '-2', current_setting('app.cash')::uuid);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t51_' || r.label, 'rows ' || n || ', item ' ||
        coalesce((select case when ci.cleared_at is null then 'pending' else 'cleared' end
                    from public.clearance_items ci
                   where ci.clearance_item_id = current_setting('app.item_fin')::bigint), 'not visible'), true);
    exception when others then
      perform set_config('app.t51_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r51', format('tag1 [%s], tag2 [%s], tag3 [%s], collected %s of %s, cleared_by_cashier %s -> %s',
  current_setting('app.t51_tag1'), current_setting('app.t51_tag2'), current_setting('app.t51_tag3'),
  (select sum(p.amount_paid) from public.payments p
    where p.charge_id in (current_setting('app.ch1')::bigint, current_setting('app.ch2')::bigint, current_setting('app.ch3')::bigint)),
  (select sum(ch.amount) from public.charges ch
    where ch.student_id = current_setting('app.s1')::uuid and ch.term_id = current_setting('app.term')::bigint),
  coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
              from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  case when current_setting('app.t51_tag1') = 'rows 1, item pending'
        and current_setting('app.t51_tag2') = 'rows 1, item pending'
        and current_setting('app.t51_tag3') = 'rows 1, item cleared'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 6. TC-52 (b): one charge still Unpaid, not cleared
-- ==========================================
-- reset and arrange
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2092-2093', '1st', '2092-08-01', '2093-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2092-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1',  $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2',  $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'edit3', $q$update public.charges set amount = 14000, due_date = date '2092-11-15'
                    where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t52_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t52_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r52', format('tag1 [%s], tag2 [%s], edit3 [%s], third_status %s, financial_pending %s -> %s',
  current_setting('app.t52_tag1'), current_setting('app.t52_tag2'), current_setting('app.t52_edit3'),
  (select status from public.charges where charge_id = current_setting('app.ch3')::bigint),
  coalesce((select cleared_at is null and cleared_by is null from public.clearance_items
             where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  case when current_setting('app.t52_tag1') = 'rows 1' and current_setting('app.t52_tag2') = 'rows 1'
        and current_setting('app.t52_edit3') = 'rows 1'
        and (select status from public.charges where charge_id = current_setting('app.ch3')::bigint) = 'Unpaid'
        and coalesce((select cleared_at is null and cleared_by is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 7. TC-53 (c): no clearance yet; the item clears when the clearance is created
-- ==========================================
-- reset and arrange (no clearance)
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2093-2094', '1st', '2093-08-01', '2094-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2093-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- act as the Cashier (no clearance exists yet)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t53_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t53_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.t53_clr_before', (select count(*)::text from public.clearances
  where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term')::bigint), true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as Student 1: request the clearance
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr', v_id::text, true);
  perform set_config('app.t53_request', 'rows 1', true);
exception when others then
  perform set_config('app.clr', '', true);
  perform set_config('app.t53_request',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.item_fin', coalesce((select min(clearance_item_id)::text from public.clearance_items
  where clearance_id::text = current_setting('app.clr') and department_id::text = current_setting('app.fin')), ''), true);
select set_config('app.t53_items', (select count(*)::text from public.clearance_items
  where clearance_id::text = current_setting('app.clr')), true);
select set_config('app.t53_others', (select count(*)::text from public.clearance_items
  where clearance_id::text = current_setting('app.clr') and department_id::text <> current_setting('app.fin')
    and cleared_at is null), true);
select set_config('app.t53_audit', coalesce((select string_agg(l.action::text, ',' order by l.log_id) from public.audit_logs l
  where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
    and l.record_id = current_setting('app.item_fin')), '-'), true);
select set_config('app.r53', format('tags [%s, %s, %s], clearances_before %s, request [%s], items %s, cleared_by_cashier %s, others_pending %s, item_audit [%s], update_actor_is_student %s -> %s',
  current_setting('app.t53_tag1'), current_setting('app.t53_tag2'), current_setting('app.t53_tag3'),
  current_setting('app.t53_clr_before'), current_setting('app.t53_request'), current_setting('app.t53_items'),
  coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
              from public.clearance_items where clearance_item_id::text = current_setting('app.item_fin')), false),
  current_setting('app.t53_others'), current_setting('app.t53_audit'),
  coalesce((select bool_and(l.actor_id::text = current_setting('app.s1')) from public.audit_logs l
             where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
               and l.record_id = current_setting('app.item_fin') and l.action = 'UPDATE'), false),
  case when current_setting('app.t53_tag1') = 'rows 1' and current_setting('app.t53_tag2') = 'rows 1'
        and current_setting('app.t53_tag3') = 'rows 1' and current_setting('app.t53_clr_before') = '0'
        and current_setting('app.t53_request') = 'rows 1'
        and current_setting('app.t53_items') = current_setting('app.ndept')
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id::text = current_setting('app.item_fin')), false)
        and current_setting('app.t53_others')::bigint = current_setting('app.ndept')::bigint - 1
        and current_setting('app.t53_audit') = 'INSERT,UPDATE'
        and coalesce((select bool_and(l.actor_id::text = current_setting('app.s1')) from public.audit_logs l
                       where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                         and l.record_id = current_setting('app.item_fin') and l.action = 'UPDATE'), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 8. TC-54 (d): zero charges, not cleared
-- ==========================================
-- reset and arrange: no charge in this term; a settled charge only in another term
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2094-2095', '1st', '2094-08-01', '2095-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2084-2085', '1st', '2084-08-01', '2085-01-01', false) returning term_id)
select set_config('app.term2', term_id::text, true) from t;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s1')::uuid, current_setting('app.term2')::bigint, current_setting('app.fee')::bigint,
        15000, date '2084-10-15', 'Unpaid');
-- act as the Cashier: settle the charge of the OTHER term
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Cleared'
  where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term2')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t54_other', 'rows ' || n, true);
exception when others then
  perform set_config('app.t54_other',
    case when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
-- act as Student 1: request the clearance for the term without charges
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr', v_id::text, true);
  perform set_config('app.t54_request', 'rows 1', true);
exception when others then
  perform set_config('app.clr', '', true);
  perform set_config('app.t54_request',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r54', format('other_term_tag [%s], charges_in_term %s, request [%s], items %s, financial_pending %s -> %s',
  current_setting('app.t54_other'),
  (select count(*) from public.charges where student_id = current_setting('app.s1')::uuid
     and term_id = current_setting('app.term')::bigint),
  current_setting('app.t54_request'),
  (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr')),
  coalesce((select bool_and(cleared_at is null) from public.clearance_items
             where clearance_id::text = current_setting('app.clr') and department_id::text = current_setting('app.fin')), false),
  case when current_setting('app.t54_other') = 'rows 1' and current_setting('app.t54_request') = 'rows 1'
        and (select count(*) from public.charges where student_id = current_setting('app.s1')::uuid
               and term_id = current_setting('app.term')::bigint) = 0
        and (select count(*) from public.clearance_items where clearance_id::text = current_setting('app.clr'))
            = current_setting('app.ndept')::bigint
        and coalesce((select bool_and(cleared_at is null) from public.clearance_items
                       where clearance_id::text = current_setting('app.clr')
                         and department_id::text = current_setting('app.fin')), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 9. TC-55 (e): active Financial hold, the item stays pending and nothing fails
-- ==========================================
-- reset and arrange
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2095-2096', '1st', '2095-08-01', '2096-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2095-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- part 1: an active Financial hold, then the Cashier tags all three
with h as (insert into public.academic_holds (student_id, department_id, reason, placed_by)
           values (current_setting('app.s1')::uuid, current_setting('app.fin')::bigint, 'TC-55 financial hold',
                   current_setting('app.cash')::uuid) returning hold_id)
select set_config('app.hold', hold_id::text, true) from h;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t55_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t55_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.t55_pending', (select (cleared_at is null)::text from public.clearance_items
  where clearance_item_id = current_setting('app.item_fin')::bigint), true);
-- part 2: lift the hold (postgres), the Cashier re-saves the last charge's status
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where hold_id = current_setting('app.hold')::bigint;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = status where charge_id = current_setting('app.ch3')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t55_resave', 'rows ' || n, true);
exception when others then
  perform set_config('app.t55_resave',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
-- part 3: creation path with an active Financial hold (second throwaway term)
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2085-2086', '1st', '2085-08-01', '2086-01-01', false) returning term_id)
select set_config('app.term2', term_id::text, true) from t;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s1')::uuid, current_setting('app.term2')::bigint, current_setting('app.fee')::bigint,
        15000, date '2085-10-15', 'Unpaid');
insert into public.academic_holds (student_id, department_id, reason, placed_by)
values (current_setting('app.s1')::uuid, current_setting('app.fin')::bigint, 'TC-55 financial hold 2',
        current_setting('app.cash')::uuid);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Cleared'
  where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term2')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t55_tag_term2', 'rows ' || n, true);
exception when others then
  perform set_config('app.t55_tag_term2', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term2')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr2', v_id::text, true);
  perform set_config('app.t55_request2', 'rows 1', true);
exception when others then
  perform set_config('app.clr2', '', true);
  perform set_config('app.t55_request2',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r55', format('tags_with_hold [%s, %s, %s], pending_with_hold %s, resave_after_lift [%s], cleared_by_cashier %s, term2_tag [%s], request_with_hold [%s], created_item_pending %s -> %s',
  current_setting('app.t55_tag1'), current_setting('app.t55_tag2'), current_setting('app.t55_tag3'),
  current_setting('app.t55_pending'), current_setting('app.t55_resave'),
  coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
              from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  current_setting('app.t55_tag_term2'), current_setting('app.t55_request2'),
  coalesce((select bool_and(cleared_at is null) from public.clearance_items
             where clearance_id::text = current_setting('app.clr2') and department_id::text = current_setting('app.fin')), false),
  case when current_setting('app.t55_tag1') = 'rows 1' and current_setting('app.t55_tag2') = 'rows 1'
        and current_setting('app.t55_tag3') = 'rows 1' and current_setting('app.t55_pending') = 'true'
        and current_setting('app.t55_resave') = 'rows 1'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and current_setting('app.t55_tag_term2') = 'rows 1'
        and current_setting('app.t55_request2') = 'rows 1'
        and coalesce((select bool_and(cleared_at is null) from public.clearance_items
                       where clearance_id::text = current_setting('app.clr2')
                         and department_id::text = current_setting('app.fin')), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 10. TC-56 (f): an already-cleared Financial item is not overwritten
-- ==========================================
-- reset and arrange
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2096-2097', '1st', '2096-08-01', '2097-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2096-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
update public.clearance_items
set cleared_at = timestamptz '2096-09-01 08:00:00+00', cleared_by = current_setting('app.adm')::uuid,
    remarks = 'TC-56 manual clear'
where clearance_item_id = current_setting('app.item_fin')::bigint;
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t56_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t56_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r56', format('tags [%s, %s, %s], unchanged %s, item_audit_rows %s -> %s',
  current_setting('app.t56_tag1'), current_setting('app.t56_tag2'), current_setting('app.t56_tag3'),
  coalesce((select cleared_at = timestamptz '2096-09-01 08:00:00+00' and cleared_by::text = current_setting('app.adm')
                   and remarks = 'TC-56 manual clear'
              from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
      and l.record_id = current_setting('app.item_fin')),
  case when current_setting('app.t56_tag1') = 'rows 1' and current_setting('app.t56_tag2') = 'rows 1'
        and current_setting('app.t56_tag3') = 'rows 1'
        and coalesce((select cleared_at = timestamptz '2096-09-01 08:00:00+00'
                             and cleared_by::text = current_setting('app.adm')
                             and remarks = 'TC-56 manual clear'
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                and l.record_id = current_setting('app.item_fin')) = 0
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 11. TC-57 (g): a charge goes back to Unpaid, the item is NOT un-cleared
-- ==========================================
-- reset and arrange
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2097-2098', '1st', '2097-08-01', '2098-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2097-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- act as the Cashier: tag all three (the item auto-clears)
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t57_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t57_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.t57_auto', coalesce((select (cleared_at is not null)::text from public.clearance_items
  where clearance_item_id = current_setting('app.item_fin')::bigint), 'false'), true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier: revert the second charge to Unpaid, then tag it again
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'revert', $q$update public.charges set status = 'Unpaid'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (2, 'retag',  $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch2')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t57_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t57_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r57', format('auto_cleared %s, revert [%s], retag [%s], still_cleared_by_cashier %s, item_audit_rows_after_revert %s, charge_audit_rows %s -> %s',
  current_setting('app.t57_auto'), current_setting('app.t57_revert'), current_setting('app.t57_retag'),
  coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
              from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
      and l.record_id = current_setting('app.item_fin')),
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'charges'
      and l.record_id = current_setting('app.ch2')),
  case when current_setting('app.t57_auto') = 'true'
        and current_setting('app.t57_tag1') = 'rows 1' and current_setting('app.t57_tag2') = 'rows 1'
        and current_setting('app.t57_tag3') = 'rows 1'
        and current_setting('app.t57_revert') = 'rows 1' and current_setting('app.t57_retag') = 'rows 1'
        and coalesce((select cleared_at is not null and cleared_by::text = current_setting('app.cash')
                        from public.clearance_items where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                and l.record_id = current_setting('app.item_fin')) = 0
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'charges'
                and l.record_id = current_setting('app.ch2')) = 2
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 12. TC-58 (h): a successful auto-clear writes an audit row
-- ==========================================
-- reset and arrange
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2098-2099', '1st', '2098-08-01', '2099-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2098-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- the first two charges are settled by the Cashier (as postgres with the Cashier's claims)
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
update public.charges set status = 'Cleared'
where charge_id in (current_setting('app.ch1')::bigint, current_setting('app.ch2')::bigint);
select set_config('request.jwt.claims', '', true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier: the last tag
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Waived' where charge_id = current_setting('app.ch3')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t58_tag3', 'rows ' || n, true);
exception when others then
  perform set_config('app.t58_tag3',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r58', (select format('last_tag [%s], item_audit_rows %s, action %s, actor_is_cashier %s, old_cleared_at_null %s, new_cleared_by_is_cashier %s, charge_row_first %s -> %s',
    current_setting('app.t58_tag3'), a.item_audit_rows, coalesce(a.action, '-'), a.actor_is_cashier,
    a.old_cleared_at_null, a.new_cleared_by_is_cashier, a.charge_row_first,
    case when current_setting('app.t58_tag3') = 'rows 1' and a.item_audit_rows = 1 and a.action = 'UPDATE'
          and a.actor_is_cashier and a.old_cleared_at_null and a.new_cleared_by_is_cashier and a.charge_row_first
         then 'OK' else 'FAIL' end)
  from (select count(*) as item_audit_rows,
               string_agg(distinct l.action::text, ',') as action,
               coalesce(bool_and(l.actor_id::text = current_setting('app.cash')), false) as actor_is_cashier,
               coalesce(bool_and(l.old_data ->> 'cleared_at' is null), false) as old_cleared_at_null,
               coalesce(bool_and(l.new_data ->> 'cleared_by' = current_setting('app.cash')), false) as new_cleared_by_is_cashier,
               coalesce(bool_and(l.log_id > (select min(c.log_id) from public.audit_logs c
                                              where c.log_id > current_setting('app.log_mark')::bigint
                                                and c.table_name = 'charges'
                                                and c.record_id = current_setting('app.ch3'))), false) as charge_row_first
        from public.audit_logs l
        where l.log_id > current_setting('app.log_mark')::bigint
          and l.table_name = 'clearance_items'
          and l.record_id = current_setting('app.item_fin')) a), true);

-- ==========================================
-- 13. TC-59 (i): other departments' items and other students are never touched
-- ==========================================
-- reset and arrange
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s2')::uuid and department_id = current_setting('app.fin')::bigint
  and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2099-2100', '1st', '2099-08-01', '2100-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s2')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr2', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select x.clr, d.department_id
from (values (current_setting('app.clr')::bigint), (current_setting('app.clr2')::bigint)) as x(clr)
cross join public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = x.clr and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
select set_config('app.item_fin2', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr2')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s2')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
        15000, date '2099-10-15', 'Unpaid');
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2099-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
select set_config('app.log_mark', (select coalesce(max(log_id), 0)::text from public.audit_logs), true);
-- act as the Cashier
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
declare
  r record;
  n bigint;
begin
  for r in select * from (values
    (1, 'tag1', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch1')::bigint$q$),
    (2, 'tag2', $q$update public.charges set status = 'Waived'  where charge_id = current_setting('app.ch2')::bigint$q$),
    (3, 'tag3', $q$update public.charges set status = 'Cleared' where charge_id = current_setting('app.ch3')::bigint$q$)
  ) as t(ord, label, stmt) order by ord
  loop
    begin
      execute r.stmt;
      get diagnostics n = row_count;
      perform set_config('app.t59_' || r.label, 'rows ' || n, true);
    exception when others then
      perform set_config('app.t59_' || r.label,
        case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
             when sqlerrm like 'permission denied%' then 'denied: '
             when sqlerrm like 'new row violates row-level security%' then 'rls: '
             else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
    end;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r59', format('tags [%s, %s, %s], s1_financial_cleared %s, s1_other_items_pending %s of %s, other_rows_audited %s, s2_financial_pending %s -> %s',
  current_setting('app.t59_tag1'), current_setting('app.t59_tag2'), current_setting('app.t59_tag3'),
  coalesce((select cleared_at is not null from public.clearance_items
             where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  (select count(*) from public.clearance_items where clearance_id = current_setting('app.clr')::bigint
     and department_id <> current_setting('app.fin')::bigint and cleared_at is null and cleared_by is null),
  current_setting('app.ndept')::bigint - 1,
  (select count(*) from public.audit_logs l
    where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
      and l.record_id <> current_setting('app.item_fin')),
  coalesce((select cleared_at is null from public.clearance_items
             where clearance_item_id = current_setting('app.item_fin2')::bigint), false),
  case when current_setting('app.t59_tag1') = 'rows 1' and current_setting('app.t59_tag2') = 'rows 1'
        and current_setting('app.t59_tag3') = 'rows 1'
        and coalesce((select cleared_at is not null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and (select count(*) from public.clearance_items where clearance_id = current_setting('app.clr')::bigint
               and department_id <> current_setting('app.fin')::bigint and cleared_at is null and cleared_by is null)
            = current_setting('app.ndept')::bigint - 1
        and (select count(*) from public.audit_logs l
              where l.log_id > current_setting('app.log_mark')::bigint and l.table_name = 'clearance_items'
                and l.record_id <> current_setting('app.item_fin')) = 0
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin2')::bigint), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 14. TC-60: no Cashier to record (postgres without a user JWT), the item stays pending
-- ==========================================
-- reset and arrange
select set_config('request.jwt.claims', '', true);
update public.academic_holds set lifted_at = now(), lifted_by = current_setting('app.cash')::uuid
where student_id = current_setting('app.s1')::uuid and lifted_at is null;
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2081-2082', '1st', '2081-08-01', '2082-01-01', false) returning term_id)
select set_config('app.term', term_id::text, true) from t;
with c as (insert into public.clearances (student_id, term_id)
           values (current_setting('app.s1')::uuid, current_setting('app.term')::bigint) returning clearance_id)
select set_config('app.clr', clearance_id::text, true) from c;
insert into public.clearance_items (clearance_id, department_id)
select current_setting('app.clr')::bigint, d.department_id
from public.departments d
where not exists (select 1 from public.clearance_items i
                  where i.clearance_id = current_setting('app.clr')::bigint and i.department_id = d.department_id);
select set_config('app.item_fin', (select min(clearance_item_id)::text from public.clearance_items
  where clearance_id = current_setting('app.clr')::bigint and department_id = current_setting('app.fin')::bigint), true);
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
select current_setting('app.s1')::uuid, current_setting('app.term')::bigint, current_setting('app.fee')::bigint,
       15000, date '2081-10-15', 'Unpaid'
from generate_series(1, 3);
select set_config('app.ch1', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 0 limit 1), true);
select set_config('app.ch2', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 1 limit 1), true);
select set_config('app.ch3', (select charge_id::text from public.charges where student_id = current_setting('app.s1')::uuid
  and term_id = current_setting('app.term')::bigint order by charge_id offset 2 limit 1), true);
-- part 1: the Cashier settles the first two ...
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
update public.charges set status = 'Cleared'
where charge_id in (current_setting('app.ch1')::bigint, current_setting('app.ch2')::bigint);
reset role;
-- ... and postgres without a user JWT settles the last one
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.t60_uid_null', (auth.uid() is null)::text, true);
do $$
declare n bigint;
begin
  update public.charges set status = 'Waived' where charge_id = current_setting('app.ch3')::bigint;
  get diagnostics n = row_count;
  perform set_config('app.t60_pg', 'rows ' || n, true);
exception when others then
  perform set_config('app.t60_pg', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
-- part 2: second throwaway term, the only charge settled by postgres, then the request
with t as (insert into public.terms (school_year, semester, start_date, end_date, is_current)
           values ('2082-2083', '1st', '2082-08-01', '2083-01-01', false) returning term_id)
select set_config('app.term2', term_id::text, true) from t;
insert into public.charges (student_id, term_id, fee_type_id, amount, due_date, status)
values (current_setting('app.s1')::uuid, current_setting('app.term2')::bigint, current_setting('app.fee')::bigint,
        15000, date '2082-10-15', 'Unpaid');
update public.charges set status = 'Cleared'
where student_id = current_setting('app.s1')::uuid and term_id = current_setting('app.term2')::bigint;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.s1'), 'role', 'authenticated')::text, true);
do $$
declare v_id bigint;
begin
  insert into public.clearances (student_id, term_id)
  values (auth.uid(), current_setting('app.term2')::bigint) returning clearance_id into v_id;
  perform set_config('app.clr2', v_id::text, true);
  perform set_config('app.t60_request', 'rows 1', true);
exception when others then
  perform set_config('app.clr2', '', true);
  perform set_config('app.t60_request',
    case when sqlerrm like 'active hold:%' then 'blocked [' || sqlstate || ']: '
         when sqlerrm like 'permission denied%' then 'denied: '
         when sqlerrm like 'new row violates row-level security%' then 'rls: '
         else 'ERROR [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r60', format('auth_uid_null %s, postgres_last_tag [%s], item_pending %s, request [%s], created_item_pending %s -> %s',
  current_setting('app.t60_uid_null'), current_setting('app.t60_pg'),
  coalesce((select cleared_at is null from public.clearance_items
             where clearance_item_id = current_setting('app.item_fin')::bigint), false),
  current_setting('app.t60_request'),
  coalesce((select bool_and(cleared_at is null) from public.clearance_items
             where clearance_id::text = current_setting('app.clr2') and department_id::text = current_setting('app.fin')), false),
  case when current_setting('app.t60_uid_null') = 'true' and current_setting('app.t60_pg') = 'rows 1'
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id = current_setting('app.item_fin')::bigint), false)
        and current_setting('app.t60_request') = 'rows 1'
        and coalesce((select bool_and(cleared_at is null) from public.clearance_items
                       where clearance_id::text = current_setting('app.clr2')
                         and department_id::text = current_setting('app.fin')), false)
       then 'OK' else 'FAIL' end), true);

-- ==========================================
-- 15. TC-61 (j): function privileges; anon cannot call it
-- ==========================================
set local role anon;
do $$
begin
  perform private.finance_autoclear();
  perform set_config('app.t61_anon', 'NOT DENIED', true);
exception when others then
  perform set_config('app.t61_anon',
    case when sqlerrm like 'permission denied%' then 'denied: ' else 'OTHER [' || sqlstate || ']: ' end || sqlerrm, true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.cash'), 'role', 'authenticated')::text, true);
do $$
begin
  perform private.finance_autoclear();
  perform set_config('app.t61_auth', 'NO ERROR', true);
exception when others then
  perform set_config('app.t61_auth', 'error [' || sqlstate || ']: ' || sqlerrm, true);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.r61', (select format('anon_execute %s, authenticated_execute %s, public_in_acl %s, security_definer %s, anon_call [%s], authenticated_call [%s] -> %s',
    f.anon_execute, f.authenticated_execute, f.public_in_acl, f.security_definer,
    current_setting('app.t61_anon'), current_setting('app.t61_auth'),
    case when not f.anon_execute and f.authenticated_execute and not f.public_in_acl and f.security_definer
          and current_setting('app.t61_anon') like 'denied: %'
          and current_setting('app.t61_auth') like 'error %'
         then 'OK' else 'FAIL' end)
  from (select has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
               has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
               (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)) as public_in_acl,
               p.prosecdef as security_definer
        from pg_proc p where p.oid = to_regprocedure('private.finance_autoclear()')) f), true);

-- ==========================================
-- Result: ONE row. Every cell must end in "-> OK"; all_ok must be true.
-- ==========================================
select (current_setting('app.r49') like '%-> OK' and current_setting('app.r50') like '%-> OK'
        and current_setting('app.r51') like '%-> OK' and current_setting('app.r52') like '%-> OK'
        and current_setting('app.r53') like '%-> OK' and current_setting('app.r54') like '%-> OK'
        and current_setting('app.r55') like '%-> OK' and current_setting('app.r56') like '%-> OK'
        and current_setting('app.r57') like '%-> OK' and current_setting('app.r58') like '%-> OK'
        and current_setting('app.r59') like '%-> OK' and current_setting('app.r60') like '%-> OK'
        and current_setting('app.r61') like '%-> OK') as all_ok,
  current_setting('app.r49') as tc49, current_setting('app.r50') as tc50, current_setting('app.r51') as tc51,
  current_setting('app.r52') as tc52, current_setting('app.r53') as tc53, current_setting('app.r54') as tc54,
  current_setting('app.r55') as tc55, current_setting('app.r56') as tc56, current_setting('app.r57') as tc57,
  current_setting('app.r58') as tc58, current_setting('app.r59') as tc59, current_setting('app.r60') as tc60,
  current_setting('app.r61') as tc61;

rollback;
