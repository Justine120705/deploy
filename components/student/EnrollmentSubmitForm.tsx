'use client'

import { useActionState } from 'react'
import { Button, Select } from '@/components/ui'
import { submitEnrollment, type EnrollmentActionState } from '@/lib/data/enrollment-actions'

const INITIAL: EnrollmentActionState = { status: 'idle', message: '' }
const YEARS = [1, 2, 3, 4, 5, 6]

// Creates the enrollment for the current term (server action). The database makes it Pending. On
// success the action redirects back with a notice and the page shows the section picker.
export default function EnrollmentSubmitForm({ termLabel }: { termLabel: string }) {
  const [state, formAction, pending] = useActionState(submitEnrollment, INITIAL)

  return (
    <form
      id="submit-enrollment"
      action={formAction}
      className="flex scroll-mt-4 flex-col gap-4 rounded-lg border border-edge bg-card p-4 lg:p-5"
    >
      <p className="max-w-[60ch] text-sm text-muted">
        You are enrolling for {termLabel}. Choose your year level, then add your subject sections. The Registrar reviews
        the enrollment afterwards.
      </p>
      <div className="grid gap-4 sm:max-w-xs">
        <Select id="enroll-year" name="yearLevel" label="Year level" defaultValue="1" required error={state.fieldErrors?.yearLevel}>
          {YEARS.map((y) => (
            <option key={y} value={y}>
              Year {y}
            </option>
          ))}
        </Select>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={pending} aria-disabled={pending}>
          {pending ? 'Submitting...' : 'Submit enrollment'}
        </Button>
        <p
          role="status"
          aria-live="polite"
          className={state.status === 'error' ? 'max-w-[48ch] text-sm font-medium text-danger' : 'max-w-[48ch] text-sm text-muted'}
        >
          {state.message}
        </p>
      </div>
    </form>
  )
}
