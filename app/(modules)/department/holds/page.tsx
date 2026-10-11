import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import HoldsClient from '@/components/department/HoldsClient'
import { DEPT_NAME } from '@/lib/mock/department-data'

export default async function DepartmentHoldsPage() {
  const profile = await requireRole('Department')
  return (
    <DashboardShell
      profile={profile}
      title="Academic Holds"
      subtitle={`${DEPT_NAME} · place and lift holds for your own department`}
    >
      <HoldsClient />
    </DashboardShell>
  )
}
