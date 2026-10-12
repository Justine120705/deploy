import DashboardShell from '@/components/layout/DashboardShell'
import { ResponsiveTable, type Column } from '@/components/student/ResponsiveTable'
import { StatGrid } from '@/components/student/StatGrid'
import { Badge, EmptyState, Section } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { getStudentGradesState, type GradeResult, type StudentGrade } from '@/lib/data/grades'

const TONE: Record<GradeResult, 'success' | 'danger' | 'neutral'> = {
  Passed: 'success',
  Failed: 'danger',
  Incomplete: 'neutral',
  Dropped: 'neutral',
}

const columns: Column<StudentGrade>[] = [
  { key: 'code', header: 'Code', primary: true, cell: (g) => g.subjectCode },
  { key: 'course', header: 'Course', cell: (g) => g.subjectTitle },
  { key: 'units', header: 'Units', className: 'w-20', cell: (g) => g.units },
  { key: 'grade', header: 'Grade', className: 'w-24 font-semibold', cell: (g) => g.gradeCode },
  { key: 'remarks', header: 'Remarks', badge: true, cell: (g) => <Badge tone={TONE[g.result]}>{g.result}</Badge> },
]

export default async function StudentGradesPage() {
  const profile = await requireRole('Student')
  const state = await getStudentGradesState()

  if (state.kind === 'error') {
    return (
      <DashboardShell profile={profile} title="Grades" subtitle="Final grades per subject">
        <div role="alert">
          <EmptyState title="We could not load your grades">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      </DashboardShell>
    )
  }

  if (state.terms.length === 0) {
    return (
      <DashboardShell profile={profile} title="Grades" subtitle="Final grades per subject">
        <EmptyState title="No grades posted yet">
          Your grades appear here once the Registrar posts them for an approved enrollment.
        </EmptyState>
      </DashboardShell>
    )
  }

  const latest = state.terms[0]
  const passed = latest.grades.filter((g) => g.result === 'Passed').length
  const failed = latest.grades.filter((g) => g.result === 'Failed').length

  return (
    <DashboardShell profile={profile} title="Grades" subtitle={`${latest.label} · final grades per subject`}>
      <div className="flex flex-col gap-8">
        <StatGrid
          stats={[
            { label: 'GWA', value: latest.gwa === null ? '-' : latest.gwa.toFixed(2), hint: `${latest.label}, lower is better` },
            { label: 'Units earned', value: latest.earnedUnits, hint: `of ${latest.enrolledUnits} graded` },
            { label: 'Passed', value: passed, hint: 'subjects', hue: passed > 0 ? 'teal' : undefined },
            { label: 'Failed', value: failed, hint: 'subjects', hue: failed > 0 ? 'rose' : undefined },
          ]}
        />
        {state.terms.map((t) => (
          <Section
            key={t.termId}
            title={t.label}
            description={`${t.grades.length} ${t.grades.length === 1 ? 'subject' : 'subjects'} · GWA ${t.gwa === null ? '-' : t.gwa.toFixed(2)}`}
          >
            <ResponsiveTable
              columns={columns}
              rows={t.grades}
              rowKey={(g) => g.id}
              caption={`Final grades, ${t.label}`}
              empty="No grades have been posted for this term yet."
            />
          </Section>
        ))}
      </div>
    </DashboardShell>
  )
}
