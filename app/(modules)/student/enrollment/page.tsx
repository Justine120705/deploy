import DashboardShell from '@/components/layout/DashboardShell'
import EnrollmentView from '@/components/student/EnrollmentView'
import { UnavailableAction } from '@/components/student/PageActions'
import { SampleDataNote } from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import {
  MOCK_CURRENT_TERM_ID,
  MOCK_STUDENT_ID,
  enrollmentItems,
  enrollments,
  programs,
  sections,
  students,
  subjects,
  terms,
} from '@/lib/mock-data'

export default async function StudentEnrollmentPage() {
  const profile = await requireRole('Student')

  const currentTerm = terms.find((t) => t.term_id === MOCK_CURRENT_TERM_ID)
  const student = students.find((s) => s.student_id === MOCK_STUDENT_ID)
  const program = programs.find((p) => p.program_id === student?.program_id)
  const subtitle = [
    currentTerm ? `${currentTerm.semester} ${currentTerm.school_year}` : null,
    program?.code ?? null,
    'your enrolled subjects',
  ]
    .filter(Boolean)
    .join(' · ')

  const sectionOptions = sections.flatMap((s) => {
    const subject = subjects.find((sub) => sub.subject_id === s.subject_id)
    if (!subject) return []
    return [
      {
        section_id: s.section_id,
        term_id: s.term_id,
        section_code: s.section_code,
        subject_code: subject.code,
        subject_title: subject.title,
        units: subject.units,
        schedule: s.schedule,
        capacity: s.capacity,
      },
    ]
  })

  const records = enrollments
    .filter((e) => e.student_id === MOCK_STUDENT_ID)
    .map((e) => ({
      id: e.enrollment_id,
      term_id: e.term_id,
      year_level: e.year_level,
      status: e.status,
      submitted_at: e.submitted_at,
      section_ids: enrollmentItems
        .filter((i) => i.enrollment_id === e.enrollment_id)
        .map((i) => i.section_id),
    }))

  return (
    <DashboardShell
      profile={profile}
      title="Enrollment"
      subtitle={subtitle}
      actions={<UnavailableAction label="Download COR" reason="Not available yet." />}
    >
      <SampleDataNote className="mb-6">Enrollment records are sample data and are not saved yet.</SampleDataNote>
      <EnrollmentView
        terms={terms.map((t) => ({
          term_id: t.term_id,
          label: `${t.school_year} ${t.semester}`,
        }))}
        sections={sectionOptions}
        initialEnrollments={records}
        defaultTermId={MOCK_CURRENT_TERM_ID}
      />
    </DashboardShell>
  )
}
