import ModulePage from '@/components/layout/ModulePage'

export default function StudentGradesPage() {
  return (
    <ModulePage
      role="Student"
      title="Grades"
      subtitle="Your grades per term."
      planned={[
      "Grades per subject with remarks",
      "GWA per term",
      ]}
    />
  )
}
