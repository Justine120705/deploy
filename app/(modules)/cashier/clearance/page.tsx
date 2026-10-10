import DashboardShell from '@/components/layout/DashboardShell'
import ClearanceView from '@/components/cashier/ClearanceView'
import { requireRole } from '@/lib/auth/session'
import { CASHIER_TERM } from '@/lib/mock/cashier-data'

export default async function CashierClearancePage() {
  const profile = await requireRole('Cashier')
  return (
    <DashboardShell
      profile={profile}
      title="Finance Clearance"
      subtitle={`Cashier's Office, ${CASHIER_TERM}. One clearance item per student, cleared automatically.`}
    >
      <ClearanceView />
    </DashboardShell>
  )
}
