import DashboardShell from '@/components/layout/DashboardShell'
import LedgerProblem from '@/components/cashier/LedgerProblem'
import PaymentsView from '@/components/cashier/PaymentsView'
import { LinkButton } from '@/components/cashier/LinkButton'
import { requireRole } from '@/lib/auth/session'
import { getCashierLedger } from '@/lib/data/cashier'

export default async function CashierPaymentsPage() {
  const profile = await requireRole('Cashier')
  const state = await getCashierLedger()
  const term = state.kind === 'ready' ? `, ${state.ledger.term.semester} ${state.ledger.term.schoolYear}` : ''

  return (
    <DashboardShell
      profile={profile}
      title="Payments"
      subtitle={`Cashier's Office${term}. The cashier logs each payment by hand.`}
      actions={
        <LinkButton href="#record" icon="check">
          Log a payment
        </LinkButton>
      }
    >
      {state.kind === 'ready' ? <PaymentsView ledger={state.ledger} /> : <LedgerProblem kind={state.kind} />}
    </DashboardShell>
  )
}
