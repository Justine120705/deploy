-- ==========================================
-- E2E NEGATIVE CASE: a department cannot read or approve another department's item (issue #69, TC-71)
-- ==========================================
-- Supabase SQL editor, as postgres, a new tab. Run the whole block (from "begin;" to "rollback;"); nothing is committed.
-- Acts as dept@pnc.test (its own department comes from department_staff) and:
--   1. counts the clearance items of OTHER departments it can read through v_clearance_items (expected 0, RLS),
--   2. tries to approve a pending item of another department with cleared_by = itself (expected: rows 0, or a
--      42501 error; the item must stay pending).
-- Expected: other_items_visible 0, dept_approves_other_office "rows 0" (or an ERROR [42501]...), still_pending true,
-- verdict "-> OK". An empty other_item means there is no pending item of another department: record as not run.
begin;
select set_config('request.jwt.claims', '', true);
select set_config('app.dept', coalesce((select id::text from auth.users where email = 'dept@pnc.test'), ''), true);
select set_config('app.mydept', coalesce((select min(department_id)::text from public.department_staff
  where profile_id = current_setting('app.dept')::uuid), ''), true);
select set_config('app.other_item', coalesce((select min(clearance_item_id)::text from public.clearance_items
  where cleared_at is null and department_id::text <> current_setting('app.mydept')), ''), true);
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('app.dept'), 'role', 'authenticated')::text, true);
do $$
declare n bigint;
begin
  begin
    select count(*) into n from public.v_clearance_items
      where department_id::text <> current_setting('app.mydept');
    perform set_config('app.r_visible', n::text, true);
  exception when others then
    perform set_config('app.r_visible', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
  end;
  begin
    update public.clearance_items set cleared_at = now(), cleared_by = auth.uid()
      where clearance_item_id = current_setting('app.other_item')::bigint;
    get diagnostics n = row_count;
    perform set_config('app.r_other', 'rows ' || n, true);
  exception when others then
    perform set_config('app.r_other', 'ERROR [' || sqlstate || ']: ' || sqlerrm, true);
  end;
end $$;
reset role;
select current_setting('app.other_item') as other_item,
  current_setting('app.r_visible') as other_items_visible,
  current_setting('app.r_other') as dept_approves_other_office,
  (select cleared_at is null from public.clearance_items
    where clearance_item_id = current_setting('app.other_item')::bigint) as still_pending,
  case when current_setting('app.other_item') <> ''
        and current_setting('app.r_visible') = '0'
        and (current_setting('app.r_other') = 'rows 0' or current_setting('app.r_other') like 'ERROR [42501]%')
        and coalesce((select cleared_at is null from public.clearance_items
                       where clearance_item_id = current_setting('app.other_item')::bigint), false)
       then '-> OK' else '-> FAIL' end as verdict;
rollback;
