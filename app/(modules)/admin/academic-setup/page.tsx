import ModulePage from '@/components/layout/ModulePage'

export default function AdminAcademicSetupPage() {
  return (
    <ModulePage
      role="Admin"
      title="Academic Setup"
      subtitle="Terms, programs, subjects and sections."
      planned={[
      "Terms and programs",
      "Subjects and sections",
      "Fee types and document types",
      ]}
    />
  )
}
