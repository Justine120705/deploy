import ModulePage from '@/components/layout/ModulePage'

export default function AdminDashboardPage() {
  return (
    <ModulePage
      role="Admin"
      title="Admin Dashboard"
      subtitle="System overview."
      planned={[
      "Users by role",
      "Recent audit log entries",
      ]}
    />
  )
}
