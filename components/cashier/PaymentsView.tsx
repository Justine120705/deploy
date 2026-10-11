import { EmptyRow, Section, SummaryStrip, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import type { CashierLedger } from '@/lib/data/cashier'
import PaymentForm, { type PaymentOption } from './PaymentForm'
import { formatPeso, formatTimestamp } from './format'

const NUM = 'text-right tabular-nums'

// Payment log plus the manual entry form. Payments are saved to the database; there is no payment
// gateway, the cashier logs each payment by hand.
export default function PaymentsView({ ledger }: { ledger: CashierLedger }) {
  const { charges, payments, totals: t } = ledger
  const options: PaymentOption[] = charges
    .filter((c) => c.status === 'Unpaid' && c.balance > 0)
    .map((c) => ({ chargeId: c.chargeId, label: `${c.studentName}, ${c.feeType} (${formatPeso(c.balance)} left)` }))
  const last = payments[0]

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Payments', value: String(payments.length), hint: 'logged this term' },
          { label: 'Total collected', value: formatPeso(t.collected), hint: 'this term', hue: 'teal' },
          {
            label: 'Last payment',
            value: last ? formatTimestamp(last.paidAt).replace(/, \d{4}$/, '') : 'None',
            hint: last ? formatTimestamp(last.paidAt).slice(-4) : 'no payments yet',
          },
        ]}
      />

      <Section
        title="Log a payment"
        description="Log each payment by hand after the student pays at the Cashier's Office. The date is recorded automatically."
      >
        <div id="record" className="scroll-mt-4 rounded-lg border border-edge bg-card p-4 lg:p-5">
          {options.length === 0 ? (
            <p className="text-sm font-medium">Every charge is settled. There is nothing to log.</p>
          ) : (
            <PaymentForm options={options} />
          )}
        </div>
      </Section>

      <Section
        title="Payment log"
        description="The Finance clearance item clears by itself once every charge is Cleared or Waived."
      >
        <Table className="min-w-[420px]">
          <TableHeader>
            <tr>
              <TableHead>Receipt no.</TableHead>
              <TableHead>Student</TableHead>
              <TableHead className="hidden md:table-cell">Charge</TableHead>
              <TableHead className={NUM}>Amount</TableHead>
              <TableHead className="hidden sm:table-cell">Date</TableHead>
              <TableHead className="hidden lg:table-cell">Recorded by</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {payments.length === 0 && <EmptyRow colSpan={6}>No payments logged yet.</EmptyRow>}
            {payments.map((p) => (
              <TableRow key={p.paymentId}>
                <TableCell className="font-medium">{p.receiptNo}</TableCell>
                <TableCell>
                  <span className="block">{p.studentName}</span>
                  <span className="block text-xs text-muted">
                    {p.studentNo}
                    <span className="sm:hidden">, {formatTimestamp(p.paidAt)}</span>
                  </span>
                </TableCell>
                <TableCell className="hidden text-muted md:table-cell">{p.feeType}</TableCell>
                <TableCell className={`${NUM} font-medium`}>{formatPeso(p.amount)}</TableCell>
                <TableCell className="hidden text-muted sm:table-cell">{formatTimestamp(p.paidAt)}</TableCell>
                <TableCell className="hidden text-muted lg:table-cell">{p.recordedBy}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Section>
    </div>
  )
}
