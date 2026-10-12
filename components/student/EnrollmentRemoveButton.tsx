'use client'

import { useActionState } from 'react'
import { Button } from '@/components/ui'
import { removeEnrollmentSection, type EnrollmentActionState } from '@/lib/data/enrollment-actions'

const INITIAL: EnrollmentActionState = { status: 'idle', message: '' }

// Removes one section from a Pending enrollment (server action). Success redirects with a notice; an
// error stays here, under the button, because the row is still on the page.
export default function EnrollmentRemoveButton({
  enrollmentId,
  itemId,
  label,
}: {
  enrollmentId: number
  itemId: number
  label: string
}) {
  const [state, formAction, pending] = useActionState(removeEnrollmentSection, INITIAL)

  return (
    <form action={formAction}>
      <input type="hidden" name="enrollmentId" value={enrollmentId} />
      <input type="hidden" name="enrollmentItemId" value={itemId} />
      <Button type="submit" variant="outline" disabled={pending} aria-disabled={pending} aria-label={`Remove ${label}`}>
        {pending ? 'Removing...' : 'Remove'}
      </Button>
      <p role="status" aria-live="polite" className={state.message ? 'mt-2 max-w-[40ch] text-sm font-medium whitespace-normal text-danger' : 'sr-only'}>
        {state.message}
      </p>
    </form>
  )
}
