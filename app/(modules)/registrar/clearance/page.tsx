import ModulePage from '@/components/layout/ModulePage'

export default function RegistrarClearancePage() {
  return (
    <ModulePage
      role="Registrar"
      title="Clearance"
      subtitle="Final approval of student clearances."
      planned={[
      "Clearances with all items cleared",
      "Final approval action",
      ]}
    />
  )
}
