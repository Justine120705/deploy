import { EmptyRow, Section, StatusBadge, SummaryStrip, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import {
  CASHIER_CHARGES,
  CASHIER_PAYMENTS,
  buildChargeRows,
  chargeTotals,
  formatPaidOn,
  formatPeso,
  plural,
} from '@/lib/mock/cashier-data'

const NUM = 'text-right tabular-nums'

export default function DashboardView() {
  const rows = buildChargeRows(CASHIER_CHARGES, CASHIER_PAYMENTS)
  const t = chargeTotals(rows, CASHIER_PAYMENTS)
  const owing = rows.filter((r) => r.balance > 0)
  const recent = [...CASHIER_PAYMENTS].sort((a, b) => b.paidOn.localeCompare(a.paidOn))
  const chargeOf = (chargeId: number) => rows.find((r) => r.chargeId === chargeId)

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Total charged', value: formatPeso(t.totalCharged), hint: plural(rows.length, 'charge') },
          { label: 'Collected', value: formatPeso(t.collected), hint: plural(CASHIER_PAYMENTS.length, 'payment'), hue: 'teal' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'still to collect', hue: 'amber' },
          { label: 'Finance cleared', value: String(t.clearedCount), hint: `of ${plural(rows.length, 'student')}` },
        ]}
      />

      <Section title="Students with a balance" description="Collect these first.">
        <Table className="min-w-[420px]">
          <TableHeader>
            <tr>
              <TableHead>Student</TableHead>
              <TableHead className="hidden md:table-cell">Fee type</TableHead>
              <TableHead className={NUM}>Balance</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="hidden lg:table-cell">Last payment</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {owing.length === 0 && <EmptyRow colSpan={5}>No student has a balance.</EmptyRow>}
            {owing.map((r) => (
              <TableRow key={r.chargeId}>
                <TableCell>
                  <span className="block font-medium">{r.studentName}</span>
                  <span className="block text-xs text-muted">{r.studentNo}</span>
                </TableCell>
                <TableCell className="hidden text-muted md:table-cell">{r.feeType}</TableCell>
                <TableCell className={`${NUM} font-medium`}>{formatPeso(r.balance)}</TableCell>
                <TableCell>
                  <StatusBadge status={r.status} />
                </TableCell>
                <TableCell className="hidden text-muted lg:table-cell">
                  {r.lastPaymentOn ? formatPaidOn(r.lastPaymentOn) : 'None yet'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Section>

      <Section title="Recent payments">
        <Table className="min-w-[420px]">
          <TableHeader>
            <tr>
              <TableHead>Receipt no.</TableHead>
              <TableHead>Student</TableHead>
              <TableHead className="hidden md:table-cell">Fee type</TableHead>
              <TableHead className={NUM}>Amount</TableHead>
              <TableHead className="hidden sm:table-cell">Date</TableHead>
              <TableHead className="hidden lg:table-cell">Recorded by</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {recent.length === 0 && <EmptyRow colSpan={6}>No payments logged yet.</EmptyRow>}
            {recent.map((p) => {
              const c = chargeOf(p.chargeId)
              return (
                <TableRow key={p.receiptNo}>
                  <TableCell className="text-muted">{p.receiptNo}</TableCell>
                  <TableCell>
                    <span className="block font-medium">{c?.studentName}</span>
                    <span className="block text-xs text-muted sm:hidden">{formatPaidOn(p.paidOn)}</span>
                  </TableCell>
                  <TableCell className="hidden text-muted md:table-cell">{c?.feeType}</TableCell>
                  <TableCell className={`${NUM} font-medium`}>{formatPeso(p.amount)}</TableCell>
                  <TableCell className="hidden text-muted sm:table-cell">{formatPaidOn(p.paidOn)}</TableCell>
                  <TableCell className="hidden text-muted lg:table-cell">{p.recordedBy}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </Section>
    </div>
  )
}
