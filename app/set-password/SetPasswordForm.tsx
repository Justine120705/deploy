'use client'

import { useActionState, useState } from 'react'
import { Button } from '@/components/ui/Button'
import { FIELD, FIELD_LABEL } from '@/components/ui/Input'
import { setPassword, type SetPasswordState } from './actions'

const INITIAL_STATE: SetPasswordState = { error: null }

export function SetPasswordForm() {
  const [state, formAction, isPending] = useActionState(setPassword, INITIAL_STATE)
  const [visible, setVisible] = useState(false)
  const type = visible ? 'text' : 'password'

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <div className="flex flex-col gap-1.5">
        <label htmlFor="password" className={FIELD_LABEL}>
          New password
        </label>
        <input
          id="password"
          name="password"
          type={type}
          autoComplete="new-password"
          required
          minLength={10}
          maxLength={72}
          aria-describedby="password-hint"
          aria-invalid={state.error ? true : undefined}
          className={FIELD}
        />
        <p id="password-hint" className="text-xs text-muted">
          At least 10 characters. It cannot be your student ID.
        </p>
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="confirm" className={FIELD_LABEL}>
          Confirm password
        </label>
        <input
          id="confirm"
          name="confirm"
          type={type}
          autoComplete="new-password"
          required
          minLength={10}
          maxLength={72}
          aria-invalid={state.error ? true : undefined}
          className={FIELD}
        />
      </div>

      <label className="flex items-center gap-2 text-sm text-muted">
        <input type="checkbox" checked={visible} onChange={(e) => setVisible(e.target.checked)} className="size-4 accent-primary" />
        Show passwords
      </label>

      {state.error && (
        <p role="alert" className="rounded-md bg-danger-soft px-3 py-2 text-sm text-danger">
          {state.error}
        </p>
      )}

      <Button type="submit" disabled={isPending} aria-busy={isPending} className="w-full">
        {isPending ? 'Saving...' : 'Save password and continue'}
      </Button>
    </form>
  )
}
