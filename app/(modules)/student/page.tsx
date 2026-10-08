import DashboardShell from '@/components/layout/DashboardShell'
import RlsCheck from '@/components/layout/RlsCheck'
import { requireRole } from '@/lib/auth/session'

export default async function StudentPage() {
  const profile = await requireRole('Student')

  return (
    <DashboardShell profile={profile} title="Student Dashboard">
      <RlsCheck table="enrollments" expected="A student should see only their own enrollment (1 with the test data)." />
    </DashboardShell>
  )
}
