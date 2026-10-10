-- ==========================================
-- VIEWS (schema public)
-- ==========================================
-- Exported from the live Supabase database (pg_views, schema public) on 2026-10-10.
-- Definitions are verbatim from the export. All 4 views are security_invoker = true,
-- so the RLS policies of the underlying tables apply to the caller.
-- Run AFTER schema.sql. Table names are unqualified, as exported (search_path public).

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

-- Columns: clearance_item_id bigint, clearance_id bigint, department_id bigint, cleared_by uuid, cleared_at timestamp with time zone, remarks character varying, status text
CREATE OR REPLACE VIEW public.v_clearance_items WITH (security_invoker = true) AS
 SELECT clearance_item_id,
    clearance_id,
    department_id,
    cleared_by,
    cleared_at,
    remarks,
        CASE
            WHEN (cleared_at IS NULL) THEN 'Pending'::text
            ELSE 'Cleared'::text
        END AS status
   FROM clearance_items;

-- Columns: clearance_id bigint, student_id uuid, term_id bigint, created_at timestamp with time zone, approved_by uuid, approved_at timestamp with time zone, status text
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
        END AS status
   FROM clearances;

-- Columns: grade_id bigint, enrollment_item_id bigint, grade_code character varying, numeric_value numeric, is_passing boolean, encoded_by uuid, encoded_at timestamp with time zone
CREATE OR REPLACE VIEW public.v_grades WITH (security_invoker = true) AS
 SELECT g.grade_id,
    g.enrollment_item_id,
    g.grade_code,
    s.numeric_value,
    s.is_passing,
    g.encoded_by,
    g.encoded_at
   FROM (grades g
     JOIN grade_scale s ON (((s.grade_code)::text = (g.grade_code)::text)));
