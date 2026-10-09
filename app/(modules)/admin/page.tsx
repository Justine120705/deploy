import DashboardShell from '@/components/layout/DashboardShell'
import RlsCheck from '@/components/layout/RlsCheck'
import { requireRole } from '@/lib/auth/session'

export default async function AdminPage() {
  const profile = await requireRole('Admin')

  return (
    <DashboardShell profile={profile} title="Admin Dashboard">
      <RlsCheck table="profiles" expected="The Admin should see every profile (7 with the test data)." />
    </DashboardShell>
  )
}
