import ModulePage from '@/components/layout/ModulePage'

export default function DepartmentClearancePage() {
  return (
    <ModulePage
      role="Department"
      title="Clearance Items"
      subtitle="Approve clearance items for your department."
      planned={[
      "Pending items for your department",
      "Approve or reject with remarks",
      ]}
    />
  )
}
