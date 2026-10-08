import DashboardShell from '@/components/layout/DashboardShell'
import RlsCheck from '@/components/layout/RlsCheck'
import { requireRole } from '@/lib/auth/session'

export default async function RegistrarPage() {
  const profile = await requireRole('Registrar')

  return (
    <DashboardShell profile={profile} title="Registrar Dashboard">
      <RlsCheck table="enrollments" expected="The Registrar should see every student's enrollment (3 with the test data)." />
    </DashboardShell>
  )
}
