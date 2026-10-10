import DashboardShell from '@/components/layout/DashboardShell'
import { requireRole } from '@/lib/auth/session'
import {
  Badge,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { auditLogs, profiles } from '@/lib/mock-data'

export default async function AdminAuditLogPage() {
  const profile = await requireRole('Admin')

  const rows = [...auditLogs].sort((a, b) => b.created_at.localeCompare(a.created_at))

  return (
    <DashboardShell profile={profile} title="Audit Log" subtitle="Who did what, and when. Read-only.">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>When</TableHead>
            <TableHead>Actor</TableHead>
            <TableHead>Action</TableHead>
            <TableHead>Table</TableHead>
            <TableHead>Record</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((log) => {
            const actor = profiles.find((p) => p.profile_id === log.actor_id)
            return (
              <TableRow key={log.log_id}>
                <TableCell className="whitespace-nowrap">
                  {log.created_at.slice(0, 16).replace('T', ' ')}
                </TableCell>
                <TableCell>{actor ? `${actor.first_name} ${actor.last_name}` : 'System'}</TableCell>
                <TableCell>
                  <Badge>{log.action}</Badge>
                </TableCell>
                <TableCell>{log.table_name}</TableCell>
                <TableCell className="text-muted">{log.record_id}</TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </DashboardShell>
  )
}
