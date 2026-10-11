import Link from 'next/link'
import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyRow, Section, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats } from '@/components/department/DeptStats'
import { HoldFlagBadge, ItemStatusBadge } from '@/components/department/DeptBadges'
import { RecordList } from '@/components/department/RecordList'
import {
  DEPT_CLEARANCE_ITEMS,
  DEPT_HOLDS,
  DEPT_NAME,
  DEPT_STUDENTS,
  studentByNo,
} from '@/lib/mock/department-data'

const LINK =
  'inline-flex items-center text-sm font-semibold text-accent-foreground underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring max-lg:min-h-11'

export default async function DepartmentDashboardPage() {
  const profile = await requireRole('Department')

  const activeHolds = DEPT_HOLDS.filter((h) => h.status === 'Active')
  const holdNos = new Set(activeHolds.map((h) => h.studentNo))
  const pending = DEPT_CLEARANCE_ITEMS.filter((i) => i.status === 'Pending')
  const cleared = DEPT_CLEARANCE_ITEMS.filter((i) => i.status === 'Cleared')

  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle={`${DEPT_NAME} · 1st Sem 2026-2027`}>
      <div className="flex flex-col gap-6">
        <DeptStats
          stats={[
            { label: 'Items to review', value: pending.length, hint: 'waiting for you', hue: pending.length ? 'amber' : undefined },
            { label: 'Active holds', value: activeHolds.length, hint: 'block approval', hue: activeHolds.length ? 'rose' : undefined },
            { label: 'Cleared', value: cleared.length, hint: 'items approved' },
            { label: 'Students', value: DEPT_STUDENTS.length, hint: 'in clearance' },
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
                {pending.map((item) => {
                  const s = studentByNo(item.studentNo)
                  return (
                    <TableRow key={item.studentNo}>
                      <TableCell className="text-muted">{s.studentNo}</TableCell>
                      <TableCell className="font-semibold">{s.name}</TableCell>
                      <TableCell className="text-muted">{s.program}</TableCell>
                      <TableCell><ItemStatusBadge status={item.status} /></TableCell>
                      <TableCell><HoldFlagBadge active={holdNos.has(item.studentNo)} /></TableCell>
                      <TableCell className="text-muted">{item.requestedOn}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <RecordList
            className="md:hidden"
            empty="No pending clearance items."
            items={pending.map((item) => {
              const s = studentByNo(item.studentNo)
              return {
                key: item.studentNo,
                title: s.name,
                subtitle: `${s.studentNo} · ${s.program}`,
                badge: <ItemStatusBadge status={item.status} />,
                fields: [
                  { label: 'Hold', value: <HoldFlagBadge active={holdNos.has(item.studentNo)} /> },
                  { label: 'Requested', value: item.requestedOn },
                ],
              }
            })}
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
                {activeHolds.map((h) => {
                  const s = studentByNo(h.studentNo)
                  return (
                    <TableRow key={h.id}>
                      <TableCell className="text-muted">{s.studentNo}</TableCell>
                      <TableCell className="font-semibold">{s.name}</TableCell>
                      <TableCell>{h.reason}</TableCell>
                      <TableCell className="text-muted">{h.placedBy}</TableCell>
                      <TableCell className="text-muted">{h.placedOn}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <RecordList
            className="md:hidden"
            empty="No active academic holds."
            items={activeHolds.map((h) => {
              const s = studentByNo(h.studentNo)
              return {
                key: h.id,
                title: s.name,
                subtitle: s.studentNo,
                fields: [
                  { label: 'Reason', value: h.reason },
                  { label: 'Placed by', value: h.placedBy },
                  { label: 'Placed on', value: h.placedOn },
                ],
              }
            })}
          />
        </Section>
      </div>
    </DashboardShell>
  )
}
