import ModulePage from '@/components/layout/ModulePage'

export default function StudentEnrollmentPage() {
  return (
    <ModulePage
      role="Student"
      title="Enrollment"
      subtitle="Your enrolled subjects for the current term."
      planned={[
      "Enrollment status and term",
      "Enrolled subjects, units and schedule",
      ]}
    />
  )
}
