import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import ClearanceItemsClient from '@/components/department/ClearanceItemsClient'
import { DEPT_NAME } from '@/lib/mock/department-data'

export default async function DepartmentClearancePage() {
  const profile = await requireRole('Department')
  return (
    <DashboardShell
      profile={profile}
      title="Clearance Items"
      subtitle={`${DEPT_NAME} · approve an item once all your holds are lifted`}
    >
      <ClearanceItemsClient />
    </DashboardShell>
  )
}
