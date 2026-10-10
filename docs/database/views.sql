-- ==========================================
-- VIEWS (schema public)
-- ==========================================
-- State of the live Supabase database after views_extend.sql was run on 2026-10-10 (issue #49)
-- and tested (TC-29 to TC-33 in docs/issue-12-testing-guide.md). v_active_holds is the original
-- export; v_clearance_items, v_clearances and v_grades are the extended definitions from
-- views_extend.sql (same SQL, not a fresh pg_views export, so the layout may differ slightly
-- from what pg_views prints). Every view has every column of types/database.types.ts.
-- All 4 views are security_invoker = true, so the RLS policies of the underlying tables
-- (including the joined ones) apply to the caller.
-- Grants: authenticated SELECT only, no anon (hardening2.sql section C).
-- Run AFTER schema.sql. Before views_extend.sql existed these 3 views had fewer columns
-- (see git history).

-- Columns: hold_id bigint, student_id uuid, department_id bigint, reason character varying, placed_by uuid, placed_at timestamp with time zone
CREATE OR REPLACE VIEW public.v_active_holds WITH (security_invoker = true) AS
 SELECT hold_id,
    student_id,
    department_id,
    reason,
    placed_by,
    placed_at
   FROM academic_holds
  WHERE (lifted_at IS NULL);

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
