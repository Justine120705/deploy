import ModulePage from '@/components/layout/ModulePage'

export default function RegistrarDashboardPage() {
  return (
    <ModulePage
      role="Registrar"
      title="Registrar Dashboard"
      subtitle="Records and clearance overview."
      planned={[
      "Enrollments awaiting review",
      "Pending document requests",
      "Clearances ready for final approval",
      ]}
    />
  )
}
