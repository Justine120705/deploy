import DashboardShell from '@/components/layout/DashboardShell'
import EnrollmentView from '@/components/student/EnrollmentView'
import { EmptyState } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { getStudentEnrollmentState } from '@/lib/data/enrollment'

const NOTICES: Record<string, string> = {
  submitted: 'Enrollment submitted. It is Pending until the Registrar reviews it. Add your subject sections below.',
  added: 'Section added to your enrollment.',
  removed: 'Section removed from your enrollment.',
}

export default async function StudentEnrollmentPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const profile = await requireRole('Student')
  const state = await getStudentEnrollmentState()
  const { notice } = await searchParams
  const noticeText = typeof notice === 'string' ? NOTICES[notice] : undefined
  const termLabel = state.kind === 'ready' ? `${state.term.semester} ${state.term.schoolYear}` : ''

  return (
    <DashboardShell
      profile={profile}
      title="Enrollment"
      subtitle={state.kind === 'ready' ? `${termLabel} · your enrolled subjects` : 'Enroll in your subjects for the term'}
    >
      {noticeText && state.kind === 'ready' && (
        <p role="status" className="mb-4 rounded-md border border-edge bg-card px-4 py-3 text-sm text-ink">
          {noticeText}
        </p>
      )}
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load your enrollment">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : state.kind === 'no-term' ? (
        <EmptyState title="No term is open">
          Enrollment opens when the Registrar sets the current term. Check back later.
        </EmptyState>
      ) : (
        <EnrollmentView
          termLabel={termLabel}
          enrollment={state.enrollment}
          chosen={state.chosen}
          available={state.available}
        />
      )}
    </DashboardShell>
  )
}
