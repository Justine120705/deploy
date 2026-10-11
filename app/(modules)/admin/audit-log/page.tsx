import DashboardShell from '@/components/layout/DashboardShell'
import AuditLogView from '@/components/admin/AuditLogView'
import { requireRole } from '@/lib/auth/session'
import { getAuditRows } from '@/lib/mock/admin-data'

export default async function AdminAuditLogPage() {
  const profile = await requireRole('Admin')

  return (
    <DashboardShell
      profile={profile}
      title="Audit Log"
      subtitle="Every change is recorded by database triggers. Read-only."
    >
      <AuditLogView rows={getAuditRows()} />
    </DashboardShell>
  )
}
