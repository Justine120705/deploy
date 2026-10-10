import { CardHeader, EmptyRow, StatusBadge, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import {
  CASHIER_CHARGES,
  CASHIER_PAYMENTS,
  buildChargeRows,
  chargeTotals,
  formatPaidOn,
  formatPeso,
  plural,
} from '@/lib/mock/cashier-data'
import { StatRow } from './StatRow'

const NUM = 'text-right tabular-nums'

export default function DashboardView() {
  const rows = buildChargeRows(CASHIER_CHARGES, CASHIER_PAYMENTS)
  const t = chargeTotals(rows, CASHIER_PAYMENTS)
  const owing = rows.filter((r) => r.balance > 0)
  const recent = [...CASHIER_PAYMENTS].sort((a, b) => b.paidOn.localeCompare(a.paidOn))
  const chargeOf = (chargeId: number) => rows.find((r) => r.chargeId === chargeId)

  return (
    <>
      <StatRow
        stats={[
          { label: 'Total charged', value: formatPeso(t.totalCharged), hint: plural(rows.length, 'charge') },
          { label: 'Collected', value: formatPeso(t.collected), hint: plural(CASHIER_PAYMENTS.length, 'payment'), hue: 'teal' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'to collect', hue: 'amber' },
          { label: 'Finance cleared', value: String(t.clearedCount), hint: `of ${plural(rows.length, 'student')}` },
        ]}
      />

      <section className="mb-4">
        <CardHeader title="Students with a balance" icon="charges" hue="amber" className="mb-3 px-2" />
        <Table className="min-w-[420px]">
          <TableHeader>
            <tr>
              <TableHead>Student no.</TableHead>
              <TableHead>Student name</TableHead>
              <TableHead className="hidden md:table-cell">Fee type</TableHead>
              <TableHead className={NUM}>Balance</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="hidden lg:table-cell">Last payment</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {owing.length === 0 && <EmptyRow colSpan={6}>No student has a balance.</EmptyRow>}
            {owing.map((r) => (
              <TableRow key={r.chargeId}>
                <TableCell className="font-normal text-muted">{r.studentNo}</TableCell>
                <TableCell className="font-semibold">{r.studentName}</TableCell>
                <TableCell className="hidden font-normal text-muted md:table-cell">{r.feeType}</TableCell>
                <TableCell className={`${NUM} font-normal text-muted`}>{formatPeso(r.balance)}</TableCell>
                <TableCell>
                  <StatusBadge status={r.status} />
                </TableCell>
                <TableCell className="hidden font-normal text-muted lg:table-cell">
                  {r.lastPaymentOn ? formatPaidOn(r.lastPaymentOn) : 'None yet'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </section>

      <section>
        <CardHeader title="Recent payments" icon="payments" hue="teal" className="mb-3 px-2" />
        <Table className="min-w-[420px]">
          <TableHeader>
            <tr>
              <TableHead>Receipt no.</TableHead>
              <TableHead>Student name</TableHead>
              <TableHead className="hidden md:table-cell">Fee type</TableHead>
              <TableHead className={NUM}>Amount</TableHead>
              <TableHead>Date</TableHead>
              <TableHead className="hidden lg:table-cell">Recorded by</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {recent.length === 0 && <EmptyRow colSpan={6}>No payments logged yet.</EmptyRow>}
            {recent.map((p) => {
              const c = chargeOf(p.chargeId)
              return (
                <TableRow key={p.receiptNo}>
                  <TableCell className="font-normal text-muted">{p.receiptNo}</TableCell>
                  <TableCell className="font-semibold">{c?.studentName}</TableCell>
                  <TableCell className="hidden font-normal text-muted md:table-cell">{c?.feeType}</TableCell>
                  <TableCell className={`${NUM} font-normal text-muted`}>{formatPeso(p.amount)}</TableCell>
                  <TableCell className="font-normal text-muted">{formatPaidOn(p.paidOn)}</TableCell>
                  <TableCell className="hidden font-normal text-muted lg:table-cell">{p.recordedBy}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </section>
    </>
  )
}
