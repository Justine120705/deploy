'use client'

import { useActionState } from 'react'
import { Button } from '@/components/ui'
import { requestClearance, type RequestClearanceState } from '@/lib/data/clearance-actions'

const INITIAL: RequestClearanceState = { status: 'idle', message: '' }

// Requests the term clearance for the signed-in student (server action). The result is announced in a
// polite live region; on success the page re-renders with the new clearance.
export default function RequestClearanceButton({ className }: { className?: string }) {
  const [state, formAction, pending] = useActionState(requestClearance, INITIAL)

  return (
    <form action={formAction} className={className}>
      <Button type="submit" disabled={pending} aria-disabled={pending}>
        {pending ? 'Requesting...' : 'Request clearance'}
      </Button>
      <p
        role="status"
        aria-live="polite"
        className={state.status === 'error' ? 'mt-2 max-w-[48ch] text-sm font-medium text-danger' : 'mt-2 max-w-[48ch] text-sm text-muted'}
      >
        {state.message}
      </p>
    </form>
  )
}
