import DashboardShell from '@/components/layout/DashboardShell'
import DashboardView from '@/components/cashier/DashboardView'
import { requireRole } from '@/lib/auth/session'
import { CASHIER_TERM } from '@/lib/mock/cashier-data'

export default async function CashierDashboardPage() {
  const profile = await requireRole('Cashier')
  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle={`Cashier's Office · ${CASHIER_TERM}`}>
      <DashboardView />
    </DashboardShell>
  )
}
