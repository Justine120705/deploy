import ModulePage from '@/components/layout/ModulePage'

export default function CashierPaymentsPage() {
  return (
    <ModulePage
      role="Cashier"
      title="Payments"
      subtitle="Record payments against charges."
      planned={[
      "Payment entry form",
      "Payment history",
      ]}
    />
  )
}
