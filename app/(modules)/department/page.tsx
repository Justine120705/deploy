import ModulePage from '@/components/layout/ModulePage'

export default function DepartmentDashboardPage() {
  return (
    <ModulePage
      role="Department"
      title="Department Dashboard"
      subtitle="Your department clearance overview."
      planned={[
      "Pending clearance items",
      "Active academic holds",
      ]}
    />
  )
}
