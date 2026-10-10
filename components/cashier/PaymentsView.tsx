'use client'

import { useState } from 'react'
import {
  Button,
  Card,
  CardHeader,
  EmptyRow,
  Input,
  Select,
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
import { StatRow } from './StatRow'

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
    <>
      <StatRow
        stats={[
          { label: 'Payments', value: String(payments.length), hint: 'logged this term' },
          { label: 'Total collected', value: formatPeso(total), hint: 'this term', hue: 'teal' },
          {
            label: 'Last payment',
            value: last ? formatPaidOn(last.paidOn).replace(/, \d{4}$/, '') : 'None',
            hint: last ? last.paidOn.slice(0, 4) : 'no payments yet',
          },
          {
            label: 'Average',
            value: payments.length ? formatPeso(Math.round(total / payments.length)) : formatPeso(0),
            hint: 'per payment',
          },
        ]}
      />

      <Card id="record" className="mb-4 scroll-mt-4 p-5">
        <CardHeader title="Log a payment" icon="payments" hue="teal" />
        <p className="mt-1 text-sm text-muted">
          Payments are logged by hand after the student pays at the Cashier&apos;s Office. There is no online gateway.
        </p>
        {owing.length === 0 ? (
          <p className="mt-4 text-sm font-medium">Every charge is paid. There is nothing to log.</p>
        ) : (
          <form onSubmit={submit} noValidate className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
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
            <div className="flex flex-wrap items-center gap-3 sm:col-span-2 lg:col-span-4">
              <Button type="submit" className="max-lg:h-11">
                Log payment
              </Button>
              {saved && (
                <p role="status" className="text-sm font-medium text-hue-teal-strong">
                  {saved}
                </p>
              )}
            </div>
          </form>
        )}
      </Card>

      <Table className="min-w-[420px]">
        <TableHeader>
          <tr>
            <TableHead>Receipt no.</TableHead>
            <TableHead className="hidden md:table-cell">Student no.</TableHead>
            <TableHead>Student name</TableHead>
            <TableHead className="hidden md:table-cell">Charge</TableHead>
            <TableHead className={NUM}>Amount</TableHead>
            <TableHead className="hidden sm:table-cell">Date</TableHead>
            <TableHead className="hidden lg:table-cell">Recorded by</TableHead>
          </tr>
        </TableHeader>
        <TableBody>
          {sorted.length === 0 && <EmptyRow colSpan={7}>No payments logged yet.</EmptyRow>}
          {sorted.map((p) => {
            const c = rows.find((r) => r.chargeId === p.chargeId)
            return (
              <TableRow key={p.receiptNo}>
                <TableCell className="font-semibold">{p.receiptNo}</TableCell>
                <TableCell className="hidden font-normal text-muted md:table-cell">{c?.studentNo}</TableCell>
                <TableCell className="font-normal text-muted">{c?.studentName}</TableCell>
                <TableCell className="hidden font-normal text-muted md:table-cell">{c?.feeType}</TableCell>
                <TableCell className={`${NUM} font-normal text-muted`}>{formatPeso(p.amount)}</TableCell>
                <TableCell className="hidden font-normal text-muted sm:table-cell">{formatPaidOn(p.paidOn)}</TableCell>
                <TableCell className="hidden font-normal text-muted lg:table-cell">{p.recordedBy}</TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
      <p className="mt-3 px-2 text-sm text-muted">
        The Cashier&apos;s Office clearance item clears automatically once every charge is Cleared or Waived.
      </p>
    </>
  )
}
