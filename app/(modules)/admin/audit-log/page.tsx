import ModulePage from '@/components/layout/ModulePage'

export default function AdminAuditLogPage() {
  return (
    <ModulePage
      role="Admin"
      title="Audit Log"
      subtitle="Who did what, and when."
      planned={[
      "Audit entries with actor, action and time",
      "Filter by user, table and date",
      ]}
    />
  )
}
