import Link from 'next/link'
import DashboardShell from '@/components/layout/DashboardShell'
import TableCard from '@/components/admin/TableCard'
import { requireRole } from '@/lib/auth/session'
import {
  Badge,
  StatCard,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  HUE_TEXT,
} from '@/components/ui'
import { auditLogs, profiles, roles } from '@/lib/mock-data'
import { getAuditRows, getRoleCounts } from '@/lib/mock/admin-data'

const ACTION_TONE = { Insert: 'success', Update: 'warning', Delete: 'danger' } as const

export default async function AdminDashboardPage() {
  const profile = await requireRole('Admin')

  const active = profiles.filter((p) => p.is_active).length
  const roleCounts = getRoleCounts()
  const recent = getAuditRows().slice(0, 3)
  const roleNames = roles.map((r) => r.role_name)

  return (
    <DashboardShell profile={profile} title="Dashboard" subtitle="System overview: accounts and recent activity">
      <div className="flex flex-col gap-4">
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard label="Total users" value={profiles.length} hint="accounts" />
          <StatCard
            label="Active"
            value={<span className={HUE_TEXT.teal}>{active}</span>}
            hint="accounts"
          />
          <StatCard
            label="Roles"
            value={roles.length}
            hint={`${roleNames[0]} to ${roleNames[roleNames.length - 1]}`}
          />
          <StatCard label="Audit entries" value={auditLogs.length} hint="recorded so far" />
        </div>

        <TableCard title="Users by role" minWidth="min-w-[480px]">
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead scope="col">Role</TableHead>
              <TableHead scope="col">Users</TableHead>
              <TableHead scope="col">Active</TableHead>
              <TableHead scope="col">Inactive</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {roleCounts.map((r) => (
              <TableRow key={r.role}>
                <TableCell>{r.role}</TableCell>
                <TableCell className="font-normal text-muted">{r.users}</TableCell>
                <TableCell className="font-normal text-muted">{r.active}</TableCell>
                <TableCell className="font-normal text-muted">{r.inactive}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>

        <TableCard
          title="Recent audit entries"
          action={
            <Link
              href="/admin/audit-log"
              className="inline-flex h-9 items-center rounded-full px-3 text-sm font-semibold text-accent-foreground hover:bg-accent max-lg:h-11 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
            >
              View all
            </Link>
          }
          minWidth="min-w-[620px]"
        >
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead scope="col">Time</TableHead>
              <TableHead scope="col">Actor</TableHead>
              <TableHead scope="col">Action</TableHead>
              <TableHead scope="col">Table</TableHead>
              <TableHead scope="col">Record</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {recent.map((log) => (
              <TableRow key={log.id}>
                <TableCell className="whitespace-nowrap font-normal text-muted">{log.when}</TableCell>
                <TableCell>{log.actor}</TableCell>
                <TableCell>
                  <Badge tone={ACTION_TONE[log.action]}>{log.action}</Badge>
                </TableCell>
                <TableCell className="font-normal text-muted">{log.table}</TableCell>
                <TableCell className="font-normal text-muted">{log.record}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>
      </div>
    </DashboardShell>
  )
}
