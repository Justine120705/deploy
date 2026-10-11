import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyState } from '@/components/ui'
import { ClearanceActions, ClearanceBody, ClearanceProvider } from '@/components/registrar/ClearanceReview'
import { getRegistrarClearanceState } from '@/lib/data/registrar'

export default async function RegistrarClearancePage() {
  const profile = await requireRole('Registrar')
  const state = await getRegistrarClearanceState()

  const subtitle =
    state.kind === 'ready'
      ? `${state.term.semester} ${state.term.schoolYear} · final approval once every office has cleared`
      : 'Final approval once every office has cleared'

  if (state.kind !== 'ready') {
    return (
      <DashboardShell profile={profile} title="Clearance" subtitle={subtitle}>
        {state.kind === 'error' ? (
          <div role="alert">
            <EmptyState title="We could not load clearance requests">
              Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
            </EmptyState>
          </div>
        ) : (
          <EmptyState title="No term is open">Clearance requests appear once a current term is set.</EmptyState>
        )}
      </DashboardShell>
    )
  }

  return (
    <ClearanceProvider rows={state.clearances}>
      <DashboardShell profile={profile} title="Clearance" subtitle={subtitle} actions={<ClearanceActions />}>
        <ClearanceBody />
      </DashboardShell>
    </ClearanceProvider>
  )
}
