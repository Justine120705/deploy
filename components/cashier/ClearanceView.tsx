import { EmptyRow, Section, StatusBadge, SummaryStrip, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import type { FinanceClearance } from '@/lib/data/cashier'
import { formatPeso, formatTimestamp } from './format'

const NUM = 'text-right tabular-nums'

// Read-only: the Finance item is cleared by the database, not by a button. A hand-clear is not offered
// here because the mock screen never had one.
export default function ClearanceView({ data }: { data: FinanceClearance }) {
  const { items } = data

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Requests', value: String(items.length), hint: 'in clearance' },
          { label: 'Cleared', value: String(data.cleared), hint: 'finance items', hue: 'teal' },
          { label: 'Pending', value: String(data.pending), hint: 'awaiting settlement', hue: 'amber' },
          { label: 'Outstanding', value: formatPeso(data.outstanding), hint: 'still to collect' },
        ]}
      />
      <Section
        title="Finance clearance by student"
        description="A student's Finance item clears automatically once every charge for the term is Cleared or Waived. An active Financial hold keeps it pending until the hold is lifted."
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
            {items.length === 0 && <EmptyRow colSpan={5}>No student has requested clearance yet.</EmptyRow>}
            {items.map((i) => (
              <TableRow key={i.itemId}>
                <TableCell>
                  <span className="block font-medium">{i.studentName}</span>
                  <span className="block text-xs text-muted">{i.studentNo}</span>
                  {i.hasHold && i.status === 'Pending' && (
                    <span className="mt-1 block text-xs font-medium text-warning">
                      Active hold{i.holdReason ? `: ${i.holdReason}` : ''}
                    </span>
                  )}
                </TableCell>
                <TableCell className="hidden text-muted md:table-cell">
                  {i.chargeCount === 1 ? '1 charge' : `${i.chargeCount} charges`}
                </TableCell>
                <TableCell className={`${NUM} font-medium`}>{formatPeso(i.balance)}</TableCell>
                <TableCell>
                  <StatusBadge status={i.status} />
                </TableCell>
                <TableCell className="hidden text-muted sm:table-cell">
                  {i.status === 'Cleared' && i.clearedAt ? formatTimestamp(i.clearedAt) : 'Not yet'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Section>
    </div>
  )
}
