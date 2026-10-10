import ModulePage from '@/components/layout/ModulePage'

export default function RegistrarDocumentsPage() {
  return (
    <ModulePage
      role="Registrar"
      title="Document Requests"
      subtitle="Process document requests."
      planned={[
      "Request queue with status",
      "Mark requests processing, ready or released",
      ]}
    />
  )
}
