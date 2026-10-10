import ModulePage from '@/components/layout/ModulePage'

export default function AdminUsersPage() {
  return (
    <ModulePage
      role="Admin"
      title="Users"
      subtitle="Manage portal accounts."
      planned={[
      "User list with role and active status",
      "Activate or deactivate accounts",
      "Change role",
      ]}
    />
  )
}
