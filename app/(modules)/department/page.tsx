import DashboardShell from '@/components/layout/DashboardShell'
import RlsCheck from '@/components/layout/RlsCheck'
import { requireRole } from '@/lib/auth/session'

export default async function DepartmentPage() {
  const profile = await requireRole('Department')

  return (
    <DashboardShell profile={profile} title="Department Dashboard">
      <RlsCheck table="clearance_items" expected="A Department user should see only their own department's items (3 with the test data)." />
    </DashboardShell>
  )
}
