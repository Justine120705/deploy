import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyState } from '@/components/ui'
import DocumentsQueue from '@/components/registrar/DocumentsQueue'
import { getRegistrarDocumentsState } from '@/lib/data/documents'

export default async function RegistrarDocumentsPage() {
  const profile = await requireRole('Registrar')
  const state = await getRegistrarDocumentsState()

  return (
    <DashboardShell
      profile={profile}
      title="Document Requests"
      subtitle="Registrar Office · process requests from students"
    >
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load document requests">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : (
        <DocumentsQueue requests={state.requests} />
      )}
    </DashboardShell>
  )
}
