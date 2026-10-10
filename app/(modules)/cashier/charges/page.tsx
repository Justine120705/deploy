import DashboardShell from '@/components/layout/DashboardShell'
import ChargesView from '@/components/cashier/ChargesView'
import { LinkButton } from '@/components/cashier/LinkButton'
import { requireRole } from '@/lib/auth/session'
import { CASHIER_TERM } from '@/lib/mock/cashier-data'

export default async function CashierChargesPage() {
  const profile = await requireRole('Cashier')
  return (
    <DashboardShell
      profile={profile}
      title="Charges"
      subtitle={`Cashier's Office · ${CASHIER_TERM} · balance = charges minus payments`}
      actions={
        <LinkButton href="/cashier/payments#record" icon="check">
          Record payment
        </LinkButton>
      }
    >
      <ChargesView />
    </DashboardShell>
  )
}
