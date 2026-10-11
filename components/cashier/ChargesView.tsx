import { EmptyRow, Section, StatusBadge, SummaryStrip, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import type { CashierLedger } from '@/lib/data/cashier'
import ChargeActions from './ChargeActions'
import { formatDateOnly, formatPeso, plural } from './format'

const NUM = 'text-right tabular-nums'

export default function ChargesView({ ledger }: { ledger: CashierLedger }) {
  const { charges, payments, totals: t } = ledger

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Total charged', value: formatPeso(t.totalCharged), hint: plural(charges.length, 'charge') },
          { label: 'Collected', value: formatPeso(t.collected), hint: plural(payments.length, 'payment'), hue: 'teal' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'still to collect', hue: 'amber' },
          { label: 'Unpaid charges', value: String(t.unpaidCount), hint: t.waived > 0 ? `${formatPeso(t.waived)} waived` : 'to settle' },
        ]}
      />
      <Section
        title="All charges"
        description="Balance is the charge minus its payments. Mark a charge Cleared once it is paid, or Waive it. The Finance clearance item then clears by itself when every charge of the student is Cleared or Waived."
      >
        <Table className="min-w-[420px]">
          <TableHeader>
            <tr>
              <TableHead>Student</TableHead>
              <TableHead className="hidden md:table-cell">Fee type</TableHead>
              <TableHead className={`${NUM} hidden sm:table-cell`}>Amount</TableHead>
              <TableHead className={`${NUM} hidden sm:table-cell`}>Paid</TableHead>
              <TableHead className={NUM}>Balance</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Tag charge</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {charges.length === 0 && <EmptyRow colSpan={7}>No charges have been posted for this term yet.</EmptyRow>}
            {charges.map((c) => (
              <TableRow key={c.chargeId}>
                <TableCell>
                  <span className="block font-medium">{c.studentName}</span>
                  <span className="block text-xs text-muted">
                    {c.studentNo}
                    <span className="md:hidden">, {c.feeType}</span>
                    {c.dueDate && <span className="hidden lg:inline">, due {formatDateOnly(c.dueDate)}</span>}
                  </span>
                </TableCell>
                <TableCell className="hidden text-muted md:table-cell">{c.feeType}</TableCell>
                <TableCell className={`${NUM} hidden text-muted sm:table-cell`}>{formatPeso(c.amount)}</TableCell>
                <TableCell className={`${NUM} hidden text-muted sm:table-cell`}>{formatPeso(c.paid)}</TableCell>
                <TableCell className={`${NUM} font-medium`}>{formatPeso(c.balance)}</TableCell>
                <TableCell>
                  <StatusBadge status={c.status} />
                </TableCell>
                <TableCell>
                  <ChargeActions chargeId={c.chargeId} settled={c.status !== 'Unpaid'} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Section>
    </div>
  )
}
