import ModulePage from '@/components/layout/ModulePage'

export default function CashierClearancePage() {
  return (
    <ModulePage
      role="Cashier"
      title="Finance Clearance"
      subtitle="Finance clearance per student."
      planned={[
      "Students and finance clearance status",
      "Auto-clears when all charges are Cleared or Waived",
      ]}
    />
  )
}
