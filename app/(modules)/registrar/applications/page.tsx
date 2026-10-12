import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyState } from '@/components/ui'
import ApplicationsReview from '@/components/registrar/ApplicationsReview'
import { getApplicationsState } from '@/lib/data/applications'

export default async function RegistrarApplicationsPage() {
  const profile = await requireRole('Registrar')
  const state = await getApplicationsState()

  return (
    <DashboardShell
      profile={profile}
      title="Applications"
      subtitle="Registrar Office · review new applicants and set up their student accounts"
    >
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load applications">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : (
        <ApplicationsReview applications={state.applications} />
      )}
    </DashboardShell>
  )
}
