import ModulePage from '@/components/layout/ModulePage'

export default function StudentDashboardPage() {
  return (
    <ModulePage
      role="Student"
      title="Student Dashboard"
      subtitle="Your clearance, grades and schedule at a glance."
      planned={[
      "Clearance progress and pending items",
      "GWA by term and current grades",
      "Clearance offices and their status",
      ]}
    />
  )
}
