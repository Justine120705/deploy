// Mock data for the Cashier screens (Figma frames "Cashier Dashboard", "Charges", "Payments",
// "Finance Clearance"). Static on purpose and separate from lib/mock-data.ts. There is no payment
// gateway: the cashier logs every payment by hand. Replace with live queries later.

export type CashierCharge = {
  chargeId: number
  studentNo: string
  studentName: string
  feeType: string
  amount: number
}

export type CashierPayment = {
  receiptNo: string
  chargeId: number
  amount: number
  /** ISO date, YYYY-MM-DD. */
  paidOn: string
  recordedBy: string
}

export const CASHIER_TERM = '1st Sem 2026-2027'

export const CASHIER_CHARGES: CashierCharge[] = [
  { chargeId: 1, studentNo: '2026-0001', studentName: 'Reyes, Ana', feeType: 'Tuition', amount: 15000 },
  { chargeId: 2, studentNo: '2026-0002', studentName: 'Santos, Ben', feeType: 'Tuition', amount: 15000 },
  { chargeId: 3, studentNo: '2026-0003', studentName: 'Mendoza, Carla', feeType: 'Tuition', amount: 15000 },
]

export const CASHIER_PAYMENTS: CashierPayment[] = [
  { receiptNo: 'OR-0001', chargeId: 1, amount: 15000, paidOn: '2026-09-20', recordedBy: 'Cashier' },
  { receiptNo: 'OR-0002', chargeId: 3, amount: 5000, paidOn: '2026-09-21', recordedBy: 'Cashier' },
]

/** Philippine peso, whole pesos unless there are centavos. */
export function formatPeso(amount: number): string {
  return new Intl.NumberFormat('en-PH', {
    style: 'currency',
    currency: 'PHP',
    minimumFractionDigits: Number.isInteger(amount) ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(amount)
}

/** "2026-09-20" to "Sep 20, 2026". Fixed to UTC so server and browser agree. */
export function formatPaidOn(iso: string): string {
  return new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'UTC',
  })
}

export type ChargeRow = CashierCharge & {
  paid: number
  balance: number
  /** Cleared when nothing is owed, otherwise Unpaid (matches the Figma frames). */
  status: 'Cleared' | 'Unpaid'
  lastPaymentOn: string | null
}

export function buildChargeRows(charges: CashierCharge[], payments: CashierPayment[]): ChargeRow[] {
  return charges.map((c) => {
    const mine = payments.filter((p) => p.chargeId === c.chargeId)
    const paid = mine.reduce((sum, p) => sum + p.amount, 0)
    const balance = Math.max(c.amount - paid, 0)
    const lastPaymentOn = mine.map((p) => p.paidOn).sort().at(-1) ?? null
    return { ...c, paid, balance, status: balance === 0 ? 'Cleared' : 'Unpaid', lastPaymentOn }
  })
}

export function chargeTotals(rows: ChargeRow[], payments: CashierPayment[]) {
  const totalCharged = rows.reduce((s, r) => s + r.amount, 0)
  const collected = payments.reduce((s, p) => s + p.amount, 0)
  return {
    totalCharged,
    collected,
    outstanding: rows.reduce((s, r) => s + r.balance, 0),
    unpaidCount: rows.filter((r) => r.status === 'Unpaid').length,
    clearedCount: rows.filter((r) => r.status === 'Cleared').length,
  }
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`
}
