import { EmptyRow, Section, StatusBadge, SummaryStrip, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import type { CashierLedger, FinanceClearance } from '@/lib/data/cashier'
import { formatPeso, formatTimestamp, plural } from './format'

const NUM = 'text-right tabular-nums'

export default function DashboardView({ ledger, finance }: { ledger: CashierLedger; finance: FinanceClearance | null }) {
  const { charges, payments, totals: t } = ledger
  const owing = charges.filter((c) => c.balance > 0)
  const recent = payments.slice(0, 8)

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Total charged', value: formatPeso(t.totalCharged), hint: plural(charges.length, 'charge') },
          { label: 'Collected', value: formatPeso(t.collected), hint: plural(payments.length, 'payment'), hue: 'teal' },
          { label: 'Outstanding', value: formatPeso(t.outstanding), hint: 'still to collect', hue: 'amber' },
          {
            label: 'Finance cleared',
            value: finance ? String(finance.cleared) : '-',
            hint: finance ? `of ${plural(finance.items.length, 'request')}` : 'not available',
          },
        ]}
      />

      <Section title="Charges with a balance" description="Collect these first.">
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
            {owing.map((c) => (
              <TableRow key={c.chargeId}>
                <TableCell>
                  <span className="block font-medium">{c.studentName}</span>
                  <span className="block text-xs text-muted">{c.studentNo}</span>
                </TableCell>
                <TableCell className="hidden text-muted md:table-cell">{c.feeType}</TableCell>
                <TableCell className={`${NUM} font-medium`}>{formatPeso(c.balance)}</TableCell>
                <TableCell>
                  <StatusBadge status={c.status} />
                </TableCell>
                <TableCell className="hidden text-muted lg:table-cell">
                  {c.lastPaymentAt ? formatTimestamp(c.lastPaymentAt) : 'None yet'}
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
            {recent.map((p) => (
              <TableRow key={p.paymentId}>
                <TableCell className="text-muted">{p.receiptNo}</TableCell>
                <TableCell>
                  <span className="block font-medium">{p.studentName}</span>
                  <span className="block text-xs text-muted sm:hidden">{formatTimestamp(p.paidAt)}</span>
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
