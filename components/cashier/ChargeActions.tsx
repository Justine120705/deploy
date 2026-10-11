'use client'

import { useActionState } from 'react'
import { Button } from '@/components/ui'
import { tagCharge, type TagChargeState } from '@/lib/data/cashier-actions'

const INITIAL: TagChargeState = { status: 'idle', message: '' }

// Tags one charge Cleared or Waived (server action). The row stays mounted after the change, so the
// result is announced in a polite live region next to the buttons.
export default function ChargeActions({ chargeId, settled }: { chargeId: number; settled: boolean }) {
  const [state, formAction, pending] = useActionState(tagCharge, INITIAL)

  return (
    <form action={formAction} className="flex flex-col items-end gap-1.5">
      <input type="hidden" name="chargeId" value={chargeId} />
      {!settled && (
        <div className="flex flex-wrap justify-end gap-2">
          <Button type="submit" name="status" value="Cleared" variant="outline" disabled={pending}>
            Mark cleared
          </Button>
          <Button type="submit" name="status" value="Waived" variant="ghost" disabled={pending}>
            Waive
          </Button>
        </div>
      )}
      <p
        role="status"
        aria-live="polite"
        className={
          state.status === 'error'
            ? 'max-w-[34ch] text-right text-xs font-medium text-danger'
            : 'max-w-[34ch] text-right text-xs text-muted'
        }
      >
        {state.message}
      </p>
    </form>
  )
}
