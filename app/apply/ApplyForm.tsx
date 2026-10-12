'use client'

import { useActionState } from 'react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { submitApplication, type ApplyState } from '@/lib/data/apply-actions'
import type { ProgramOption } from './programs'

const INITIAL_STATE: ApplyState = { status: 'idle', message: '' }

export function ApplyForm({ programs }: { programs: ProgramOption[] }) {
  const [state, formAction, isPending] = useActionState(submitApplication, INITIAL_STATE)
  const fe = state.fieldErrors ?? {}
  const v = state.values

  return (
    <form action={formAction} noValidate className="relative flex flex-col gap-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <Input id="firstName" name="firstName" label="First name" autoComplete="given-name" required maxLength={100} defaultValue={v?.firstName} error={fe.firstName} />
        <Input id="lastName" name="lastName" label="Last name" autoComplete="family-name" required maxLength={100} defaultValue={v?.lastName} error={fe.lastName} />
      </div>
      <Input id="email" name="email" type="email" label="Email address" autoComplete="email" inputMode="email" spellCheck={false} required maxLength={254} defaultValue={v?.email} error={fe.email} />
      <Input id="mobile" name="mobile" type="tel" label="Mobile number (optional)" autoComplete="tel" inputMode="tel" maxLength={20} defaultValue={v?.mobile} error={fe.mobile} />
      <Select id="programId" name="programId" label="Program" required defaultValue={v?.programId ?? ''} error={fe.programId}>
        <option value="" disabled>
          {programs.length === 0 ? 'Programs are unavailable right now' : 'Choose a program'}
        </option>
        {programs.map((p) => (
          <option key={p.program_id} value={p.program_id}>
            {p.code} - {p.name}
          </option>
        ))}
      </Select>

      {/* Honeypot: hidden from people and assistive tech. Bots fill it; the server then ignores the application. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
        <label htmlFor="website">Website</label>
        <input id="website" name="website" type="text" tabIndex={-1} autoComplete="off" />
      </div>

      {state.status === 'error' && state.message && (
        <p role="alert" className="rounded-md bg-danger-soft px-3 py-2 text-sm text-danger">
          {state.message}
        </p>
      )}

      <Button type="submit" disabled={isPending || programs.length === 0} aria-busy={isPending} className="mt-1 w-full">
        {isPending ? 'Sending...' : 'Submit application'}
      </Button>
    </form>
  )
}
