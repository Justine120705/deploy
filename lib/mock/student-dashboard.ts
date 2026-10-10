// Mock data for the student dashboard (Figma "Student Dashboard"). Static on purpose: the numbers
// match the design. Replace with live queries when the dashboard is wired to the database.

export const DASHBOARD_UNITS_THIS_TERM = 9

export const CLEARANCE_SUMMARY = { cleared: 3, total: 4 } // 75%

/** GWA per term. Lower is better. */
export const GWA_BY_TERM = [
  { term: 'T1', gwa: 2.5 },
  { term: 'T2', gwa: 2.23 },
  { term: 'T3', gwa: 2.36 },
  { term: 'T4', gwa: 2.02 },
  { term: 'T5', gwa: 1.75 },
  { term: 'T6', gwa: 2.16 },
]
export const CURRENT_GWA_TERM = 'T5'

/** GWA progress line, two points per term plus the start (13 points across T1..T6). */
export const GWA_PROGRESS = [2.4, 2.76, 2.2, 1.66, 2.34, 2.08, 2.3, 1.82, 1.2, 1.92, 2.76, 2.04, 2.0]
export const GWA_PROGRESS_X_LABELS = ['T1', 'T2', 'T3', 'T4', 'T5', 'T6']
export const GWA_PROGRESS_Y_TICKS = [1, 1.5, 2, 2.5, 3]

export const PENDING_ITEMS = [
  { title: 'CCS Department', value: 'Pending', note: 'Awaiting department review', attention: true },
  { title: 'Active holds', value: '0', note: 'No academic holds', attention: false },
]

export const CURRENT_GRADES = [
  { code: 'CS101', course: 'Introduction to Computing', units: 3, grade: '1.75', remarks: 'Passed' },
  { code: 'CS102', course: 'Computer Programming 1', units: 3, grade: '2.00', remarks: 'Passed' },
  { code: 'GE101', course: 'Understanding the Self', units: 3, grade: '1.50', remarks: 'Passed' },
]

export const CLEARANCE_OFFICES = [
  { name: "Cashier's Office", note: 'Completed', status: 'Cleared' },
  { name: 'CBA Department', note: 'Completed', status: 'Cleared' },
  { name: 'CAS Department', note: 'Completed', status: 'Cleared' },
  { name: 'CCS Department', note: 'Awaiting review', status: 'Pending' },
] as const

/** Calendar shown on the dashboard: October 2026, "today" is the 5th. */
export const CALENDAR_VIEW = { year: 2026, month: 9, today: '2026-10-05' } // month is 0-based
export const CALENDAR_EVENTS = [
  { id: 'exam', title: 'Midterm examinations', tone: 'rose', dates: ['2026-10-09', '2026-10-30'] },
  { id: 'enroll', title: 'Enrollment advising', tone: 'sky', dates: ['2026-10-16'] },
  { id: 'fees', title: 'Fee payment deadline', tone: 'amber', dates: ['2026-10-23'] },
] as const

export const SCHEDULE = [
  // One hue per course (violet, sky, teal only; amber and rose mean attention and problems).
  { time: 'MWF 8-9 AM', title: 'Intro to Computing', code: 'CS101', tone: 'violet' },
  { time: 'TTh 9-10:30', title: 'Programming 1', code: 'CS102', tone: 'sky' },
  { time: 'MWF 10-11 AM', title: 'Understanding Self', code: 'GE101', tone: 'teal' },
] as const

/** Seconds until the next class, shown as 00:42:18. */
export const NEXT_LESSON = { seconds: 42 * 60 + 18, title: 'Intro to Computing · CS101' }
