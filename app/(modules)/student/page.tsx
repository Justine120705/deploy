import DashboardShell from '@/components/layout/DashboardShell'
import { requireRole } from '@/lib/auth/session'
import { Badge, Card, CardHeader, StatCard, StatusBadge } from '@/components/ui'
import {
  MOCK_CURRENT_TERM_ID,
  MOCK_STUDENT_ID,
  departments,
  enrollments,
  terms,
  vActiveHolds,
  vClearanceItems,
} from '@/lib/mock-data'

export default async function StudentDashboardPage() {
  const profile = await requireRole('Student')

  const term = terms.find((t) => t.term_id === MOCK_CURRENT_TERM_ID)
  const enrollment = enrollments.find(
    (e) => e.student_id === MOCK_STUDENT_ID && e.term_id === MOCK_CURRENT_TERM_ID
  )
  const items = vClearanceItems.filter(
    (i) => i.student_id === MOCK_STUDENT_ID && i.term_id === MOCK_CURRENT_TERM_ID
  )
  const cleared = items.filter((i) => i.status === 'Cleared').length
  const holds = vActiveHolds.filter((h) => h.student_id === MOCK_STUDENT_ID)

  return (
    <DashboardShell
      profile={profile}
      title="Student Dashboard"
      subtitle="Your enrollment, clearance and holds at a glance."
    >
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <Card className="flex flex-col gap-2 p-5">
          <p className="text-sm font-medium text-muted">Enrollment status</p>
          <div>
            <StatusBadge status={enrollment?.status ?? 'Pending'} />
          </div>
          <p className="text-sm text-muted">
            {term ? `${term.semester}, ${term.school_year}` : 'Current term'}
          </p>
        </Card>
        <StatCard
          label="Clearance summary"
          value={`${cleared} / ${items.length}`}
          hint={`${cleared} cleared, ${items.length - cleared} pending`}
        />
        <StatCard
          label="Active holds"
          value={holds.length}
          hint={holds.length ? 'Resolve holds to proceed' : 'No active holds'}
          className="sm:col-span-2 xl:col-span-1"
        />
      </div>

      <Card className="mt-6 p-5">
        <CardHeader title="Active holds" />
        {holds.length === 0 ? (
          <p className="mt-3 text-sm text-muted">You have no active holds.</p>
        ) : (
          <ul className="mt-3 divide-y divide-border-subtle">
            {holds.map((hold) => (
              <li
                key={hold.hold_id}
                className="flex flex-col gap-1 py-3 sm:flex-row sm:items-center sm:justify-between"
              >
                <div>
                  <p className="text-sm font-semibold">{hold.reason}</p>
                  <p className="text-sm text-muted">
                    {departments.find((d) => d.department_id === hold.department_id)?.name}
                  </p>
                </div>
                <Badge tone="danger" className="self-start">On hold</Badge>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </DashboardShell>
  )
}
