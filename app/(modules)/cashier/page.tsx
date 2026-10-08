import DashboardShell from '@/components/layout/DashboardShell'
import RlsCheck from '@/components/layout/RlsCheck'
import { requireRole } from '@/lib/auth/session'

export default async function CashierPage() {
  const profile = await requireRole('Cashier')

  return (
    <DashboardShell profile={profile} title="Cashier Dashboard">
      <RlsCheck table="charges" expected="The Cashier should see every student's charges (3 with the test data)." />
    </DashboardShell>
  )
}
