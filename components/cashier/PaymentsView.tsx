'use client'

import { useState } from 'react'
import {
  Button,
  Section,
  EmptyRow,
  Input,
  Select,
  SummaryStrip,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import {
  CASHIER_CHARGES,
  CASHIER_PAYMENTS,
  buildChargeRows,
  formatPaidOn,
  formatPeso,
  type CashierPayment,
} from '@/lib/mock/cashier-data'

const NUM = 'text-right tabular-nums'

const receiptFor = (n: number) => `OR-${String(n).padStart(4, '0')}`

type FieldErrors = { charge?: string; amount?: string; receipt?: string; date?: string }

// Payment log plus the manual entry form. Entries live in local state only (nothing is saved):
// there is no payment gateway, the cashier logs each payment by hand.
export default function PaymentsView() {
  const [payments, setPayments] = useState<CashierPayment[]>(CASHIER_PAYMENTS)
  const [chargeId, setChargeId] = useState('')
  const [amount, setAmount] = useState('')
  const [receipt, setReceipt] = useState(receiptFor(CASHIER_PAYMENTS.length + 1))
  const [date, setDate] = useState('')
  const [errors, setErrors] = useState<FieldErrors>({})
  const [saved, setSaved] = useState('')

  const rows = buildChargeRows(CASHIER_CHARGES, payments)
  const owing = rows.filter((r) => r.balance > 0)
  const selected = rows.find((r) => String(r.chargeId) === chargeId)

  const sorted = [...payments].sort((a, b) => b.paidOn.localeCompare(a.paidOn) || b.receiptNo.localeCompare(a.receiptNo))
  const total = payments.reduce((s, p) => s + p.amount, 0)
  const last = sorted[0]

  function submit(e: React.FormEvent) {
    e.preventDefault()
    const next: FieldErrors = {}
    const value = Number(amount)
    if (!selected) next.charge = 'Choose the charge this payment is for.'
    if (!amount || !Number.isFinite(value) || value <= 0) next.amount = 'Enter an amount greater than 0.'
    else if (selected && value > selected.balance) next.amount = `The balance is only ${formatPeso(selected.balance)}.`
    if (!receipt.trim()) next.receipt = 'Enter the receipt number.'
    else if (payments.some((p) => p.receiptNo.toLowerCase() === receipt.trim().toLowerCase()))
      next.receipt = 'This receipt number is already used.'
    if (!date) next.date = 'Choose the date paid.'
    setErrors(next)
    setSaved('')
    if (Object.keys(next).length > 0 || !selected) return

    setPayments((prev) => [
      ...prev,
      { receiptNo: receipt.trim(), chargeId: selected.chargeId, amount: value, paidOn: date, recordedBy: 'Cashier' },
    ])
    setSaved(`Logged ${formatPeso(value)} from ${selected.studentName} as ${receipt.trim()}. Not saved to the database yet.`)
    setChargeId('')
    setAmount('')
    setDate('')
    setReceipt(receiptFor(payments.length + 2))
  }

  return (
    <div className="flex flex-col gap-8">
      <SummaryStrip
        items={[
          { label: 'Payments', value: String(payments.length), hint: 'logged this term' },
          { label: 'Total collected', value: formatPeso(total), hint: 'this term', hue: 'teal' },
          {
            label: 'Last payment',
            value: last ? formatPaidOn(last.paidOn).replace(/, \d{4}$/, '') : 'None',
            hint: last ? last.paidOn.slice(0, 4) : 'no payments yet',
          },
        ]}
      />

      <Section
        title="Log a payment"
        description="Log each payment by hand after the student pays at the Cashier's Office. There is no online gateway."
      >
        <div id="record" className="scroll-mt-4 rounded-lg border border-edge bg-card p-4 lg:p-5">
          {owing.length === 0 ? (
            <p className="text-sm font-medium">Every charge is paid. There is nothing to log.</p>
          ) : (
            <form
              onSubmit={submit}
              noValidate
              className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1fr)_auto] lg:items-start"
            >
              <div className="sm:col-span-2 lg:col-span-1">
                <Select
                  id="pay-charge"
                  label="Charge"
                  value={chargeId}
                  onChange={(e) => setChargeId(e.target.value)}
                  error={errors.charge}
                >
                  <option value="">Choose a charge</option>
                  {owing.map((r) => (
                    <option key={r.chargeId} value={r.chargeId}>
                      {r.studentName}, {r.feeType} ({formatPeso(r.balance)} left)
                    </option>
                  ))}
                </Select>
              </div>
              <Input
                id="pay-amount"
                label="Amount (PHP)"
                type="number"
                inputMode="decimal"
                min="0"
                step="0.01"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                error={errors.amount}
              />
              <Input
                id="pay-receipt"
                label="Receipt no."
                value={receipt}
                onChange={(e) => setReceipt(e.target.value)}
                error={errors.receipt}
              />
              <Input
                id="pay-date"
                label="Date paid"
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                error={errors.date}
              />
              <Button type="submit" className="sm:col-span-2 lg:col-span-1 lg:mt-[26px]">
                Log payment
              </Button>
            </form>
          )}
          {saved && (
            <p role="status" className="mt-4 text-sm font-medium text-hue-teal-strong">
              {saved}
            </p>
          )}
        </div>
      </Section>

      <Section
        title="Payment log"
        description="The Cashier's Office item clears automatically once every charge is Cleared or Waived."
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
            {sorted.length === 0 && <EmptyRow colSpan={6}>No payments logged yet.</EmptyRow>}
            {sorted.map((p) => {
              const c = rows.find((r) => r.chargeId === p.chargeId)
              return (
                <TableRow key={p.receiptNo}>
                  <TableCell className="font-medium">{p.receiptNo}</TableCell>
                  <TableCell>
                    <span className="block">{c?.studentName}</span>
                    <span className="block text-xs text-muted">
                      {c?.studentNo}
                      <span className="sm:hidden">, {formatPaidOn(p.paidOn)}</span>
                    </span>
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
