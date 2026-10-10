import ModulePage from '@/components/layout/ModulePage'

export default function CashierChargesPage() {
  return (
    <ModulePage
      role="Cashier"
      title="Charges"
      subtitle="Post and manage student charges."
      planned={[
      "Charges list per student",
      "Add a charge from the fee types",
      "Waive a charge",
      ]}
    />
  )
}
