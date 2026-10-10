import { EmptyRow, StatusBadge, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import {
  CASHIER_CHARGES,
  CASHIER_PAYMENTS,
  buildChargeRows,
  chargeTotals,
  formatPeso,
  plural,
} from '@/lib/mock/cashier-data'
import { StatRow } from './StatRow'

const NUM = 'text-right tabular-nums'

export default function ChargesView() {
  const rows = buildChargeRows(CASHIER_CHARGES, CASHIER_PAYMENTS)
  const t = chargeTotals(rows, CASHIER_PAYMENTS)

  return (
    <>
      <StatRow
        stats={[
          { label: 'Total charged', value: formatPeso(t.totalCharged), hint: plural(rows.length, 'charge') },
          { label: 'Collected', value: formatPeso(t.collected), hint: plural(CASHIER_PAYMENTS.length, 'payment'), hue: 'teal' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'to collect', hue: 'amber' },
          { label: 'Unpaid charges', value: String(t.unpaidCount), hint: t.unpaidCount === 1 ? 'student' : 'students' },
        ]}
      />
      <Table className="min-w-[420px]">
        <TableHeader>
          <tr>
            <TableHead>Student no.</TableHead>
            <TableHead>Student name</TableHead>
            <TableHead className="hidden md:table-cell">Fee type</TableHead>
            <TableHead className={`${NUM} hidden sm:table-cell`}>Amount</TableHead>
            <TableHead className={`${NUM} hidden sm:table-cell`}>Paid</TableHead>
            <TableHead className={NUM}>Balance</TableHead>
            <TableHead>Status</TableHead>
          </tr>
        </TableHeader>
        <TableBody>
          {rows.length === 0 && <EmptyRow colSpan={7}>No charges have been posted yet.</EmptyRow>}
          {rows.map((r) => (
            <TableRow key={r.chargeId}>
              <TableCell className="font-normal text-muted">{r.studentNo}</TableCell>
              <TableCell className="font-semibold">{r.studentName}</TableCell>
              <TableCell className="hidden font-normal text-muted md:table-cell">{r.feeType}</TableCell>
              <TableCell className={`${NUM} hidden font-normal text-muted sm:table-cell`}>{formatPeso(r.amount)}</TableCell>
              <TableCell className={`${NUM} hidden font-normal text-muted sm:table-cell`}>{formatPeso(r.paid)}</TableCell>
              <TableCell className={`${NUM} font-normal text-muted`}>{formatPeso(r.balance)}</TableCell>
              <TableCell>
                <StatusBadge status={r.status} />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <p className="mt-3 px-2 text-sm text-muted">
        The Cashier&apos;s Office item clears automatically once every charge is Cleared or Waived.
      </p>
    </>
  )
}
