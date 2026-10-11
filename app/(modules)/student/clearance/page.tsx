import DashboardShell from '@/components/layout/DashboardShell'
import ClearanceOverview from '@/components/student/ClearanceOverview'
import RequestClearanceButton from '@/components/student/RequestClearanceButton'
import { EmptyState } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { getStudentClearanceState } from '@/lib/data/clearance'

export default async function StudentClearancePage() {
  const profile = await requireRole('Student')
  const state = await getStudentClearanceState()

  const subtitle =
    state.kind === 'ready'
      ? `${state.term.semester} ${state.term.schoolYear} · one item per office`
      : 'Clearance for the current term'

  return (
    <DashboardShell profile={profile} title="My clearance" subtitle={subtitle}>
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load your clearance">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : state.kind === 'no-term' ? (
        <EmptyState title="No term is open">
          Clearance opens when the Registrar sets the current term. Check back later.
        </EmptyState>
      ) : state.clearance === null ? (
        <EmptyState
          title="You have not requested clearance yet"
          action={<RequestClearanceButton />}
        >
          Request your {state.term.semester} {state.term.schoolYear} clearance. Every office will get an item to review,
          and the Registrar gives the final approval once all of them clear you.
        </EmptyState>
      ) : (
        <ClearanceOverview
          offices={state.clearance.items}
          holds={state.holds}
          approved={state.clearance.approved}
          approvedAt={state.clearance.approvedAt}
        />
      )}
    </DashboardShell>
  )
}
