import ModulePage from '@/components/layout/ModulePage'

export default function DepartmentHoldsPage() {
  return (
    <ModulePage
      role="Department"
      title="Academic Holds"
      subtitle="Place and lift academic holds."
      planned={[
      "Active holds in your department",
      "Place a hold",
      "Lift a hold",
      ]}
    />
  )
}
