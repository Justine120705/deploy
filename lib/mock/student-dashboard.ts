// Mock data for the student dashboard (Figma "Student Dashboard"). Static on purpose: the numbers
// match the design. Replace with live queries when the dashboard is wired to the database.

export const DASHBOARD_UNITS_THIS_TERM = 9

/** GWA per term, oldest first. Lower is better. `short` fits under a bar on a phone; `full` is read
 *  out to screen readers. The last term is the latest one with grades (its GWA is the average of
 *  CURRENT_GRADES below). */
export const GWA_BY_TERM = [
  { short: 'Y1 S1', full: '1st Semester 2023-24', gwa: 2.5 },
  { short: 'Y1 S2', full: '2nd Semester 2023-24', gwa: 2.23 },
  { short: 'Y2 S1', full: '1st Semester 2024-25', gwa: 2.02 },
  { short: 'Y2 S2', full: '2nd Semester 2024-25', gwa: 1.62 },
  { short: 'Y3 S1', full: '1st Semester 2025-26', gwa: 2.16 },
  { short: 'Y3 S2', full: '2nd Semester 2025-26', gwa: 1.75 },
]
export const GWA_Y_TICKS = [1, 1.5, 2, 2.5, 3]

export const CURRENT_GRADES = [
  { code: 'CS101', course: 'Introduction to Computing', units: 3, grade: '1.75', remarks: 'Passed' },
  { code: 'CS102', course: 'Computer Programming 1', units: 3, grade: '2.00', remarks: 'Passed' },
  { code: 'GE101', course: 'Understanding the Self', units: 3, grade: '1.50', remarks: 'Passed' },
]

/** Clearance chain, in the order the offices sign. `reason` and `nextAction` explain a step that is
 *  not cleared yet. After every office clears, the Registrar gives the final approval. */
export const CLEARANCE_OFFICES = [
  { name: "Cashier's Office", note: 'Completed', status: 'Cleared', reason: '', nextAction: '' },
  { name: 'CBA Department', note: 'Completed', status: 'Cleared', reason: '', nextAction: '' },
  { name: 'CAS Department', note: 'Completed', status: 'Cleared', reason: '', nextAction: '' },
  {
    name: 'CCS Department',
    note: 'Awaiting review',
    status: 'Pending',
    reason: 'Awaiting department review',
    nextAction: 'No action needed, CCS Department is reviewing.',
  },
] as const

/** Academic holds that block clearance (none right now). */
export const ACTIVE_HOLDS = 0

/** Calendar shown on the dashboard: October 2026, "today" is the 5th. */
export const CALENDAR_VIEW = { year: 2026, month: 9, today: '2026-10-05' } // month is 0-based
export const CALENDAR_EVENTS = [
  { id: 'exam', title: 'Midterm examinations', tone: 'rose', dates: ['2026-10-09', '2026-10-30'] },
  { id: 'enroll', title: 'Enrollment advising', tone: 'sky', dates: ['2026-10-16'] },
  { id: 'fees', title: 'Fee payment deadline', tone: 'amber', dates: ['2026-10-23'] },
] as const

export const SCHEDULE = [
  // One hue per course (violet, sky, teal only; amber and rose mean attention and problems).
  { time: 'MWF 8-9 AM', title: 'Introduction to Computing', code: 'CS101', tone: 'violet' },
  { time: 'TTh 9-10:30 AM', title: 'Computer Programming 1', code: 'CS102', tone: 'sky' },
  { time: 'MWF 10-11 AM', title: 'Understanding the Self', code: 'GE101', tone: 'teal' },
] as const

/** Next class: one of SCHEDULE above (today, Monday 5 October, is a MWF day). `seconds` is a fixed
 *  sample countdown until real timetables are wired in. */
export const NEXT_CLASS = {
  title: 'Understanding the Self',
  code: 'GE101',
  startsAt: '10:00 AM',
  seconds: 42 * 60 + 18,
}
