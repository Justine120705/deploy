// Mock data for the Department head screens (no database yet). Dates are display strings.

export type DeptStudent = { studentNo: string; name: string; program: string }

export type DeptClearanceItem = {
  studentNo: string
  status: 'Pending' | 'Cleared' | 'Rejected'
  requestedOn: string
  clearedOn: string | null
  remarks?: string
}

export type DeptHold = {
  id: string
  studentNo: string
  reason: string
  placedBy: string
  placedOn: string
  status: 'Active' | 'Lifted'
  liftedOn: string | null
}

export const DEPT_NAME = 'CCS Department'
export const DEPT_USER = 'CCS Staff'

export const DEPT_STUDENTS: DeptStudent[] = [
  { studentNo: '2026-0001', name: 'Reyes, Ana', program: 'BSCS' },
  { studentNo: '2026-0002', name: 'Santos, Ben', program: 'BSIT' },
  { studentNo: '2026-0003', name: 'Mendoza, Carla', program: 'BSBA' },
]

export const DEPT_CLEARANCE_ITEMS: DeptClearanceItem[] = [
  { studentNo: '2026-0001', status: 'Pending', requestedOn: 'Sep 23, 2026', clearedOn: null },
  { studentNo: '2026-0002', status: 'Pending', requestedOn: 'Sep 23, 2026', clearedOn: null },
  { studentNo: '2026-0003', status: 'Cleared', requestedOn: 'Sep 22, 2026', clearedOn: 'Sep 24, 2026' },
]

export const DEPT_HOLDS: DeptHold[] = [
  {
    id: 'hold-1',
    studentNo: '2026-0002',
    reason: 'Missing lab equipment',
    placedBy: 'CCS Staff',
    placedOn: 'Sep 22, 2026',
    status: 'Active',
    liftedOn: null,
  },
  {
    id: 'hold-2',
    studentNo: '2026-0003',
    reason: 'Advising required',
    placedBy: 'CCS Staff',
    placedOn: 'Sep 21, 2026',
    status: 'Lifted',
    liftedOn: 'Sep 22, 2026',
  },
]

export function studentByNo(studentNo: string): DeptStudent {
  return (
    DEPT_STUDENTS.find((s) => s.studentNo === studentNo) ?? { studentNo, name: studentNo, program: '' }
  )
}
