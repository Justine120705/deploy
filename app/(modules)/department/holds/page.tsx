import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import HoldsClient from '@/components/department/HoldsClient'
import { DeptUnavailable } from '@/components/department/DeptNotice'
import { countDepartment, getDepartmentState } from '@/lib/data/department'

export default async function DepartmentHoldsPage() {
  const profile = await requireRole('Department')
  const state = await getDepartmentState()
  if (state.kind !== 'ready') {
    return (
      <DashboardShell profile={profile} title="Academic Holds" subtitle="Place and lift holds for your own department">
        <DeptUnavailable kind={state.kind} />
      </DashboardShell>
    )
  }
  const counts = countDepartment(state.items, state.holds)
  const onHold = new Set(state.holds.filter((h) => h.status === 'Active').map((h) => h.studentId)).size
  const lifted = state.holds.filter((h) => h.status === 'Lifted').length
  return (
    <DashboardShell
      profile={profile}
      title="Academic Holds"
      subtitle={`${state.department.name} · place and lift holds for your own department`}
    >
      <HoldsClient
        holds={state.holds}
        students={state.students}
        departmentName={state.department.name}
        stats={[
          { label: 'Active holds', value: counts.activeHolds, hint: 'block approval', hue: counts.activeHolds ? 'rose' : undefined },
          { label: 'Students on hold', value: onHold, hint: 'right now' },
          { label: 'Lifted', value: lifted, hint: 'all time' },
          { label: 'Placed', value: state.holds.length, hint: 'all time' },
        ]}
      />
    </DashboardShell>
  )
}
