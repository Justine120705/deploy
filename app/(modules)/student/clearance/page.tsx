import DashboardShell from '@/components/layout/DashboardShell'
import ClearanceOverview from '@/components/student/ClearanceOverview'
import { requireRole } from '@/lib/auth/session'
import {
  MOCK_CURRENT_TERM_ID,
  MOCK_STUDENT_ID,
  programs,
  students,
  terms,
  vActiveHolds,
  vClearanceItems,
} from '@/lib/mock-data'

export default async function StudentClearancePage() {
  const profile = await requireRole('Student')

  const items = vClearanceItems.filter(
    (i) => i.student_id === MOCK_STUDENT_ID && i.term_id === MOCK_CURRENT_TERM_ID
  )
  // Signing order: the Cashier's Office (Financial) first, then the academic departments.
  const offices = [...items]
    .sort((a, b) => Number(b.department_type === 'Financial') - Number(a.department_type === 'Financial'))
    .map((i) => ({
      id: i.clearance_item_id ?? 0,
      name: i.department_name ?? 'Department',
      type: i.department_type ?? '-',
      status: i.status === 'Cleared' ? ('Cleared' as const) : ('Pending' as const),
      clearedAt: i.cleared_at,
      remarks: i.remarks,
    }))
  const activeHolds = vActiveHolds.filter((h) => h.student_id === MOCK_STUDENT_ID).length

  const term = terms.find((t) => t.term_id === MOCK_CURRENT_TERM_ID)
  const student = students.find((s) => s.student_id === MOCK_STUDENT_ID)
  const program = programs.find((p) => p.program_id === student?.program_id)
  const subtitle = [term ? `${term.semester} ${term.school_year}` : null, program?.code, 'one item per office']
    .filter(Boolean)
    .join(' · ')

  return (
    <DashboardShell profile={profile} title="My clearance" subtitle={subtitle}>
      <ClearanceOverview offices={offices} activeHolds={activeHolds} />
    </DashboardShell>
  )
}
