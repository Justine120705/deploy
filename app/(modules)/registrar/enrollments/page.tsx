import ModulePage from '@/components/layout/ModulePage'

export default function RegistrarEnrollmentsPage() {
  return (
    <ModulePage
      role="Registrar"
      title="Enrollments"
      subtitle="Review student enrollments."
      planned={[
      "Enrollment list with status",
      "Approve or reject enrollments",
      ]}
    />
  )
}
