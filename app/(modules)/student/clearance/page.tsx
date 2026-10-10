import ModulePage from '@/components/layout/ModulePage'

export default function StudentClearancePage() {
  return (
    <ModulePage
      role="Student"
      title="Clearance"
      subtitle="Track each office that must clear you."
      planned={[
      "Clearance items per office with status",
      "Active academic holds",
      "Request final clearance",
      ]}
    />
  )
}
