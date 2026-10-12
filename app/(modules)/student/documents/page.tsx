import DashboardShell from '@/components/layout/DashboardShell'
import DocumentRequestsView from '@/components/student/DocumentRequestsView'
import { JumpLink } from '@/components/student/PageActions'
import { EmptyState } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { getStudentDocumentsState } from '@/lib/data/documents'

const NOTICES: Record<string, string> = {
  requested: 'Request sent. It is listed below as Pending until the Registrar starts processing it.',
}

export default async function StudentDocumentsPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const profile = await requireRole('Student')
  const state = await getStudentDocumentsState()
  const { notice } = await searchParams
  const noticeText = typeof notice === 'string' ? NOTICES[notice] : undefined

  return (
    <DashboardShell
      profile={profile}
      title="Document requests"
      subtitle="Request records from the Registrar and track their status"
      actions={state.kind === 'ready' ? <JumpLink href="#new-request">New request</JumpLink> : undefined}
    >
      {noticeText && state.kind === 'ready' && (
        <p role="status" className="mb-4 rounded-md border border-edge bg-card px-4 py-3 text-sm text-ink">
          {noticeText}
        </p>
      )}
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load your document requests">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : (
        <DocumentRequestsView documentTypes={state.types} requests={state.requests} />
      )}
    </DashboardShell>
  )
}
