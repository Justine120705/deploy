import ModulePage from '@/components/layout/ModulePage'

export default function StudentDocumentsPage() {
  return (
    <ModulePage
      role="Student"
      title="Document Requests"
      subtitle="Request and track official documents."
      planned={[
      "New document request form",
      "Request history with status",
      ]}
    />
  )
}
