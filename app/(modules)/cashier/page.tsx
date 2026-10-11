import DashboardShell from '@/components/layout/DashboardShell'
import DashboardView from '@/components/cashier/DashboardView'
import LedgerProblem from '@/components/cashier/LedgerProblem'
import { LinkButton } from '@/components/cashier/LinkButton'
import { requireRole } from '@/lib/auth/session'
import { getCashierLedger, getFinanceClearance } from '@/lib/data/cashier'

export default async function CashierDashboardPage() {
  const profile = await requireRole('Cashier')
  const state = await getCashierLedger()
  const finance = state.kind === 'ready' ? await getFinanceClearance(state.ledger) : null
  const subtitle =
    state.kind === 'ready'
      ? `Cashier's Office, ${state.ledger.term.semester} ${state.ledger.term.schoolYear}`
      : "Cashier's Office"

  return (
    <DashboardShell
      profile={profile}
      title="Dashboard"
      subtitle={subtitle}
      actions={
        <LinkButton href="/cashier/payments#record" icon="check">
          Log a payment
        </LinkButton>
      }
    >
      {state.kind === 'ready' ? (
        <DashboardView ledger={state.ledger} finance={finance?.kind === 'ready' ? finance.data : null} />
      ) : (
        <LedgerProblem kind={state.kind} />
      )}
    </DashboardShell>
  )
}
