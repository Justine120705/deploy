import { EmptyRow, StatusBadge, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import {
  CASHIER_CHARGES,
  CASHIER_PAYMENTS,
  buildChargeRows,
  chargeTotals,
  formatPaidOn,
  formatPeso,
} from '@/lib/mock/cashier-data'
import { StatRow } from './StatRow'

const NUM = 'text-right tabular-nums'

export default function ClearanceView() {
  const rows = buildChargeRows(CASHIER_CHARGES, CASHIER_PAYMENTS)
  const t = chargeTotals(rows, CASHIER_PAYMENTS)
  const pending = rows.length - t.clearedCount

  return (
    <>
      <StatRow
        stats={[
          { label: 'Students', value: String(rows.length), hint: 'in clearance' },
          { label: 'Cleared', value: String(t.clearedCount), hint: 'finance items', hue: 'teal' },
          { label: 'Pending', value: String(pending), hint: 'awaiting payment', hue: 'amber' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'to collect' },
        ]}
      />
      <Table className="min-w-[420px]">
        <TableHeader>
          <tr>
            <TableHead>Student no.</TableHead>
            <TableHead>Student name</TableHead>
            <TableHead className="hidden md:table-cell">Charges</TableHead>
            <TableHead className={NUM}>Balance</TableHead>
            <TableHead>Finance item</TableHead>
            <TableHead className="hidden sm:table-cell">Cleared on</TableHead>
          </tr>
        </TableHeader>
        <TableBody>
          {rows.length === 0 && <EmptyRow colSpan={6}>No students are in clearance yet.</EmptyRow>}
          {rows.map((r) => (
            <TableRow key={r.chargeId}>
              <TableCell className="font-normal text-muted">{r.studentNo}</TableCell>
              <TableCell className="font-semibold">{r.studentName}</TableCell>
              <TableCell className="hidden font-normal text-muted md:table-cell">1 charge</TableCell>
              <TableCell className={`${NUM} font-normal text-muted`}>{formatPeso(r.balance)}</TableCell>
              <TableCell>
                <StatusBadge status={r.status === 'Cleared' ? 'Cleared' : 'Pending'} />
              </TableCell>
              <TableCell className="hidden font-normal text-muted sm:table-cell">
                {r.status === 'Cleared' && r.lastPaymentOn ? formatPaidOn(r.lastPaymentOn) : 'Not yet'}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <p className="mt-3 px-2 text-sm text-muted">
        The item clears automatically once every charge is Cleared or Waived (REQ-CSH-03).
      </p>
    </>
  )
}
