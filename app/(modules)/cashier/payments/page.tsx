import DashboardShell from '@/components/layout/DashboardShell'
import PaymentsView from '@/components/cashier/PaymentsView'
import { LinkButton } from '@/components/cashier/LinkButton'
import { requireRole } from '@/lib/auth/session'
import { CASHIER_TERM } from '@/lib/mock/cashier-data'

export default async function CashierPaymentsPage() {
  const profile = await requireRole('Cashier')
  return (
    <DashboardShell
      profile={profile}
      title="Payments"
      subtitle={`Cashier's Office, ${CASHIER_TERM}. The cashier logs each payment by hand.`}
      actions={
        <LinkButton href="#record" icon="check">
          Log a payment
        </LinkButton>
      }
    >
      <PaymentsView />
    </DashboardShell>
  )
}
