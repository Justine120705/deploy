/**
 * Shared mock data for frontend prototyping (Issue 8).
 *
 * Rules
 * - Field names come from `types/database.types.ts` (ERD v3), so swapping a mock
 *   array for a live Supabase query later needs no renaming.
 * - Every array is typed with `Tables<...>`; a wrong or missing column fails `npm run build`.
 * - Data is fictional (ETH-01 / ETH-02): no real student records, no real e-mails.
 * - No `Date.now()` or randomness, so server and client renders always match.
 * - The row counts mirror the Issue 10 login test, so a mock page and the live
 *   "Database check" box agree: 7 profiles, 3 enrollments, 3 charges and
 *   3 clearance items for the department head's department.
 */
import type { Tables } from "@/types/database.types";

type ViewRow<V extends "v_active_holds" | "v_clearance_items" | "v_clearances" | "v_grades"> =
  Tables<V>;

/* -------------------------------------------------------------------------- */
/* Fixed IDs (profile_id equals auth.users.id in the live database)           */
/* -------------------------------------------------------------------------- */

export const MOCK_IDS = {
  admin: "00000000-0000-4000-8000-000000000001",
  registrar: "00000000-0000-4000-8000-000000000002",
  cashier: "00000000-0000-4000-8000-000000000003",
  department: "00000000-0000-4000-8000-000000000004",
  student1: "00000000-0000-4000-8000-000000000005",
  student2: "00000000-0000-4000-8000-000000000006",
  student3: "00000000-0000-4000-8000-000000000007",
} as const;

export const MOCK_CURRENT_TERM_ID = 1;
/** Student shown on the student module pages until live auth data replaces the mocks. */
export const MOCK_STUDENT_ID = MOCK_IDS.student2;
export const MOCK_CASHIER_DEPARTMENT_ID = 2;

/* -------------------------------------------------------------------------- */
/* Identity & Access                                                          */
/* -------------------------------------------------------------------------- */

export const roles: Tables<"roles">[] = [
  { role_id: 1, role_name: "Student" },
  { role_id: 2, role_name: "Registrar" },
  { role_id: 3, role_name: "Cashier" },
  { role_id: 4, role_name: "Department" },
  { role_id: 5, role_name: "Admin" },
];

export const profiles: Tables<"profiles">[] = [
  { profile_id: MOCK_IDS.admin, role_id: 5, first_name: "Alex", last_name: "Admin", email: "admin@portal.test", is_active: true, created_at: "2026-08-01T08:00:00+08:00" },
  { profile_id: MOCK_IDS.registrar, role_id: 2, first_name: "Rosa", last_name: "Registrar", email: "registrar@portal.test", is_active: true, created_at: "2026-08-01T08:05:00+08:00" },
  { profile_id: MOCK_IDS.cashier, role_id: 3, first_name: "Carlo", last_name: "Cashier", email: "cashier@portal.test", is_active: true, created_at: "2026-08-01T08:10:00+08:00" },
  { profile_id: MOCK_IDS.department, role_id: 4, first_name: "Dina", last_name: "Department", email: "dept@portal.test", is_active: true, created_at: "2026-08-01T08:15:00+08:00" },
  { profile_id: MOCK_IDS.student1, role_id: 1, first_name: "Mia", last_name: "Santos", email: "student1@portal.test", is_active: true, created_at: "2026-08-01T08:20:00+08:00" },
  { profile_id: MOCK_IDS.student2, role_id: 1, first_name: "Luis", last_name: "Reyes", email: "student2@portal.test", is_active: true, created_at: "2026-08-01T08:25:00+08:00" },
  { profile_id: MOCK_IDS.student3, role_id: 1, first_name: "Ana", last_name: "Lopez", email: "student3@portal.test", is_active: true, created_at: "2026-08-01T08:30:00+08:00" },
];

export const students: Tables<"students">[] = [
  { student_id: MOCK_IDS.student1, student_number: "2026-00001", program_id: 1 },
  { student_id: MOCK_IDS.student2, student_number: "2026-00002", program_id: 1 },
  { student_id: MOCK_IDS.student3, student_number: "2026-00003", program_id: 2 },
];

export const departmentStaff: Tables<"department_staff">[] = [
  { profile_id: MOCK_IDS.department, department_id: 1 },
];

/* -------------------------------------------------------------------------- */
/* Academic Structure                                                         */
/* -------------------------------------------------------------------------- */

export const departments: Tables<"departments">[] = [
  { department_id: 1, code: "CCS", name: "College of Computer Studies", department_type: "Academic" },
  { department_id: MOCK_CASHIER_DEPARTMENT_ID, code: "CASH", name: "Cashier's Office", department_type: "Financial" },
];

export const terms: Tables<"terms">[] = [
  { term_id: 1, school_year: "2026-2027", semester: "1st Sem", start_date: "2026-08-17", end_date: "2026-12-18", is_current: true },
  { term_id: 2, school_year: "2025-2026", semester: "2nd Sem", start_date: "2026-01-12", end_date: "2026-05-29", is_current: false },
];

export const programs: Tables<"programs">[] = [
  { program_id: 1, department_id: 1, code: "BSCS", name: "Bachelor of Science in Computer Science" },
  { program_id: 2, department_id: 1, code: "BSIT", name: "Bachelor of Science in Information Technology" },
];

export const subjects: Tables<"subjects">[] = [
  { subject_id: 1, department_id: 1, code: "CS101", title: "Introduction to Computing", units: 3 },
  { subject_id: 2, department_id: 1, code: "CS102", title: "Computer Programming 1", units: 3 },
  { subject_id: 3, department_id: 1, code: "CS103", title: "Discrete Mathematics", units: 3 },
  { subject_id: 4, department_id: 1, code: "CS104", title: "Human-Computer Interaction", units: 3 },
];

export const sections: Tables<"sections">[] = [
  { section_id: 1, subject_id: 1, term_id: 1, section_code: "BSCS1-A", schedule: "Mon/Wed 08:00-09:30", capacity: 40 },
  { section_id: 2, subject_id: 2, term_id: 1, section_code: "BSCS1-A", schedule: "Tue/Thu 08:00-09:30", capacity: 40 },
  { section_id: 3, subject_id: 3, term_id: 1, section_code: "BSCS1-A", schedule: "Mon/Wed 10:00-11:30", capacity: 40 },
  { section_id: 4, subject_id: 4, term_id: 1, section_code: "BSCS1-A", schedule: "Fri 13:00-16:00", capacity: 40 },
  { section_id: 5, subject_id: 1, term_id: 1, section_code: "BSIT1-A", schedule: "Mon/Wed 13:00-14:30", capacity: 40 },
  { section_id: 6, subject_id: 2, term_id: 1, section_code: "BSIT1-A", schedule: "Tue/Thu 13:00-14:30", capacity: 40 },
  { section_id: 7, subject_id: 3, term_id: 1, section_code: "BSIT1-A", schedule: null, capacity: 40 },
];

/* -------------------------------------------------------------------------- */
/* Enrollment & Grades                                                        */
/* -------------------------------------------------------------------------- */

export const gradeScale: Tables<"grade_scale">[] = [
  { grade_code: "1.00", numeric_value: 1.0, is_passing: true, description: "Excellent" },
  { grade_code: "1.25", numeric_value: 1.25, is_passing: true, description: "Superior" },
  { grade_code: "1.50", numeric_value: 1.5, is_passing: true, description: "Very Good" },
  { grade_code: "1.75", numeric_value: 1.75, is_passing: true, description: "Good" },
  { grade_code: "2.00", numeric_value: 2.0, is_passing: true, description: "Meritorious" },
  { grade_code: "2.25", numeric_value: 2.25, is_passing: true, description: "Very Satisfactory" },
  { grade_code: "2.50", numeric_value: 2.5, is_passing: true, description: "Satisfactory" },
  { grade_code: "2.75", numeric_value: 2.75, is_passing: true, description: "Fairly Satisfactory" },
  { grade_code: "3.00", numeric_value: 3.0, is_passing: true, description: "Passed" },
  { grade_code: "5.00", numeric_value: 5.0, is_passing: false, description: "Failed" },
  { grade_code: "INC", numeric_value: null, is_passing: false, description: "Incomplete" },
  { grade_code: "DRP", numeric_value: null, is_passing: false, description: "Dropped" },
];

export const enrollments: Tables<"enrollments">[] = [
  { enrollment_id: 1, student_id: MOCK_IDS.student1, term_id: 1, year_level: 1, status: "Approved", submitted_at: "2026-08-10T10:00:00+08:00", reviewed_by: MOCK_IDS.registrar, reviewed_at: "2026-08-11T09:00:00+08:00", remarks: null },
  { enrollment_id: 2, student_id: MOCK_IDS.student2, term_id: 1, year_level: 1, status: "Approved", submitted_at: "2026-08-10T10:30:00+08:00", reviewed_by: MOCK_IDS.registrar, reviewed_at: "2026-08-11T09:15:00+08:00", remarks: null },
  { enrollment_id: 3, student_id: MOCK_IDS.student3, term_id: 1, year_level: 1, status: "Pending", submitted_at: "2026-08-12T14:00:00+08:00", reviewed_by: null, reviewed_at: null, remarks: null },
];

export const enrollmentItems: Tables<"enrollment_items">[] = [
  { enrollment_item_id: 1, enrollment_id: 1, section_id: 1 },
  { enrollment_item_id: 2, enrollment_id: 1, section_id: 2 },
  { enrollment_item_id: 3, enrollment_id: 1, section_id: 3 },
  { enrollment_item_id: 4, enrollment_id: 1, section_id: 4 },
  { enrollment_item_id: 5, enrollment_id: 2, section_id: 1 },
  { enrollment_item_id: 6, enrollment_id: 2, section_id: 2 },
  { enrollment_item_id: 7, enrollment_id: 2, section_id: 3 },
  { enrollment_item_id: 8, enrollment_id: 3, section_id: 5 },
  { enrollment_item_id: 9, enrollment_id: 3, section_id: 6 },
  { enrollment_item_id: 10, enrollment_id: 3, section_id: 7 },
];

export const grades: Tables<"grades">[] = [
  { grade_id: 1, enrollment_item_id: 1, grade_code: "1.50", encoded_by: MOCK_IDS.registrar, encoded_at: "2026-12-10T10:00:00+08:00" },
  { grade_id: 2, enrollment_item_id: 2, grade_code: "1.75", encoded_by: MOCK_IDS.registrar, encoded_at: "2026-12-10T10:05:00+08:00" },
  { grade_id: 3, enrollment_item_id: 3, grade_code: "2.00", encoded_by: MOCK_IDS.registrar, encoded_at: "2026-12-10T10:10:00+08:00" },
  { grade_id: 4, enrollment_item_id: 4, grade_code: "1.25", encoded_by: MOCK_IDS.registrar, encoded_at: "2026-12-10T10:15:00+08:00" },
  { grade_id: 5, enrollment_item_id: 5, grade_code: "2.25", encoded_by: MOCK_IDS.registrar, encoded_at: "2026-12-10T10:20:00+08:00" },
  { grade_id: 6, enrollment_item_id: 6, grade_code: "2.75", encoded_by: MOCK_IDS.registrar, encoded_at: "2026-12-10T10:25:00+08:00" },
  { grade_id: 7, enrollment_item_id: 7, grade_code: "INC", encoded_by: MOCK_IDS.registrar, encoded_at: "2026-12-10T10:30:00+08:00" },
];

/* -------------------------------------------------------------------------- */
/* Finance                                                                    */
/* -------------------------------------------------------------------------- */

export const feeTypes: Tables<"fee_types">[] = [
  { fee_type_id: 1, name: "Tuition" },
  { fee_type_id: 2, name: "Laboratory Fee" },
  { fee_type_id: 3, name: "Miscellaneous Fee" },
];

export const charges: Tables<"charges">[] = [
  { charge_id: 1, student_id: MOCK_IDS.student1, term_id: 1, fee_type_id: 1, amount: 18500.0, due_date: "2026-09-15", status: "Cleared" },
  { charge_id: 2, student_id: MOCK_IDS.student2, term_id: 1, fee_type_id: 1, amount: 18500.0, due_date: "2026-09-15", status: "Unpaid" },
  { charge_id: 3, student_id: MOCK_IDS.student3, term_id: 1, fee_type_id: 1, amount: 16000.0, due_date: "2026-09-15", status: "Unpaid" },
];

export const payments: Tables<"payments">[] = [
  { payment_id: 1, charge_id: 1, amount_paid: 10000.0, paid_at: "2026-08-14T11:00:00+08:00", receipt_number: "OR-2026-0001", recorded_by: MOCK_IDS.cashier },
  { payment_id: 2, charge_id: 1, amount_paid: 8500.0, paid_at: "2026-09-02T10:30:00+08:00", receipt_number: "OR-2026-0002", recorded_by: MOCK_IDS.cashier },
  { payment_id: 3, charge_id: 2, amount_paid: 9000.0, paid_at: "2026-09-03T13:45:00+08:00", receipt_number: "OR-2026-0003", recorded_by: MOCK_IDS.cashier },
];

/* -------------------------------------------------------------------------- */
/* Clearance                                                                  */
/* -------------------------------------------------------------------------- */

export const clearances: Tables<"clearances">[] = [
  { clearance_id: 1, student_id: MOCK_IDS.student1, term_id: 1, created_at: "2026-11-20T09:00:00+08:00", approved_by: MOCK_IDS.registrar, approved_at: "2026-11-25T15:00:00+08:00" },
  { clearance_id: 2, student_id: MOCK_IDS.student2, term_id: 1, created_at: "2026-11-20T09:30:00+08:00", approved_by: null, approved_at: null },
  { clearance_id: 3, student_id: MOCK_IDS.student3, term_id: 1, created_at: "2026-11-21T08:45:00+08:00", approved_by: null, approved_at: null },
];

export const clearanceItems: Tables<"clearance_items">[] = [
  { clearance_item_id: 1, clearance_id: 1, department_id: 1, cleared_at: "2026-11-23T10:00:00+08:00", cleared_by: MOCK_IDS.department, remarks: null },
  { clearance_item_id: 2, clearance_id: 1, department_id: 2, cleared_at: "2026-09-02T10:31:00+08:00", cleared_by: MOCK_IDS.cashier, remarks: null },
  { clearance_item_id: 3, clearance_id: 2, department_id: 1, cleared_at: null, cleared_by: null, remarks: "Active hold: missing laboratory equipment" },
  { clearance_item_id: 4, clearance_id: 2, department_id: 2, cleared_at: null, cleared_by: null, remarks: "Outstanding balance" },
  { clearance_item_id: 5, clearance_id: 3, department_id: 1, cleared_at: null, cleared_by: null, remarks: null },
  { clearance_item_id: 6, clearance_id: 3, department_id: 2, cleared_at: null, cleared_by: null, remarks: null },
];

export const academicHolds: Tables<"academic_holds">[] = [
  { hold_id: 1, student_id: MOCK_IDS.student1, department_id: 1, reason: "Advising required", placed_by: MOCK_IDS.department, placed_at: "2026-08-20T09:00:00+08:00", lifted_by: MOCK_IDS.department, lifted_at: "2026-08-25T14:00:00+08:00" },
  { hold_id: 2, student_id: MOCK_IDS.student2, department_id: 1, reason: "Missing laboratory equipment", placed_by: MOCK_IDS.department, placed_at: "2026-11-22T11:00:00+08:00", lifted_by: null, lifted_at: null },
];

/* -------------------------------------------------------------------------- */
/* Document Requests                                                          */
/* -------------------------------------------------------------------------- */

export const documentTypes: Tables<"document_types">[] = [
  { document_type_id: 1, name: "Transcript of Records" },
  { document_type_id: 2, name: "Certificate of Enrollment" },
  { document_type_id: 3, name: "Certificate of Good Moral Character" },
];

export const documentRequests: Tables<"document_requests">[] = [
  { request_id: 1, ticket_number: "DOC-2026-0001", student_id: MOCK_IDS.student1, document_type_id: 2, purpose: "Scholarship application", copies: 1, status: "Released", requested_at: "2026-09-01T09:00:00+08:00", processed_by: MOCK_IDS.registrar, processed_at: "2026-09-03T14:00:00+08:00", remarks: null },
  { request_id: 2, ticket_number: "DOC-2026-0002", student_id: MOCK_IDS.student2, document_type_id: 1, purpose: "Transfer evaluation", copies: 2, status: "Pending", requested_at: "2026-09-05T10:15:00+08:00", processed_by: null, processed_at: null, remarks: null },
  { request_id: 3, ticket_number: "DOC-2026-0003", student_id: MOCK_IDS.student3, document_type_id: 3, purpose: "Internship requirement", copies: 1, status: "Processing", requested_at: "2026-09-06T08:50:00+08:00", processed_by: MOCK_IDS.registrar, processed_at: null, remarks: "Awaiting signature" },
];

/* -------------------------------------------------------------------------- */
/* Security & Audit                                                           */
/* -------------------------------------------------------------------------- */

export const auditLogs: Tables<"audit_logs">[] = [
  { log_id: 1, actor_id: MOCK_IDS.student3, action: "INSERT", table_name: "enrollments", record_id: "3", old_data: null, new_data: { enrollment_id: 3, status: "Pending" }, created_at: "2026-08-12T14:00:00+08:00" },
  { log_id: 2, actor_id: MOCK_IDS.registrar, action: "UPDATE", table_name: "enrollments", record_id: "1", old_data: { status: "Pending" }, new_data: { status: "Approved" }, created_at: "2026-08-11T09:00:00+08:00" },
  { log_id: 3, actor_id: MOCK_IDS.cashier, action: "UPDATE", table_name: "charges", record_id: "1", old_data: { status: "Unpaid" }, new_data: { status: "Cleared" }, created_at: "2026-09-02T10:31:00+08:00" },
  { log_id: 4, actor_id: MOCK_IDS.department, action: "INSERT", table_name: "academic_holds", record_id: "2", old_data: null, new_data: { hold_id: 2, reason: "Missing laboratory equipment" }, created_at: "2026-11-22T11:00:00+08:00" },
];

export const loginAttempts: Tables<"login_attempts">[] = [
  { attempt_id: 1, email: "student1@portal.test", ip_address: "203.0.113.10", was_successful: true, attempted_at: "2026-10-05T07:55:00+08:00" },
  { attempt_id: 2, email: "student2@portal.test", ip_address: "203.0.113.11", was_successful: false, attempted_at: "2026-10-05T08:01:00+08:00" },
  { attempt_id: 3, email: "student2@portal.test", ip_address: "203.0.113.11", was_successful: true, attempted_at: "2026-10-05T08:02:00+08:00" },
];

/* -------------------------------------------------------------------------- */
/* Views (derived from the tables above, like the database views)             */
/* -------------------------------------------------------------------------- */

export const vActiveHolds: ViewRow<"v_active_holds">[] = academicHolds
  .filter((h) => h.lifted_at === null)
  .map(({ hold_id, student_id, department_id, reason, placed_by, placed_at }) => ({
    hold_id,
    student_id,
    department_id,
    reason,
    placed_by,
    placed_at,
  }));

export const vClearanceItems: ViewRow<"v_clearance_items">[] = clearanceItems.map((item) => {
  const clearance = clearances.find((c) => c.clearance_id === item.clearance_id);
  const department = departments.find((d) => d.department_id === item.department_id);
  return {
    clearance_item_id: item.clearance_item_id,
    clearance_id: item.clearance_id,
    student_id: clearance?.student_id ?? null,
    term_id: clearance?.term_id ?? null,
    department_id: item.department_id,
    department_name: department?.name ?? null,
    department_type: department?.department_type ?? null,
    cleared_at: item.cleared_at,
    cleared_by: item.cleared_by,
    remarks: item.remarks,
    status: item.cleared_at ? "Cleared" : "Pending",
  };
});

export const vClearances: ViewRow<"v_clearances">[] = clearances.map((c) => {
  const items = clearanceItems.filter((i) => i.clearance_id === c.clearance_id);
  const cleared = items.filter((i) => i.cleared_at !== null).length;
  return {
    clearance_id: c.clearance_id,
    student_id: c.student_id,
    term_id: c.term_id,
    created_at: c.created_at,
    approved_by: c.approved_by,
    approved_at: c.approved_at,
    total_items: items.length,
    cleared_items: cleared,
    status: c.approved_at ? "Approved" : cleared === items.length ? "Ready" : "In Progress",
  };
});

export const vGrades: ViewRow<"v_grades">[] = grades.flatMap((g) => {
  const item = enrollmentItems.find((i) => i.enrollment_item_id === g.enrollment_item_id);
  const enrollment = enrollments.find((e) => e.enrollment_id === item?.enrollment_id);
  const section = sections.find((s) => s.section_id === item?.section_id);
  const subject = subjects.find((s) => s.subject_id === section?.subject_id);
  const scale = gradeScale.find((s) => s.grade_code === g.grade_code);
  if (!item || !enrollment || !section || !subject || !scale) return [];
  return [
    {
      grade_id: g.grade_id,
      enrollment_item_id: g.enrollment_item_id,
      enrollment_id: enrollment.enrollment_id,
      student_id: enrollment.student_id,
      term_id: enrollment.term_id,
      section_id: section.section_id,
      subject_id: subject.subject_id,
      subject_code: subject.code,
      subject_title: subject.title,
      units: subject.units,
      grade_code: g.grade_code,
      numeric_value: scale.numeric_value,
      is_passing: scale.is_passing,
      encoded_by: g.encoded_by,
      encoded_at: g.encoded_at,
    },
  ];
});

/* -------------------------------------------------------------------------- */
/* Small helpers (pure, no I/O)                                               */
/* -------------------------------------------------------------------------- */

/** Outstanding balance = total charges - total payments (REQ-CSH-01). */
export function getOutstandingBalance(studentId: string, termId: number = MOCK_CURRENT_TERM_ID): number {
  const studentCharges = charges.filter((c) => c.student_id === studentId && c.term_id === termId);
  const chargeIds = new Set(studentCharges.map((c) => c.charge_id));
  const billed = studentCharges.reduce((sum, c) => sum + c.amount, 0);
  const paid = payments.filter((p) => chargeIds.has(p.charge_id)).reduce((sum, p) => sum + p.amount_paid, 0);
  return Math.round((billed - paid) * 100) / 100;
}

export function getProfileByEmail(email: string): Tables<"profiles"> | undefined {
  return profiles.find((p) => p.email === email);
}

export function getRoleName(roleId: number): string | undefined {
  return roles.find((r) => r.role_id === roleId)?.role_name;
}

/** One-stop object that mirrors the database, for pages that want everything. */
export const mockDb = {
  roles, profiles, students, departmentStaff,
  departments, terms, programs, subjects, sections,
  gradeScale, enrollments, enrollmentItems, grades,
  feeTypes, charges, payments,
  documentTypes, documentRequests,
  clearances, clearanceItems, academicHolds,
  auditLogs, loginAttempts,
  vActiveHolds, vClearanceItems, vClearances, vGrades,
} as const;