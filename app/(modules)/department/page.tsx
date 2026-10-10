import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyRow, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
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

export default async function DepartmentDashboardPage() {
  const profile = await requireRole('Department')

  const activeHolds = DEPT_HOLDS.filter((h) => h.status === 'Active')
  const holdNos = new Set(activeHolds.map((h) => h.studentNo))
  const pending = DEPT_CLEARANCE_ITEMS.filter((i) => i.status === 'Pending')
  const cleared = DEPT_CLEARANCE_ITEMS.filter((i) => i.status === 'Cleared')

  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle={`${DEPT_NAME} · 1st Sem 2026-2027`}>
      <div className="flex flex-col gap-4">
        <DeptStats
          stats={[
            { label: 'Students', value: DEPT_STUDENTS.length, hint: 'in clearance' },
            { label: 'Pending items', value: pending.length, hint: 'to review', hue: 'amber' },
            { label: 'Cleared', value: cleared.length, hint: 'items', hue: 'teal' },
            { label: 'Active holds', value: activeHolds.length, hint: 'academic', hue: 'rose' },
          ]}
        />

        <section aria-labelledby="pending-heading" className="flex flex-col gap-2">
          <h2 id="pending-heading" className="text-base font-bold">
            Pending clearance items
          </h2>
          <div className="hidden md:block">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead scope="col">Student no.</TableHead>
                  <TableHead scope="col">Student name</TableHead>
                  <TableHead scope="col">Program</TableHead>
                  <TableHead scope="col">Clearance item</TableHead>
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
                      <TableCell className="font-normal text-muted">{s.studentNo}</TableCell>
                      <TableCell className="font-semibold">{s.name}</TableCell>
                      <TableCell className="font-normal text-muted">{s.program}</TableCell>
                      <TableCell><ItemStatusBadge status={item.status} /></TableCell>
                      <TableCell><HoldFlagBadge active={holdNos.has(item.studentNo)} /></TableCell>
                      <TableCell className="font-normal text-muted">{item.requestedOn}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <div className="surface rounded-2xl border border-edge bg-card shadow-elev-sm md:hidden">
            <RecordList
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
          </div>
        </section>

        <section aria-labelledby="holds-heading" className="flex flex-col gap-2">
          <h2 id="holds-heading" className="text-base font-bold">
            Active academic holds
          </h2>
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
                      <TableCell className="font-normal text-muted">{s.studentNo}</TableCell>
                      <TableCell className="font-semibold">{s.name}</TableCell>
                      <TableCell className="font-normal text-muted">{h.reason}</TableCell>
                      <TableCell className="font-normal text-muted">{h.placedBy}</TableCell>
                      <TableCell className="font-normal text-muted">{h.placedOn}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <div className="surface rounded-2xl border border-edge bg-card shadow-elev-sm md:hidden">
            <RecordList
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
          </div>
        </section>
      </div>
    </DashboardShell>
  )
}
