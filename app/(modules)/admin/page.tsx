import DashboardShell from '@/components/layout/DashboardShell'
import { requireRole } from '@/lib/auth/session'
import { Card, CardHeader, StatCard } from '@/components/ui'
import { MOCK_CURRENT_TERM_ID, auditLogs, departments, profiles, roles, terms } from '@/lib/mock-data'

export default async function AdminDashboardPage() {
  const profile = await requireRole('Admin')

  const term = terms.find((t) => t.term_id === MOCK_CURRENT_TERM_ID)
  const activeProfiles = profiles.filter((p) => p.is_active)

  return (
    <DashboardShell profile={profile} title="Admin Dashboard" subtitle="System overview.">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Active users"
          value={activeProfiles.length}
          hint={`${profiles.length - activeProfiles.length} inactive`}
        />
        <StatCard label="Departments" value={departments.length} />
        <StatCard label="Current term" value={term ? term.semester : '-'} hint={term?.school_year} />
        <StatCard label="Audit entries" value={auditLogs.length} />
      </div>

      <Card className="mt-6 p-5">
        <CardHeader title="Active users by role" />
        <div className="mt-4 grid gap-4 sm:grid-cols-3 xl:grid-cols-5">
          {roles.map((r) => (
            <StatCard
              key={r.role_id}
              label={r.role_name}
              value={activeProfiles.filter((p) => p.role_id === r.role_id).length}
            />
          ))}
        </div>
      </Card>
    </DashboardShell>
  )
}
