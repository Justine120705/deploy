import DashboardShell from '@/components/layout/DashboardShell'
import DashboardView from '@/components/cashier/DashboardView'
import { LinkButton } from '@/components/cashier/LinkButton'
import { requireRole } from '@/lib/auth/session'
import { CASHIER_TERM } from '@/lib/mock/cashier-data'

export default async function CashierDashboardPage() {
  const profile = await requireRole('Cashier')
  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle={`Cashier's Office, ${CASHIER_TERM}`}
      actions={
        <LinkButton href="/cashier/payments#record" icon="check">
          Log a payment
        </LinkButton>
      }>
      <DashboardView />
    </DashboardShell>
  )
}
