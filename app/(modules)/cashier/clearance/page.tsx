import DashboardShell from '@/components/layout/DashboardShell'
import ClearanceView from '@/components/cashier/ClearanceView'
import LedgerProblem from '@/components/cashier/LedgerProblem'
import { requireRole } from '@/lib/auth/session'
import { getFinanceClearance } from '@/lib/data/cashier'

export default async function CashierClearancePage() {
  const profile = await requireRole('Cashier')
  const state = await getFinanceClearance()
  const term = state.kind === 'ready' ? `, ${state.data.term.semester} ${state.data.term.schoolYear}` : ''

  return (
    <DashboardShell
      profile={profile}
      title="Finance Clearance"
      subtitle={`Cashier's Office${term}. One clearance item per student, cleared automatically.`}
    >
      {state.kind === 'ready' ? <ClearanceView data={state.data} /> : <LedgerProblem kind={state.kind} />}
    </DashboardShell>
  )
}
