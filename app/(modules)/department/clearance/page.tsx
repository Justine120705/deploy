import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import ClearanceItemsClient from '@/components/department/ClearanceItemsClient'
import { DeptUnavailable } from '@/components/department/DeptNotice'
import { countDepartment, getDepartmentState } from '@/lib/data/department'

export default async function DepartmentClearancePage() {
  const profile = await requireRole('Department')
  const state = await getDepartmentState()
  if (state.kind !== 'ready') {
    return (
      <DashboardShell profile={profile} title="Clearance Items" subtitle="Approve an item once all your holds are lifted">
        <DeptUnavailable kind={state.kind} />
      </DashboardShell>
    )
  }
  const counts = countDepartment(state.items, state.holds)
  return (
    <DashboardShell
      profile={profile}
      title="Clearance Items"
      subtitle={`${state.department.name} · approve an item once all your holds are lifted`}
    >
      <ClearanceItemsClient
        items={state.items}
        stats={[
          { label: 'Items to review', value: counts.toReview, hint: 'waiting for you', hue: counts.toReview ? 'amber' : undefined },
          { label: 'Active holds', value: counts.activeHolds, hint: 'block approval', hue: counts.activeHolds ? 'rose' : undefined },
          { label: 'Cleared', value: counts.cleared, hint: 'items approved' },
          { label: 'Students', value: counts.students, hint: 'in clearance' },
        ]}
      />
    </DashboardShell>
  )
}
