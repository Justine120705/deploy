// Mock data for the Registrar screens (mirrors the Figma frames). Not read from the database.

export type EnrollmentStatus = 'Approved' | 'Pending' | 'Rejected'

export type EnrollmentRow = {
  id: string
  studentNo: string
  name: string
  program: string
  subjects: number
  status: EnrollmentStatus
  submitted: string
}

export const REGISTRAR_ENROLLMENTS: EnrollmentRow[] = [
  { id: 'e1', studentNo: '2026-0001', name: 'Reyes, Ana', program: 'BSCS', subjects: 3, status: 'Approved', submitted: 'Sep 20, 2026' },
  { id: 'e2', studentNo: '2026-0002', name: 'Santos, Ben', program: 'BSIT', subjects: 3, status: 'Pending', submitted: 'Sep 22, 2026' },
  { id: 'e3', studentNo: '2026-0003', name: 'Mendoza, Carla', program: 'BSBA', subjects: 3, status: 'Approved', submitted: 'Sep 21, 2026' },
]

export type DocumentStatus = 'Pending' | 'Processing' | 'Ready' | 'Released'

export type DocumentRow = {
  id: string
  ticket: string
  name: string
  document: string
  copies: number
  status: DocumentStatus
  requested: string
}

export const REGISTRAR_DOCUMENTS: DocumentRow[] = [
  { id: 'd1', ticket: 'DR-0001', name: 'Reyes, Ana', document: 'Official Transcript of Records', copies: 1, status: 'Processing', requested: 'Sep 24, 2026' },
  { id: 'd2', ticket: 'DR-0002', name: 'Santos, Ben', document: 'Certificate of Grades', copies: 1, status: 'Pending', requested: 'Sep 26, 2026' },
  { id: 'd3', ticket: 'DR-0003', name: 'Mendoza, Carla', document: 'Certificate of Grades', copies: 2, status: 'Ready', requested: 'Sep 25, 2026' },
]

export type ClearanceRow = {
  id: string
  studentNo: string
  name: string
  cleared: number
  total: number
  holds: number
  status: 'Pending' | 'Approved'
  requested: string
}

export const REGISTRAR_CLEARANCES: ClearanceRow[] = [
  { id: 'c1', studentNo: '2026-0001', name: 'Reyes, Ana', cleared: 3, total: 4, holds: 0, status: 'Pending', requested: 'Sep 23, 2026' },
  { id: 'c2', studentNo: '2026-0002', name: 'Santos, Ben', cleared: 2, total: 4, holds: 1, status: 'Pending', requested: 'Sep 23, 2026' },
  { id: 'c3', studentNo: '2026-0003', name: 'Mendoza, Carla', cleared: 3, total: 4, holds: 0, status: 'Pending', requested: 'Sep 24, 2026' },
]

// Grade scale used by the Encode Grades screen.
export const GRADE_SCALE: Record<string, string> = {
  '1.00': 'Excellent',
  '1.25': 'Superior',
  '1.50': 'Very Good',
  '1.75': 'Good',
  '2.00': 'Meritorious',
  '2.25': 'Very Satisfactory',
  '2.50': 'Satisfactory',
  '2.75': 'Fair',
  '3.00': 'Passing',
  '5.00': 'Failed',
}

export type GradeSeed = { no: string; name: string; grade: string; saved: string }

const FIRST_ROWS: GradeSeed[] = [
  { no: '2026-0001', name: 'Reyes, Ana', grade: '1.75', saved: '1.75' },
  { no: '2026-0002', name: 'Santos, Ben', grade: '2.25', saved: '2.25' },
  { no: '2026-0003', name: 'Mendoza, Carla', grade: '1.50', saved: '' },
  { no: '2026-0004', name: 'Garcia, Miguel R.', grade: '', saved: '' },
  { no: '2026-0005', name: 'Mendoza, Sofia T.', grade: '9.00', saved: '' },
  { no: '2026-0006', name: 'Ramos, Daniel P.', grade: '1.25', saved: '1.25' },
  { no: '2026-0007', name: 'Torres, Bianca K.', grade: '5.00', saved: '5.00' },
  { no: '2026-0008', name: 'Villanueva, Carlo J.', grade: '2.00', saved: '' },
]

const SURNAMES = ['Aquino', 'Bautista', 'Castro', 'Dela Cruz', 'Estrada', 'Flores', 'Gonzales', 'Hernandez', 'Ignacio', 'Jimenez', 'Lopez', 'Manalo', 'Navarro', 'Ocampo', 'Pascual', 'Quizon', 'Rivera', 'Salazar']
const GIVEN = ['Liza M.', 'Mark A.', 'Joy C.', 'Paolo D.']
const GOOD_GRADES = ['1.25', '1.50', '1.75', '2.00', '2.25', '2.50', '2.75', '3.00']

// 42 students in the section: the 8 from the design plus 34 generated ones (28 encoded, 6 not yet; 33 encoded in all).
export const GRADE_SEEDS: GradeSeed[] = [
  ...FIRST_ROWS,
  ...Array.from({ length: 34 }, (_, i): GradeSeed => {
    const n = i + 9
    const grade = i % 5 === 4 ? '' : GOOD_GRADES[i % GOOD_GRADES.length]
    return {
      no: `2026-${String(n).padStart(4, '0')}`,
      name: `${SURNAMES[i % SURNAMES.length]}, ${GIVEN[i % GIVEN.length]}`,
      grade,
      saved: grade,
    }
  }),
]
