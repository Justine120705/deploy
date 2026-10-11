import Link from 'next/link'
import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyRow, Section, StatusBadge, SummaryStrip, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { QueueSheet, QueueTable, StudentCell } from '@/components/registrar/QueueParts'
import { REGISTRAR_CLEARANCES, REGISTRAR_DOCUMENTS, REGISTRAR_ENROLLMENTS } from '@/lib/mock/registrar-data'

const OPEN_LINK =
  'inline-flex h-9 items-center text-sm font-semibold text-accent-foreground hover:underline max-lg:h-11 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring rounded-md'

export default async function RegistrarDashboardPage() {
  const profile = await requireRole('Registrar')

  const pendingEnrollments = REGISTRAR_ENROLLMENTS.filter((e) => e.status === 'Pending')
  const openRequests = REGISTRAR_DOCUMENTS.filter((d) => d.status === 'Pending' || d.status === 'Processing')
  const readyClearances = REGISTRAR_CLEARANCES.filter((c) => c.status === 'Pending' && c.cleared === c.total && c.holds === 0)

  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle="Registrar Office, 1st Sem 2026-2027">
      <div className="flex flex-col gap-6">
        <SummaryStrip
          items={[
            { label: 'Enrollments', value: pendingEnrollments.length, hint: 'awaiting review', hue: pendingEnrollments.length ? 'amber' : undefined },
            { label: 'Document requests', value: openRequests.length, hint: 'to process', hue: openRequests.length ? 'amber' : undefined },
            { label: 'Clearances', value: readyClearances.length, hint: 'ready for final approval', hue: readyClearances.length ? 'teal' : undefined },
          ]}
        />

        <Section
          title="Pending enrollments"
          action={<Link href="/registrar/enrollments" className={OPEN_LINK}>Review enrollments</Link>}
        >
          <QueueSheet>
            <QueueTable minWidth="min-w-[600px]">
              <TableHeader>
                <tr>
                  <TableHead>Student</TableHead>
                  <TableHead>Program</TableHead>
                  <TableHead>Subjects</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Submitted</TableHead>
                </tr>
              </TableHeader>
              <TableBody>
                {pendingEnrollments.length === 0 && <EmptyRow colSpan={5}>No enrollments are waiting for review.</EmptyRow>}
                {pendingEnrollments.map((e) => (
                  <TableRow key={e.id}>
                    <TableCell><StudentCell name={e.name} sub={e.studentNo} /></TableCell>
                    <TableCell className="text-muted">{e.program}</TableCell>
                    <TableCell className="text-muted">{e.subjects} subjects</TableCell>
                    <TableCell><StatusBadge status={e.status} /></TableCell>
                    <TableCell className="text-muted">{e.submitted}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </QueueTable>
          </QueueSheet>
        </Section>

        <Section
          title="Open document requests"
          action={<Link href="/registrar/documents" className={OPEN_LINK}>Open queue</Link>}
        >
          <QueueSheet>
            <QueueTable minWidth="min-w-[600px]">
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
                    <TableCell className="text-muted">{d.ticket}</TableCell>
                    <TableCell><StudentCell name={d.name} /></TableCell>
                    <TableCell>{d.document}</TableCell>
                    <TableCell className="text-muted">{d.copies}</TableCell>
                    <TableCell><StatusBadge status={d.status} /></TableCell>
                    <TableCell className="text-muted">{d.requested}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </QueueTable>
          </QueueSheet>
        </Section>
      </div>
    </DashboardShell>
  )
}
