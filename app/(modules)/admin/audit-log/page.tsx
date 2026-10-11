import DashboardShell from '@/components/layout/DashboardShell'
import AuditLogView from '@/components/admin/AuditLogView'
import { EmptyState } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { getAuditLogState } from '@/lib/data/audit'

export default async function AdminAuditLogPage() {
  const profile = await requireRole('Admin')
  const state = await getAuditLogState()

  return (
    <DashboardShell
      profile={profile}
      title="Audit Log"
      subtitle="Every change is recorded by database triggers. Read-only."
    >
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load the audit log">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : (
        <AuditLogView entries={state.entries} total={state.total} />
      )}
    </DashboardShell>
  )
}
