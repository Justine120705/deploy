import ModulePage from '@/components/layout/ModulePage'

export default function RegistrarGradesPage() {
  return (
    <ModulePage
      role="Registrar"
      title="Encode Grades"
      subtitle="Encode and save grades per section."
      planned={[
      "Section and subject picker",
      "Grade entry table with remarks",
      "Save and mark as saved or unsaved",
      ]}
    />
  )
}
