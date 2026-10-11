'use client'

import { createContext, useContext, useState } from 'react'
import { Button, EmptyRow, Section, StatusBadge, SummaryStrip, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { Icon } from '@/components/layout/Icon'
import { cn } from '@/lib/utils'
import { REGISTRAR_ENROLLMENTS, type EnrollmentRow } from '@/lib/mock/registrar-data'
import RowRadio from './RowRadio'
import { QueueSheet, QueueTable, StatusLine, StudentCell } from './QueueParts'

type Ctx = {
  rows: EnrollmentRow[]
  selected: string | null
  select: (id: string) => void
  decide: (status: 'Approved' | 'Rejected') => void
  current: EnrollmentRow | undefined
  note: string
}

const Context = createContext<Ctx | null>(null)

function useReview() {
  const ctx = useContext(Context)
  if (!ctx) throw new Error('EnrollmentsReview parts must be inside EnrollmentsProvider')
  return ctx
}

// Holds the local (not saved) state so the header buttons and the table stay in sync.
export function EnrollmentsProvider({ children }: { children: React.ReactNode }) {
  const [rows, setRows] = useState(REGISTRAR_ENROLLMENTS)
  const [selected, setSelected] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const current = rows.find((r) => r.id === selected)

  function decide(status: 'Approved' | 'Rejected') {
    if (!current) return
    setRows((rs) => rs.map((r) => (r.id === current.id ? { ...r, status } : r)))
    setNote(`${current.name}: enrollment ${status.toLowerCase()}. This is a preview and is not saved.`)
    setSelected(null)
  }

  return (
    <Context.Provider value={{ rows, selected, select: setSelected, decide, current, note }}>
      {children}
    </Context.Provider>
  )
}

export function EnrollmentsActions() {
  const { current, decide } = useReview()
  const canDecide = current?.status === 'Pending'
  return (
    <div className="flex gap-2 max-sm:w-full">
      <Button variant="outline" disabled={!canDecide} onClick={() => decide('Rejected')} className="max-sm:flex-1">
        Reject
      </Button>
      <Button disabled={!canDecide} onClick={() => decide('Approved')} className="max-sm:flex-1">
        <Icon name="check" className="size-4" />
        Approve enrollment
      </Button>
    </div>
  )
}

export function EnrollmentsBody() {
  const { rows, selected, select, current, note } = useReview()
  const count = (s: string) => rows.filter((r) => r.status === s).length
  const pending = count('Pending')
  const hint = !current
    ? 'Select a pending enrollment to approve or reject it.'
    : current.status === 'Pending'
      ? `Selected: ${current.name}.`
      : `${current.name} is already ${current.status.toLowerCase()}, so there is nothing to decide.`

  return (
    <div className="flex flex-col gap-6">
      <SummaryStrip
        items={[
          { label: 'Needs review', value: pending, hint: 'pending', hue: pending ? 'amber' : undefined },
          { label: 'Approved', value: count('Approved'), hint: 'enrolled' },
          { label: 'Rejected', value: count('Rejected'), hint: 'sent back' },
        ]}
      />

      <Section title="Submitted enrollments">
        <QueueSheet
          toolbar={<StatusLine>{note || hint}</StatusLine>}
          footer={<p className="text-sm text-muted">{rows.length} {rows.length === 1 ? 'enrollment' : 'enrollments'} this term</p>}
        >
          <QueueTable minWidth="min-w-[680px]">
            <TableHeader>
              <tr>
                <TableHead className="w-12"><span className="sr-only">Select</span></TableHead>
                <TableHead>Student</TableHead>
                <TableHead>Program</TableHead>
                <TableHead>Subjects</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Submitted</TableHead>
              </tr>
            </TableHeader>
            <TableBody>
              {rows.length === 0 && <EmptyRow colSpan={6}>No enrollments submitted this term.</EmptyRow>}
              {rows.map((r) => (
                <TableRow key={r.id} className={cn(selected === r.id && 'bg-accent')}>
                  <TableCell className="w-12 px-1.5">
                    <RowRadio name="enrollment" checked={selected === r.id} onChange={() => select(r.id)} label={`Select ${r.name}`} />
                  </TableCell>
                  <TableCell><StudentCell name={r.name} sub={r.studentNo} /></TableCell>
                  <TableCell className="text-muted">{r.program}</TableCell>
                  <TableCell className="text-muted">{r.subjects} subjects</TableCell>
                  <TableCell><StatusBadge status={r.status} /></TableCell>
                  <TableCell className="whitespace-nowrap text-muted">{r.submitted}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </QueueTable>
        </QueueSheet>
      </Section>
    </div>
  )
}
