import DashboardShell from '@/components/layout/DashboardShell'
import UsersTable from '@/components/admin/UsersTable'
import { requireRole } from '@/lib/auth/session'
import { ROLE_NAMES, getAdminUsers } from '@/lib/mock/admin-data'

export default async function AdminUsersPage() {
  const profile = await requireRole('Admin')

  return (
    <DashboardShell profile={profile} title="Users" subtitle="Accounts and roles: users are deactivated, never deleted">
      <UsersTable initialUsers={getAdminUsers()} roleNames={ROLE_NAMES} />
    </DashboardShell>
  )
}
