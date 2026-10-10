import DashboardShell from '@/components/layout/DashboardShell'
import EnrollmentView from '@/components/student/EnrollmentView'
import { requireRole } from '@/lib/auth/session'
import {
  MOCK_CURRENT_TERM_ID,
  MOCK_STUDENT_ID,
  enrollmentItems,
  enrollments,
  sections,
  subjects,
  terms,
} from '@/lib/mock-data'

export default async function StudentEnrollmentPage() {
  const profile = await requireRole('Student')

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
      subtitle="Enroll in subjects and track your enrollment status."
    >
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
