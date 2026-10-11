import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { DocumentsActions, DocumentsBody, DocumentsProvider } from '@/components/registrar/DocumentsQueue'

export default async function RegistrarDocumentsPage() {
  const profile = await requireRole('Registrar')
  return (
    <DocumentsProvider>
      <DashboardShell
        profile={profile}
        title="Document Requests"
        subtitle="Registrar Office · process requests from students"
        actions={<DocumentsActions />}
      >
        <DocumentsBody />
      </DashboardShell>
    </DocumentsProvider>
  )
}
