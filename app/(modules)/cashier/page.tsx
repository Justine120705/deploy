import ModulePage from '@/components/layout/ModulePage'

export default function CashierDashboardPage() {
  return (
    <ModulePage
      role="Cashier"
      title="Cashier Dashboard"
      subtitle="Collections and finance clearance overview."
      planned={[
      "Unpaid charges summary",
      "Recent payments",
      "Students with finance holds",
      ]}
    />
  )
}
