import { EmptyRow, Section, StatusBadge, SummaryStrip, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import {
  CASHIER_CHARGES,
  CASHIER_PAYMENTS,
  buildChargeRows,
  chargeTotals,
  formatPaidOn,
  formatPeso,
} from '@/lib/mock/cashier-data'

const NUM = 'text-right tabular-nums'

export default function ClearanceView() {
  const rows = buildChargeRows(CASHIER_CHARGES, CASHIER_PAYMENTS)
  const t = chargeTotals(rows, CASHIER_PAYMENTS)
  const pending = rows.length - t.clearedCount

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Students', value: String(rows.length), hint: 'in clearance' },
          { label: 'Cleared', value: String(t.clearedCount), hint: 'finance items', hue: 'teal' },
          { label: 'Pending', value: String(pending), hint: 'awaiting payment', hue: 'amber' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'still to collect' },
        ]}
      />
      <Section
        title="Finance clearance by student"
        description="The item clears automatically once every charge is Cleared or Waived (REQ-CSH-03)."
      >
        <Table className="min-w-[420px]">
          <TableHeader>
            <tr>
              <TableHead>Student</TableHead>
              <TableHead className="hidden md:table-cell">Charges</TableHead>
              <TableHead className={NUM}>Balance</TableHead>
              <TableHead>Finance item</TableHead>
              <TableHead className="hidden sm:table-cell">Cleared on</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && <EmptyRow colSpan={5}>No students are in clearance yet.</EmptyRow>}
            {rows.map((r) => (
              <TableRow key={r.chargeId}>
                <TableCell>
                  <span className="block font-medium">{r.studentName}</span>
                  <span className="block text-xs text-muted">{r.studentNo}</span>
                </TableCell>
                <TableCell className="hidden text-muted md:table-cell">1 charge</TableCell>
                <TableCell className={`${NUM} font-medium`}>{formatPeso(r.balance)}</TableCell>
                <TableCell>
                  <StatusBadge status={r.status === 'Cleared' ? 'Cleared' : 'Pending'} />
                </TableCell>
                <TableCell className="hidden text-muted sm:table-cell">
                  {r.status === 'Cleared' && r.lastPaymentOn ? formatPaidOn(r.lastPaymentOn) : 'Not yet'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Section>
    </div>
  )
}
