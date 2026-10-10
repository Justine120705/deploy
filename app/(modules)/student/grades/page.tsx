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
import { MOCK_CURRENT_TERM_ID, MOCK_STUDENT_ID, vGrades } from '@/lib/mock-data'

export default async function StudentGradesPage() {
  const profile = await requireRole('Student')

  const rows = vGrades.filter(
    (g) => g.student_id === MOCK_STUDENT_ID && g.term_id === MOCK_CURRENT_TERM_ID
  )

  return (
    <DashboardShell profile={profile} title="Grades" subtitle="Your grades per subject.">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>Subject</TableHead>
            <TableHead>Grade</TableHead>
            <TableHead>Result</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((g) => (
            <TableRow key={g.grade_id}>
              <TableCell>
                <span className="font-semibold">{g.subject_code}</span>
                <span className="block text-muted">{g.subject_title}</span>
              </TableCell>
              <TableCell>{g.grade_code}</TableCell>
              <TableCell>
                <Badge tone={g.is_passing ? 'success' : 'danger'}>
                  {g.is_passing ? 'Passed' : 'Not passed'}
                </Badge>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </DashboardShell>
  )
}
