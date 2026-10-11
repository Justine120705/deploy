import DashboardShell from '@/components/layout/DashboardShell'
import DocumentRequestsView from '@/components/student/DocumentRequestsView'
import { JumpLink } from '@/components/student/PageActions'
import { SampleDataNote } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { MOCK_STUDENT_ID, documentRequests, documentTypes } from '@/lib/mock-data'

export default async function StudentDocumentsPage() {
  const profile = await requireRole('Student')

  const records = documentRequests
    .filter((r) => r.student_id === MOCK_STUDENT_ID)
    .map((r) => ({
      id: r.request_id,
      ticket_number: r.ticket_number,
      document_type_id: r.document_type_id,
      purpose: r.purpose,
      copies: r.copies,
      requested_at: r.requested_at,
      processed_at: r.processed_at,
      status: r.status,
    }))

  return (
    <DashboardShell
      profile={profile}
      title="Document requests"
      subtitle="Request records from the Registrar and track their status"
      actions={<JumpLink href="#new-request">New request</JumpLink>}
    >
      <SampleDataNote className="mb-6">Document requests shown here are sample records and are not sent to the Registrar yet.</SampleDataNote>
      <DocumentRequestsView documentTypes={documentTypes} initialRequests={records} />
    </DashboardShell>
  )
}
