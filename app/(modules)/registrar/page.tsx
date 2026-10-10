import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyRow, StatusBadge, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import StatGrid from '@/components/registrar/StatGrid'
import { REGISTRAR_CLEARANCES, REGISTRAR_DOCUMENTS, REGISTRAR_ENROLLMENTS } from '@/lib/mock/registrar-data'

export default async function RegistrarDashboardPage() {
  const profile = await requireRole('Registrar')

  const pendingEnrollments = REGISTRAR_ENROLLMENTS.filter((e) => e.status === 'Pending')
  const openRequests = REGISTRAR_DOCUMENTS.filter((d) => d.status === 'Pending' || d.status === 'Processing')
  const readyClearances = REGISTRAR_CLEARANCES.filter((c) => c.status === 'Pending' && c.cleared === c.total && c.holds === 0)

  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle="Registrar Office · 1st Sem 2026-2027">
      <div className="flex flex-col gap-6">
        <StatGrid
          items={[
            { label: 'Enrollments', value: pendingEnrollments.length, hint: 'awaiting review', hue: pendingEnrollments.length ? 'amber' : undefined },
            { label: 'Document requests', value: openRequests.length, hint: 'to process', hue: openRequests.length ? 'amber' : undefined },
            { label: 'Clearances', value: readyClearances.length, hint: 'ready for final approval', hue: readyClearances.length ? 'teal' : undefined },
            { label: 'Unsaved grades', value: 0, hint: 'sections' },
          ]}
        />

        <section aria-labelledby="pending-enrollments">
          <h2 id="pending-enrollments" className="mb-3 px-1 text-base font-bold">Pending enrollments</h2>
          <Table className="min-w-[720px]">
            <TableHeader>
              <tr>
                <TableHead>Student no.</TableHead>
                <TableHead>Student name</TableHead>
                <TableHead>Program</TableHead>
                <TableHead>Subjects</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Submitted</TableHead>
              </tr>
            </TableHeader>
            <TableBody>
              {pendingEnrollments.length === 0 && <EmptyRow colSpan={6}>No enrollments are waiting for review.</EmptyRow>}
              {pendingEnrollments.map((e) => (
                <TableRow key={e.id}>
                  <TableCell className="font-normal text-muted">{e.studentNo}</TableCell>
                  <TableCell className="font-semibold">{e.name}</TableCell>
                  <TableCell className="font-normal text-muted">{e.program}</TableCell>
                  <TableCell className="font-normal text-muted">{e.subjects} subjects</TableCell>
                  <TableCell><StatusBadge status={e.status} /></TableCell>
                  <TableCell className="font-normal text-muted">{e.submitted}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <p className="px-1 pt-3 text-sm text-muted">
            Showing {pendingEnrollments.length} of {REGISTRAR_ENROLLMENTS.length} enrollments
          </p>
        </section>

        <section aria-labelledby="open-requests">
          <h2 id="open-requests" className="mb-3 px-1 text-base font-bold">Open document requests</h2>
          <Table className="min-w-[720px]">
            <TableHeader>
              <tr>
                <TableHead>Ticket</TableHead>
                <TableHead>Student</TableHead>
                <TableHead>Document</TableHead>
                <TableHead>Copies</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Requested</TableHead>
              </tr>
            </TableHeader>
            <TableBody>
              {openRequests.length === 0 && <EmptyRow colSpan={6}>No open document requests.</EmptyRow>}
              {openRequests.map((d) => (
                <TableRow key={d.id}>
                  <TableCell className="font-normal text-muted">{d.ticket}</TableCell>
                  <TableCell className="font-semibold">{d.name}</TableCell>
                  <TableCell className="font-normal text-muted">{d.document}</TableCell>
                  <TableCell className="font-normal text-muted">{d.copies}</TableCell>
                  <TableCell><StatusBadge status={d.status} /></TableCell>
                  <TableCell className="font-normal text-muted">{d.requested}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </section>
      </div>
    </DashboardShell>
  )
}
