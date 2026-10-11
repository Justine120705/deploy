import DashboardShell from '@/components/layout/DashboardShell'
import ChargesView from '@/components/cashier/ChargesView'
import LedgerProblem from '@/components/cashier/LedgerProblem'
import { LinkButton } from '@/components/cashier/LinkButton'
import { requireRole } from '@/lib/auth/session'
import { getCashierLedger } from '@/lib/data/cashier'

export default async function CashierChargesPage() {
  const profile = await requireRole('Cashier')
  const state = await getCashierLedger()
  const term = state.kind === 'ready' ? `, ${state.ledger.term.semester} ${state.ledger.term.schoolYear}` : ''

  return (
    <DashboardShell
      profile={profile}
      title="Charges"
      subtitle={`Cashier's Office${term}. Balance is charges minus payments.`}
      actions={
        <LinkButton href="/cashier/payments#record" icon="check">
          Log a payment
        </LinkButton>
      }
    >
      {state.kind === 'ready' ? <ChargesView ledger={state.ledger} /> : <LedgerProblem kind={state.kind} />}
    </DashboardShell>
  )
}
