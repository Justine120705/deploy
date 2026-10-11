import Link from 'next/link'
import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyRow, Section, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats } from '@/components/department/DeptStats'
import { HoldFlagBadge, ItemStatusBadge } from '@/components/department/DeptBadges'
import { RecordList } from '@/components/department/RecordList'
import { DeptUnavailable } from '@/components/department/DeptNotice'
import { countDepartment, getDepartmentState } from '@/lib/data/department'

const LINK =
  'inline-flex items-center text-sm font-semibold text-accent-foreground underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring max-lg:min-h-11'

export default async function DepartmentDashboardPage() {
  const profile = await requireRole('Department')

  const state = await getDepartmentState()
  if (state.kind !== 'ready') {
    return (
      <DashboardShell profile={profile} title="Dashboard" subtitle="Department clearance">
        <DeptUnavailable kind={state.kind} />
      </DashboardShell>
    )
  }

  const activeHolds = state.holds.filter((h) => h.status === 'Active')
  const pending = state.items.filter((i) => i.status === 'Pending')
  const counts = countDepartment(state.items, state.holds)
  const term = state.term ? `${state.term.semester} ${state.term.schoolYear}` : 'No open term'

  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle={`${state.department.name} · ${term}`}>
      <div className="flex flex-col gap-6">
        <DeptStats
          stats={[
            { label: 'Items to review', value: counts.toReview, hint: 'waiting for you', hue: counts.toReview ? 'amber' : undefined },
            { label: 'Active holds', value: counts.activeHolds, hint: 'block approval', hue: counts.activeHolds ? 'rose' : undefined },
            { label: 'Cleared', value: counts.cleared, hint: 'items approved' },
            { label: 'Students', value: counts.students, hint: 'in clearance' },
          ]}
        />

        <Section
          title="Items to review"
          action={
            <Link href="/department/clearance" className={LINK}>
              Review items
            </Link>
          }
        >
          <div className="hidden md:block">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead scope="col">Student no.</TableHead>
                  <TableHead scope="col">Student name</TableHead>
                  <TableHead scope="col">Program</TableHead>
                  <TableHead scope="col">Status</TableHead>
                  <TableHead scope="col">Hold</TableHead>
                  <TableHead scope="col">Requested</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {pending.length === 0 && <EmptyRow colSpan={6}>No pending clearance items.</EmptyRow>}
                {pending.map((item) => (
                  <TableRow key={item.itemId}>
                    <TableCell className="text-muted">{item.studentNo}</TableCell>
                    <TableCell className="font-semibold">{item.name}</TableCell>
                    <TableCell className="text-muted">{item.program}</TableCell>
                    <TableCell><ItemStatusBadge status={item.status} /></TableCell>
                    <TableCell><HoldFlagBadge active={item.holds.length > 0} /></TableCell>
                    <TableCell className="text-muted">{item.requestedOn}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <RecordList
            className="md:hidden"
            empty="No pending clearance items."
            items={pending.map((item) => ({
              key: String(item.itemId),
              title: item.name,
              subtitle: `${item.studentNo} · ${item.program}`,
              badge: <ItemStatusBadge status={item.status} />,
              fields: [
                { label: 'Hold', value: <HoldFlagBadge active={item.holds.length > 0} /> },
                { label: 'Requested', value: item.requestedOn },
              ],
            }))}
          />
        </Section>

        <Section
          title="Active holds"
          action={
            <Link href="/department/holds" className={LINK}>
              Manage holds
            </Link>
          }
        >
          <div className="hidden md:block">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead scope="col">Student no.</TableHead>
                  <TableHead scope="col">Student name</TableHead>
                  <TableHead scope="col">Reason</TableHead>
                  <TableHead scope="col">Placed by</TableHead>
                  <TableHead scope="col">Placed on</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {activeHolds.length === 0 && <EmptyRow colSpan={5}>No active academic holds.</EmptyRow>}
                {activeHolds.map((h) => (
                  <TableRow key={h.holdId}>
                    <TableCell className="text-muted">{h.studentNo}</TableCell>
                    <TableCell className="font-semibold">{h.name}</TableCell>
                    <TableCell className="max-w-72 whitespace-normal">{h.reason}</TableCell>
                    <TableCell className="text-muted">{h.placedByName}</TableCell>
                    <TableCell className="text-muted">{h.placedOn}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <RecordList
            className="md:hidden"
            empty="No active academic holds."
            items={activeHolds.map((h) => ({
              key: String(h.holdId),
              title: h.name,
              subtitle: h.studentNo,
              fields: [
                { label: 'Reason', value: h.reason },
                { label: 'Placed by', value: h.placedByName },
                { label: 'Placed on', value: h.placedOn },
              ],
            }))}
          />
        </Section>
      </div>
    </DashboardShell>
  )
}
