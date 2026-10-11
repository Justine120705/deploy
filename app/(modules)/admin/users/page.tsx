import DashboardShell from '@/components/layout/DashboardShell'
import { SampleDataNote } from '@/components/ui/SampleDataNote'
import UsersTable from '@/components/admin/UsersTable'
import { requireRole } from '@/lib/auth/session'
import { ROLE_NAMES, getAdminUsers } from '@/lib/mock/admin-data'

export default async function AdminUsersPage() {
  const profile = await requireRole('Admin')

  return (
    <DashboardShell profile={profile} title="Users" subtitle="Accounts and roles: users are deactivated, never deleted">
      <div className="flex flex-col gap-6">
        <SampleDataNote>The user list is sample data and is not connected to live accounts yet.</SampleDataNote>
        <UsersTable initialUsers={getAdminUsers()} roleNames={ROLE_NAMES} />
      </div>
    </DashboardShell>
  )
}
