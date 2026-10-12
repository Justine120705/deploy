import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyState } from '@/components/ui'
import EnrollmentsReview from '@/components/registrar/EnrollmentsReview'
import { getEnrollmentsReviewState } from '@/lib/data/enrollments-review'

export default async function RegistrarEnrollmentsPage() {
  const profile = await requireRole('Registrar')
  const state = await getEnrollmentsReviewState()

  return (
    <DashboardShell
      profile={profile}
      title="Enrollments"
      subtitle="Registrar Office · review and approve submitted enrollments"
    >
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load enrollments">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : (
        <EnrollmentsReview enrollments={state.enrollments} />
      )}
    </DashboardShell>
  )
}
