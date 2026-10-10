import DashboardShell from '@/components/layout/DashboardShell'
import RequestClearanceButton from '@/components/student/RequestClearanceButton'
import { requireRole } from '@/lib/auth/session'
import {
  StatusBadge,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { MOCK_CURRENT_TERM_ID, MOCK_STUDENT_ID, vClearanceItems } from '@/lib/mock-data'

export default async function StudentClearancePage() {
  const profile = await requireRole('Student')

  const items = vClearanceItems.filter(
    (i) => i.student_id === MOCK_STUDENT_ID && i.term_id === MOCK_CURRENT_TERM_ID
  )

  return (
    <DashboardShell
      profile={profile}
      title="Clearance"
      subtitle="Track each office that must clear you."
    >
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>Department</TableHead>
            <TableHead>Status</TableHead>
            <TableHead className="hidden sm:table-cell">Remarks</TableHead>
            <TableHead className="text-right">Action</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {items.map((item) => (
            <TableRow key={item.clearance_item_id}>
              <TableCell>{item.department_name}</TableCell>
              <TableCell>
                <StatusBadge status={item.status ?? 'Pending'} />
              </TableCell>
              <TableCell className="hidden text-muted sm:table-cell">{item.remarks ?? '-'}</TableCell>
              <TableCell className="text-right">
                {item.status === 'Pending' && (
                  <RequestClearanceButton department={item.department_name ?? 'department'} />
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </DashboardShell>
  )
}
