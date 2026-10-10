import DashboardShell from '@/components/layout/DashboardShell'
import UsersTable, { type UserRow } from '@/components/admin/UsersTable'
import { requireRole } from '@/lib/auth/session'
import {
  departmentStaff,
  departments,
  getRoleName,
  profiles,
  programs,
  students,
} from '@/lib/mock-data'

export default async function AdminUsersPage() {
  const profile = await requireRole('Admin')

  const users: UserRow[] = profiles.map((p) => {
    const staff = departmentStaff.find((s) => s.profile_id === p.profile_id)
    const student = students.find((s) => s.student_id === p.profile_id)
    const department = staff
      ? departments.find((d) => d.department_id === staff.department_id)?.name
      : programs.find((pr) => pr.program_id === student?.program_id)?.code
    return {
      id: p.profile_id,
      name: `${p.first_name} ${p.last_name}`,
      email: p.email,
      role: getRoleName(p.role_id) ?? 'Unknown',
      department: department ?? '-',
      active: p.is_active,
    }
  })

  return (
    <DashboardShell profile={profile} title="Accounts" subtitle="Manage portal accounts.">
      <UsersTable initialUsers={users} />
    </DashboardShell>
  )
}
