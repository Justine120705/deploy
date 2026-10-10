import DashboardShell from '@/components/layout/DashboardShell'
import { UnavailableAction } from '@/components/student/PageActions'
import { ResponsiveTable, type Column } from '@/components/student/ResponsiveTable'
import { StatGrid } from '@/components/student/StatGrid'
import { Badge } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import {
  MOCK_CURRENT_TERM_ID,
  MOCK_STUDENT_ID,
  programs,
  students,
  terms,
  vGrades,
} from '@/lib/mock-data'

type GradeRow = (typeof vGrades)[number]

// Result in words. Only a 5.00 is a fail; INC and DRP are not passing but are not failures either.
function result(g: GradeRow): { label: string; tone: 'success' | 'danger' | 'neutral' } {
  if (g.is_passing) return { label: 'Passed', tone: 'success' }
  if (g.grade_code === 'INC') return { label: 'Incomplete', tone: 'neutral' }
  if (g.grade_code === 'DRP') return { label: 'Dropped', tone: 'neutral' }
  return { label: 'Failed', tone: 'danger' }
}

export default async function StudentGradesPage() {
  const profile = await requireRole('Student')

  const rows = vGrades.filter(
    (g) => g.student_id === MOCK_STUDENT_ID && g.term_id === MOCK_CURRENT_TERM_ID
  )
  const term = terms.find((t) => t.term_id === MOCK_CURRENT_TERM_ID)
  const termLabel = term ? `${term.semester} ${term.school_year}` : ''
  const student = students.find((s) => s.student_id === MOCK_STUDENT_ID)
  const program = programs.find((p) => p.program_id === student?.program_id)

  // GWA is weighted by units, over the subjects that have a numeric grade. Lower is better.
  const numeric = rows.filter((g) => g.numeric_value !== null)
  const numericUnits = numeric.reduce((sum, g) => sum + (g.units ?? 0), 0)
  const gwa =
    numericUnits > 0
      ? (numeric.reduce((sum, g) => sum + (g.numeric_value ?? 0) * (g.units ?? 0), 0) / numericUnits).toFixed(2)
      : '-'
  const enrolledUnits = rows.reduce((sum, g) => sum + (g.units ?? 0), 0)
  const earnedUnits = rows.filter((g) => g.is_passing).reduce((sum, g) => sum + (g.units ?? 0), 0)
  const passed = rows.filter((g) => result(g).label === 'Passed').length
  const failed = rows.filter((g) => result(g).label === 'Failed').length

  const columns: Column<GradeRow>[] = [
    { key: 'code', header: 'Code', primary: true, cell: (g) => g.subject_code },
    { key: 'course', header: 'Course', cell: (g) => g.subject_title },
    { key: 'units', header: 'Units', className: 'w-20', cell: (g) => g.units },
    { key: 'grade', header: 'Grade', className: 'w-24 font-bold', cell: (g) => <b>{g.grade_code}</b> },
    {
      key: 'remarks',
      header: 'Remarks',
      badge: true,
      cell: (g) => {
        const r = result(g)
        return (
          <Badge tone={r.tone} className="text-sm">
            {r.label}
          </Badge>
        )
      },
    },
    { key: 'term', header: 'Term', cell: () => termLabel },
  ]

  return (
    <DashboardShell
      profile={profile}
      title="Grades"
      subtitle={[termLabel, program?.code, 'final grades per subject'].filter(Boolean).join(' · ')}
      actions={<UnavailableAction label="Download grade report" reason="Not available yet." />}
    >
      <div className="flex flex-col gap-4">
        <StatGrid
          stats={[
            { label: 'GWA', value: gwa, hint: `${termLabel}, lower is better` },
            { label: 'Units earned', value: earnedUnits, hint: `of ${enrolledUnits} enrolled` },
            { label: 'Passed', value: passed, hint: 'subjects', hue: passed > 0 ? 'teal' : undefined },
            { label: 'Failed', value: failed, hint: 'subjects', hue: failed > 0 ? 'rose' : undefined },
          ]}
        />
        <ResponsiveTable
          columns={columns}
          rows={rows}
          rowKey={(g) => g.grade_id ?? g.subject_code ?? ''}
          caption={`Final grades, ${termLabel}`}
          empty="No grades have been posted for this term yet."
          footer={`Showing ${rows.length} of ${rows.length} subjects`}
        />
      </div>
    </DashboardShell>
  )
}
