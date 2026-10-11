'use client'

import { createContext, useActionState, useContext, useState } from 'react'
import { Button, EmptyRow, Section, StatusBadge, SummaryStrip, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { Icon } from '@/components/layout/Icon'
import { cn } from '@/lib/utils'
import { issueFinalClearance, type IssueClearanceState } from '@/lib/data/registrar-actions'
import type { RegistrarClearance } from '@/lib/data/registrar'
import RowRadio from './RowRadio'
import { QueueSheet, QueueTable, StatusLine, StudentCell } from './QueueParts'

const INITIAL: IssueClearanceState = { status: 'idle', message: '' }

// Fixed zone so the server and the browser print the same text.
const fmt = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'Asia/Manila' })
const day = (iso: string | null) => (iso ? fmt.format(new Date(iso)) : '-')

type Ctx = {
  rows: RegistrarClearance[]
  selected: number | null
  select: (id: number) => void
  current: RegistrarClearance | undefined
  state: IssueClearanceState
  formAction: (payload: FormData) => void
  pending: boolean
}

const Context = createContext<Ctx | null>(null)

function useClearance() {
  const ctx = useContext(Context)
  if (!ctx) throw new Error('ClearanceReview parts must be inside ClearanceProvider')
  return ctx
}

export function ClearanceProvider({ rows, children }: { rows: RegistrarClearance[]; children: React.ReactNode }) {
  const [selected, setSelected] = useState<number | null>(null)
  const [state, formAction, pending] = useActionState(issueFinalClearance, INITIAL)
  const current = rows.find((r) => r.clearanceId === selected)

  return (
    <Context.Provider value={{ rows, selected, select: setSelected, current, state, formAction, pending }}>
      {children}
    </Context.Provider>
  )
}

// Why the button is locked, in words (empty when it can be used).
function lockReason(r: RegistrarClearance | undefined): string {
  if (!r) return 'Select a request to issue its final clearance.'
  if (r.approved) return ''
  if (r.totalItems === 0) return 'This request has no offices to clear yet.'
  if (!r.ready) {
    const left = r.totalItems - r.clearedItems
    return `${left} of ${r.totalItems} offices have not cleared yet: ${r.pendingDepartments.join(', ')}.`
  }
  return ''
}

export function ClearanceActions() {
  const { current, formAction, pending } = useClearance()
  const canIssue = !!current && !current.approved && current.ready
  return (
    <form action={formAction}>
      <input type="hidden" name="clearanceId" value={current?.clearanceId ?? ''} />
      <Button type="submit" disabled={!canIssue || pending} className="max-sm:w-full">
        <Icon name="check" className="size-4" />
        {pending ? 'Issuing...' : 'Issue final clearance'}
      </Button>
    </form>
  )
}

export function ClearanceBody() {
  const { rows, selected, select, current, state } = useClearance()
  const ready = rows.filter((r) => !r.approved && r.ready).length
  const waiting = rows.filter((r) => !r.approved && !r.ready).length
  const approved = rows.filter((r) => r.approved).length

  let hint = lockReason(current)
  if (current?.approved) {
    hint = `${current.studentName} has final clearance, approved by ${current.approvedByName ?? 'the Registrar'} on ${day(current.approvedAt)}.`
  } else if (current && current.ready) {
    hint = `${current.studentName} has cleared every office. Final clearance can be issued.`
  }

  return (
    <div className="flex flex-col gap-6">
      <SummaryStrip
        items={[
          { label: 'Ready to issue', value: ready, hint: 'every office cleared', hue: ready ? 'teal' : undefined },
          { label: 'Waiting', value: waiting, hint: 'offices still open', hue: waiting ? 'amber' : undefined },
          { label: 'Issued', value: approved, hint: 'final clearance' },
        ]}
      />

      <Section title="Clearance requests" description="Final approval unlocks only when every office, including Finance, has cleared.">
        <QueueSheet
          toolbar={
            <>
              <StatusLine>{hint}</StatusLine>
              <p
                role="status"
                aria-live="polite"
                className={cn('basis-64 text-sm', state.status === 'error' ? 'font-medium text-danger' : 'text-muted')}
              >
                {state.message}
              </p>
            </>
          }
          footer={<p className="text-sm text-muted">{rows.length} {rows.length === 1 ? 'request' : 'requests'} this term</p>}
        >
          <QueueTable minWidth="min-w-[720px]">
            <TableHeader>
              <tr>
                <TableHead className="w-12"><span className="sr-only">Select</span></TableHead>
                <TableHead>Student</TableHead>
                <TableHead>Offices cleared</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Requested</TableHead>
              </tr>
            </TableHeader>
            <TableBody>
              {rows.length === 0 && <EmptyRow colSpan={5}>No clearance requests this term.</EmptyRow>}
              {rows.map((r) => (
                <TableRow key={r.clearanceId} className={cn(selected === r.clearanceId && 'bg-accent')}>
                  <TableCell className="w-12 px-1.5">
                    <RowRadio name="clearance" checked={selected === r.clearanceId} onChange={() => select(r.clearanceId)} label={`Select ${r.studentName}`} />
                  </TableCell>
                  <TableCell><StudentCell name={r.studentName} sub={r.studentNo || undefined} /></TableCell>
                  <TableCell className="text-muted">{r.clearedItems} of {r.totalItems}</TableCell>
                  <TableCell><StatusBadge status={r.approved ? 'Approved' : 'Pending'} /></TableCell>
                  <TableCell className="whitespace-nowrap text-muted">{day(r.requestedAt)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </QueueTable>
        </QueueSheet>
      </Section>

      {current && (
        <Section title={`Offices for ${current.studentName}`}>
          <QueueSheet
            footer={
              current.approved ? (
                <p className="text-sm text-muted">
                  Approved by {current.approvedByName ?? 'the Registrar'} on {day(current.approvedAt)}.
                </p>
              ) : undefined
            }
          >
            <QueueTable minWidth="min-w-[560px]">
              <TableHeader>
                <tr>
                  <TableHead>Office</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Cleared on</TableHead>
                  <TableHead>Remarks</TableHead>
                </tr>
              </TableHeader>
              <TableBody>
                {current.items.length === 0 && <EmptyRow colSpan={4}>No offices on this request yet.</EmptyRow>}
                {current.items.map((i) => (
                  <TableRow key={i.id}>
                    <TableCell className="font-semibold">{i.department}</TableCell>
                    <TableCell><StatusBadge status={i.status} /></TableCell>
                    <TableCell className="whitespace-nowrap text-muted">{day(i.clearedAt)}</TableCell>
                    <TableCell className="text-muted">{i.remarks ?? '-'}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </QueueTable>
          </QueueSheet>
        </Section>
      )}
    </div>
  )
}
