import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { SampleDataNote } from '@/components/ui'
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
        <div className="flex flex-col gap-4">
          <SampleDataNote />
          <DocumentsBody />
        </div>
      </DashboardShell>
    </DocumentsProvider>
  )
}
