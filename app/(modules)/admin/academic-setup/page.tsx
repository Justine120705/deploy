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
  Tabs,
} from '@/components/ui'
import { departments, programs, sections, subjects, terms } from '@/lib/mock-data'

function SimpleTable({ head, rows }: { head: string[]; rows: React.ReactNode[][] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          {head.map((h) => (
            <TableHead key={h}>{h}</TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((cells, i) => (
          <TableRow key={i}>
            {cells.map((c, j) => (
              <TableCell key={j}>{c}</TableCell>
            ))}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

export default async function AdminAcademicSetupPage() {
  const profile = await requireRole('Admin')

  const deptName = (id: number) => departments.find((d) => d.department_id === id)?.name ?? '-'
  const termLabel = (id: number) => {
    const t = terms.find((x) => x.term_id === id)
    return t ? `${t.semester}, ${t.school_year}` : '-'
  }

  const tabs = [
    {
      id: 'departments',
      label: 'Departments',
      content: (
        <SimpleTable
          head={['Code', 'Name', 'Type']}
          rows={departments.map((d) => [d.code, d.name, d.department_type])}
        />
      ),
    },
    {
      id: 'programs',
      label: 'Programs',
      content: (
        <SimpleTable
          head={['Code', 'Name', 'Department']}
          rows={programs.map((p) => [p.code, p.name, deptName(p.department_id)])}
        />
      ),
    },
    {
      id: 'terms',
      label: 'Terms',
      content: (
        <SimpleTable
          head={['School year', 'Semester', 'Start', 'End', 'Current']}
          rows={terms.map((t) => [
            t.school_year,
            t.semester,
            t.start_date,
            t.end_date,
            t.is_current ? <Badge tone="success">Current</Badge> : '-',
          ])}
        />
      ),
    },
    {
      id: 'subjects',
      label: 'Subjects',
      content: (
        <SimpleTable
          head={['Code', 'Title', 'Units', 'Department']}
          rows={subjects.map((s) => [s.code, s.title, s.units, deptName(s.department_id)])}
        />
      ),
    },
    {
      id: 'sections',
      label: 'Sections',
      content: (
        <SimpleTable
          head={['Section', 'Subject', 'Term', 'Schedule', 'Capacity']}
          rows={sections.map((s) => {
            const subject = subjects.find((x) => x.subject_id === s.subject_id)
            return [
              s.section_code,
              subject ? `${subject.code} ${subject.title}` : '-',
              termLabel(s.term_id),
              s.schedule ?? 'TBA',
              s.capacity,
            ]
          })}
        />
      ),
    },
  ]

  return (
    <DashboardShell
      profile={profile}
      title="Academic Setup"
      subtitle="Departments, programs, terms, subjects and sections."
    >
      <Tabs tabs={tabs} />
    </DashboardShell>
  )
}
