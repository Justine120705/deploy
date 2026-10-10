import { EmptyRow, Section, StatusBadge, SummaryStrip, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import {
  CASHIER_CHARGES,
  CASHIER_PAYMENTS,
  buildChargeRows,
  chargeTotals,
  formatPeso,
  plural,
} from '@/lib/mock/cashier-data'

const NUM = 'text-right tabular-nums'

export default function ChargesView() {
  const rows = buildChargeRows(CASHIER_CHARGES, CASHIER_PAYMENTS)
  const t = chargeTotals(rows, CASHIER_PAYMENTS)

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Total charged', value: formatPeso(t.totalCharged), hint: plural(rows.length, 'charge') },
          { label: 'Collected', value: formatPeso(t.collected), hint: plural(CASHIER_PAYMENTS.length, 'payment'), hue: 'teal' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'still to collect', hue: 'amber' },
          { label: 'Unpaid charges', value: String(t.unpaidCount), hint: t.unpaidCount === 1 ? 'student' : 'students' },
        ]}
      />
      <Section
        title="All charges"
        description="The Cashier's Office item clears automatically once every charge is Cleared or Waived."
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
            </tr>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && <EmptyRow colSpan={6}>No charges have been posted yet.</EmptyRow>}
            {rows.map((r) => (
              <TableRow key={r.chargeId}>
                <TableCell>
                  <span className="block font-medium">{r.studentName}</span>
                  <span className="block text-xs text-muted">{r.studentNo}</span>
                </TableCell>
                <TableCell className="hidden text-muted md:table-cell">{r.feeType}</TableCell>
                <TableCell className={`${NUM} hidden text-muted sm:table-cell`}>{formatPeso(r.amount)}</TableCell>
                <TableCell className={`${NUM} hidden text-muted sm:table-cell`}>{formatPeso(r.paid)}</TableCell>
                <TableCell className={`${NUM} font-medium`}>{formatPeso(r.balance)}</TableCell>
                <TableCell>
                  <StatusBadge status={r.status} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Section>
    </div>
  )
}
