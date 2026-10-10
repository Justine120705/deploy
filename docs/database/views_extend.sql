-- ==========================================
-- EXTEND THE VIEWS (GitHub issue #49, option A)
-- ==========================================
-- The 4 live views (docs/database/views.sql) have fewer columns than
-- types/database.types.ts (Views section) and lib/mock-data.ts assume. Decision: extend
-- the live views so they have every column the types file lists; the app code, the mock
-- data and the types stay unchanged.
--
--   v_active_holds     already matches the types file: NOT changed, only checked.
--   v_clearance_items  + student_id, term_id            (from clearances)
--                      + department_name, department_type (from departments)
--   v_clearances       + total_items, cleared_items     (counts of clearance_items;
--                                                       cleared = cleared_at IS NOT NULL)
--   v_grades           + enrollment_id, student_id, term_id, section_id, subject_id,
--                        subject_code, subject_title, units
--                        (grades -> enrollment_items -> enrollments, -> sections -> subjects)
--
-- How CREATE OR REPLACE VIEW works here (PostgreSQL rules):
--   - It may only APPEND new columns after the existing ones; the existing columns must
--     keep their names, types and order. So each view below keeps its old select list
--     first (same names, types and order as views.sql) and appends the new columns at the
--     end. The column order in types/database.types.ts does not matter to the app
--     (PostgREST returns JSON objects by name).
--   - It keeps the view's owner and its GRANTs (after hardening2.sql section C:
--     authenticated SELECT only, no anon). A DROP + CREATE would NOT keep them (see the
--     ROLLBACK block).
--   - Every statement states WITH (security_invoker = true) again on purpose, so the
--     result does not depend on whether CREATE OR REPLACE keeps or resets the existing
--     view options. The checks below verify it before and after.
--
-- Security (security_invoker = true): the RLS policies of EVERY table the view reads,
-- including the joined ones, apply to the CALLER. A join can therefore only show the
-- caller data it could already read from that table directly, but an INNER join to a
-- table the caller cannot see would HIDE the row. All new joins are LEFT JOINs (or
-- scalar subqueries), so every view returns exactly the same rows as before for every
-- role; only new columns are added, and a new column is NULL when the caller cannot
-- read the joined row. Every join is on a primary key, so no row is duplicated.
-- Checked against rls.sql:
--   - v_grades: grades are readable by Registrar and the owner student only; the joined
--     enrollment_items / enrollments have the same readers (Registrar, owner);
--     sections / subjects are readable by all authenticated. So for the callers who can
--     see a grade, the new columns are filled. Cashier / Department / Admin see no
--     grades, before and after.
--   - v_clearance_items: clearances are readable by the owner, Registrar/Admin and
--     Cashier/Department for clearances that have an item of their department
--     (clearance_in_my_department), which covers every item they can read;
--     departments are readable by all authenticated.
--   - v_clearances: the counts are subqueries on clearance_items, which is also under
--     the caller's RLS. Owner student, Registrar and Admin see every item of a visible
--     clearance, so their counts are the real counts. Cashier and Department see only
--     the items of THEIR department, so for them total_items / cleared_items count only
--     their own department's items (usually 1). This is intentional: a real count would
--     need a SECURITY DEFINER helper and would tell them about other offices' items.
--
-- How to run: Supabase SQL editor, as the view owner (postgres). Copy from "BEGIN;" to
-- "COMMIT;" inclusive into a new tab and run that tab as a whole (never a partial
-- selection). It is one transaction: any error, including a failed check, rolls back
-- everything. Re-runnable: the checks accept both the old and the already-extended
-- column lists, and running it twice gives the same views.
-- Before running: run diagnostics (a), (b) and (c) at the bottom and SAVE the output (it
-- is the state the ROLLBACK must return to). CREATE OR REPLACE VIEW takes a short
-- exclusive lock on each view; well under a second on this data.
-- Test afterwards: Part H of docs/issue-12-testing-guide.md (TC-29 to TC-33), then
-- TC-15, TC-16 and TC-28 again.
-- After it ran live: update docs/database/views.sql to the new definitions (export from
-- pg_views) and remove the types gap from docs/database/README.md.


BEGIN;

-- ------------------------------------------
-- 1. Safety checks (stop before changing anything)
-- ------------------------------------------
-- For each view: it must exist, be a view, be security_invoker, and its columns (name
-- and type, in order) must be EITHER exactly the old list from views.sql (first run) OR
-- exactly the new list below (re-run). Anything else (someone changed a view, a column
-- type differs) stops here, so CREATE OR REPLACE cannot fail halfway or silently change
-- something we did not expect. information_schema.columns is read as postgres (the
-- owner), so every column is visible.
DO $$
DECLARE
  r      record;
  v_cols text[];
  v_kind "char";
  v_opts text[];
BEGIN
  FOR r IN
    SELECT *
    FROM (VALUES
      ('v_active_holds',
       ARRAY['hold_id bigint', 'student_id uuid', 'department_id bigint',
             'reason character varying', 'placed_by uuid',
             'placed_at timestamp with time zone'],
       ARRAY['hold_id bigint', 'student_id uuid', 'department_id bigint',
             'reason character varying', 'placed_by uuid',
             'placed_at timestamp with time zone']),
      ('v_clearance_items',
       ARRAY['clearance_item_id bigint', 'clearance_id bigint', 'department_id bigint',
             'cleared_by uuid', 'cleared_at timestamp with time zone',
             'remarks character varying', 'status text'],
       ARRAY['clearance_item_id bigint', 'clearance_id bigint', 'department_id bigint',
             'cleared_by uuid', 'cleared_at timestamp with time zone',
             'remarks character varying', 'status text',
             'student_id uuid', 'term_id bigint',
             'department_name character varying', 'department_type character varying']),
      ('v_clearances',
       ARRAY['clearance_id bigint', 'student_id uuid', 'term_id bigint',
             'created_at timestamp with time zone', 'approved_by uuid',
             'approved_at timestamp with time zone', 'status text'],
       ARRAY['clearance_id bigint', 'student_id uuid', 'term_id bigint',
             'created_at timestamp with time zone', 'approved_by uuid',
             'approved_at timestamp with time zone', 'status text',
             'total_items integer', 'cleared_items integer']),
      ('v_grades',
       ARRAY['grade_id bigint', 'enrollment_item_id bigint', 'grade_code character varying',
             'numeric_value numeric', 'is_passing boolean', 'encoded_by uuid',
             'encoded_at timestamp with time zone'],
       ARRAY['grade_id bigint', 'enrollment_item_id bigint', 'grade_code character varying',
             'numeric_value numeric', 'is_passing boolean', 'encoded_by uuid',
             'encoded_at timestamp with time zone',
             'enrollment_id bigint', 'student_id uuid', 'term_id bigint',
             'section_id bigint', 'subject_id bigint',
             'subject_code character varying', 'subject_title character varying',
             'units smallint'])
    ) AS t(view_name, old_cols, new_cols)
  LOOP
    SELECT c.relkind, c.reloptions INTO v_kind, v_opts
    FROM pg_catalog.pg_class c
    WHERE c.oid = pg_catalog.to_regclass('public.' || r.view_name);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'views_extend: public.% does not exist; stop (a new view would get default grants, including anon)', r.view_name;
    END IF;
    IF v_kind <> 'v' THEN
      RAISE EXCEPTION 'views_extend: public.% is not a plain view (relkind %); stop', r.view_name, v_kind;
    END IF;
    IF v_opts IS NULL OR NOT (v_opts && ARRAY['security_invoker=true', 'security_invoker=on',
                                              'security_invoker=1', 'security_invoker=yes']) THEN
      RAISE EXCEPTION 'views_extend: public.% is not security_invoker (reloptions %); stop and review', r.view_name, v_opts;
    END IF;

    SELECT array_agg(c.column_name::text || ' ' || c.data_type::text ORDER BY c.ordinal_position)
    INTO v_cols
    FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = r.view_name;

    IF v_cols IS DISTINCT FROM r.old_cols AND v_cols IS DISTINCT FROM r.new_cols THEN
      RAISE EXCEPTION 'views_extend: public.% has unexpected columns %; expected % (before) or % (after); stop and review',
        r.view_name, v_cols, r.old_cols, r.new_cols;
    END IF;
  END LOOP;
END $$;


-- ------------------------------------------
-- 2. The 3 extended views
-- ------------------------------------------
-- Each select list starts with the old columns of views.sql, same names, types and
-- order (only table aliases added where a join makes a name ambiguous); the new columns
-- follow. WITH (security_invoker = true) is stated again on purpose (see the header).

-- v_clearance_items: + student_id, term_id (clearances), department_name,
-- department_type (departments). LEFT JOINs: the item row must stay visible even if the
-- caller cannot read the clearance (then student_id / term_id are NULL); departments is
-- readable by everyone and the FK is NOT NULL, so that join always matches.
-- status is unchanged ('Pending' / 'Cleared', same as lib/mock-data.ts).
CREATE OR REPLACE VIEW public.v_clearance_items WITH (security_invoker = true) AS
 SELECT ci.clearance_item_id,
    ci.clearance_id,
    ci.department_id,
    ci.cleared_by,
    ci.cleared_at,
    ci.remarks,
        CASE
            WHEN (ci.cleared_at IS NULL) THEN 'Pending'::text
            ELSE 'Cleared'::text
        END AS status,
    c.student_id,
    c.term_id,
    d.name AS department_name,
    d.department_type
   FROM ((public.clearance_items ci
     LEFT JOIN public.clearances c ON ((c.clearance_id = ci.clearance_id)))
     LEFT JOIN public.departments d ON ((d.department_id = ci.department_id)));

-- v_clearances: + total_items, cleared_items. Scalar subqueries (no join, so the
-- clearance row can never be hidden or duplicated); cast to integer (count() is bigint;
-- both are "number" in the types file). cleared = cleared_at IS NOT NULL, as in
-- lib/mock-data.ts. The counts follow the caller's RLS on clearance_items (see header:
-- Cashier / Department count only their own department's items).
-- status is unchanged ('In Progress' / 'Approved'); see the NOTE about 'Ready' below.
CREATE OR REPLACE VIEW public.v_clearances WITH (security_invoker = true) AS
 SELECT clearance_id,
    student_id,
    term_id,
    created_at,
    approved_by,
    approved_at,
        CASE
            WHEN (approved_at IS NULL) THEN 'In Progress'::text
            ELSE 'Approved'::text
        END AS status,
    (( SELECT count(*) AS count
           FROM public.clearance_items ci
          WHERE (ci.clearance_id = clearances.clearance_id)))::integer AS total_items,
    (( SELECT count(*) AS count
           FROM public.clearance_items ci
          WHERE ((ci.clearance_id = clearances.clearance_id) AND (ci.cleared_at IS NOT NULL))))::integer AS cleared_items
   FROM public.clearances;

-- v_grades: + enrollment_id, student_id, term_id, section_id, subject_id, subject_code,
-- subject_title, units. The existing INNER JOIN to grade_scale is kept as it was. The
-- new joins are LEFT JOINs so v_grades keeps exactly the rows it returned before: a
-- grade the caller can read never disappears because a joined row is hidden; the new
-- columns are then NULL. (The readers of grades and of enrollment_items / enrollments
-- are the same, and sections / subjects are readable by all, so in practice they are
-- filled.) enrollment_id and section_id come from enrollment_items, student_id and
-- term_id from enrollments (as lib/mock-data.ts does), subject_* from subjects.
-- units stays smallint (subjects.units; "number" in the types file).
CREATE OR REPLACE VIEW public.v_grades WITH (security_invoker = true) AS
 SELECT g.grade_id,
    g.enrollment_item_id,
    g.grade_code,
    s.numeric_value,
    s.is_passing,
    g.encoded_by,
    g.encoded_at,
    ei.enrollment_id,
    e.student_id,
    e.term_id,
    ei.section_id,
    sec.subject_id,
    sub.code AS subject_code,
    sub.title AS subject_title,
    sub.units
   FROM (((((public.grades g
     JOIN public.grade_scale s ON (((s.grade_code)::text = (g.grade_code)::text)))
     LEFT JOIN public.enrollment_items ei ON ((ei.enrollment_item_id = g.enrollment_item_id)))
     LEFT JOIN public.enrollments e ON ((e.enrollment_id = ei.enrollment_id)))
     LEFT JOIN public.sections sec ON ((sec.section_id = ei.section_id)))
     LEFT JOIN public.subjects sub ON ((sub.subject_id = sec.subject_id)));

-- v_active_holds: not changed (already has every column of the types file).


-- ------------------------------------------
-- 3. Checks after the change (still inside the transaction; a failure undoes it all)
-- ------------------------------------------
-- All 4 views: still security_invoker, every column of types/database.types.ts present,
-- authenticated can still SELECT, anon cannot (state after hardening2.sql section C).
DO $$
DECLARE
  r         record;
  v_opts    text[];
  v_missing text[];
BEGIN
  FOR r IN
    SELECT *
    FROM (VALUES
      ('v_active_holds',
       ARRAY['hold_id', 'student_id', 'department_id', 'reason', 'placed_by', 'placed_at']),
      ('v_clearance_items',
       ARRAY['clearance_item_id', 'clearance_id', 'student_id', 'term_id', 'department_id',
             'department_name', 'department_type', 'cleared_at', 'cleared_by', 'remarks',
             'status']),
      ('v_clearances',
       ARRAY['clearance_id', 'student_id', 'term_id', 'created_at', 'approved_by',
             'approved_at', 'total_items', 'cleared_items', 'status']),
      ('v_grades',
       ARRAY['grade_id', 'enrollment_item_id', 'enrollment_id', 'student_id', 'term_id',
             'section_id', 'subject_id', 'subject_code', 'subject_title', 'units',
             'grade_code', 'numeric_value', 'is_passing', 'encoded_by', 'encoded_at'])
    ) AS t(view_name, type_cols)
  LOOP
    SELECT c.reloptions INTO v_opts
    FROM pg_catalog.pg_class c
    WHERE c.oid = pg_catalog.to_regclass('public.' || r.view_name);
    IF v_opts IS NULL OR NOT (v_opts && ARRAY['security_invoker=true', 'security_invoker=on',
                                              'security_invoker=1', 'security_invoker=yes']) THEN
      RAISE EXCEPTION 'views_extend: after the change public.% is not security_invoker (reloptions %); rolled back', r.view_name, v_opts;
    END IF;

    SELECT array_agg(x) INTO v_missing
    FROM unnest(r.type_cols) AS x
    WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c
                      WHERE c.table_schema = 'public' AND c.table_name = r.view_name
                        AND c.column_name = x);
    IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION 'views_extend: public.% is missing columns %; rolled back', r.view_name, v_missing;
    END IF;

    IF NOT has_table_privilege('authenticated', 'public.' || r.view_name, 'SELECT') THEN
      RAISE EXCEPTION 'views_extend: authenticated lost SELECT on public.%; rolled back', r.view_name;
    END IF;
    IF has_table_privilege('anon', 'public.' || r.view_name, 'SELECT') THEN
      RAISE EXCEPTION 'views_extend: anon can SELECT public.% (expected no access after hardening2.sql section C); rolled back, review the grants first', r.view_name;
    END IF;
  END LOOP;
END $$;

COMMIT;


-- NOTE (not changed here, a decision for the PM): lib/mock-data.ts gives v_clearances a
-- third status 'Ready' (all items cleared, not yet approved). The live view only has
-- 'In Progress' / 'Approved', and this file keeps the live status expression unchanged.
-- The app can derive "ready" from cleared_items = total_items, or the status CASE can be
-- changed later in a separate, reviewed change (same name and type, so CREATE OR REPLACE
-- allows it). Note that the mock also says 'Ready' for a clearance with 0 items.


-- ------------------------------------------
-- ROLLBACK (restores the exact previous definitions from views.sql)
-- ------------------------------------------
-- CREATE OR REPLACE cannot remove columns, so the rollback must DROP and CREATE the 3
-- views. A DROP + CREATE does NOT keep the grants: the new view gets the owner's
-- default privileges (Supabase's pg_default_acl, which include anon), so the grants are
-- set again explicitly below (state after hardening2.sql section C: authenticated
-- SELECT only, no anon). The view owner becomes the role that runs it (postgres).
-- DROP is without CASCADE: if anything depends on a view, it stops with an error and
-- the whole block rolls back. Table names are unqualified, verbatim from views.sql, so
-- run it with the editor's default search_path (public).
-- Afterwards compare with the saved output of diagnostics (a), (b) and (c). Supabase's
-- server role had leftover TRUNCATE / REFERENCES / TRIGGER / MAINTAIN on the views
-- (grants_snapshot_2026-10-10.txt); after a re-create it gets the defaults instead. If
-- (c) differs for it, adjust by hand (its name is left out of this repo on purpose).
--
-- BEGIN;
--
-- DROP VIEW IF EXISTS public.v_grades;
-- DROP VIEW IF EXISTS public.v_clearance_items;
-- DROP VIEW IF EXISTS public.v_clearances;
--
-- CREATE VIEW public.v_clearance_items WITH (security_invoker = true) AS
--  SELECT clearance_item_id,
--     clearance_id,
--     department_id,
--     cleared_by,
--     cleared_at,
--     remarks,
--         CASE
--             WHEN (cleared_at IS NULL) THEN 'Pending'::text
--             ELSE 'Cleared'::text
--         END AS status
--    FROM clearance_items;
--
-- CREATE VIEW public.v_clearances WITH (security_invoker = true) AS
--  SELECT clearance_id,
--     student_id,
--     term_id,
--     created_at,
--     approved_by,
--     approved_at,
--         CASE
--             WHEN (approved_at IS NULL) THEN 'In Progress'::text
--             ELSE 'Approved'::text
--         END AS status
--    FROM clearances;
--
-- CREATE VIEW public.v_grades WITH (security_invoker = true) AS
--  SELECT g.grade_id,
--     g.enrollment_item_id,
--     g.grade_code,
--     s.numeric_value,
--     s.is_passing,
--     g.encoded_by,
--     g.encoded_at
--    FROM (grades g
--      JOIN grade_scale s ON (((s.grade_code)::text = (g.grade_code)::text)));
--
-- -- Grants: back to the state after hardening2.sql section C.
-- REVOKE ALL ON public.v_grades, public.v_clearance_items, public.v_clearances FROM PUBLIC, anon, authenticated;
-- GRANT SELECT ON public.v_grades, public.v_clearance_items, public.v_clearances TO authenticated;
--
-- COMMIT;


-- ==========================================
-- DIAGNOSTICS (read-only; run one at a time)
-- ==========================================
-- Nothing here changes the database. Run (a), (b) and (c) BEFORE the change and save the
-- output; run them again afterwards to compare.
--
-- a) Columns of the 4 views, in order, with types:
-- select table_name, ordinal_position, column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name in ('v_active_holds', 'v_clearance_items', 'v_clearances', 'v_grades')
-- order by table_name, ordinal_position;
--
-- b) View options (each must show {security_invoker=true}; null means the view runs as
--    its owner and ignores RLS):
-- select c.relname, c.reloptions, pg_get_userbyid(c.relowner) as owner
-- from pg_class c
-- where c.relnamespace = 'public'::regnamespace
--   and c.relname in ('v_active_holds', 'v_clearance_items', 'v_clearances', 'v_grades')
-- order by c.relname;
--
-- c) Grants (ACLs) of the 4 views:
-- select c.relname, c.relacl::text as acl
-- from pg_class c
-- where c.relnamespace = 'public'::regnamespace
--   and c.relname in ('v_active_holds', 'v_clearance_items', 'v_clearances', 'v_grades')
-- order by c.relname;
--
-- d) Current definitions (to update views.sql after the change):
-- select viewname, definition from pg_views
-- where schemaname = 'public' and viewname like 'v\_%' order by viewname;
