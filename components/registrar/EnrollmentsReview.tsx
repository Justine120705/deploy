'use client'

import { createContext, useContext, useState } from 'react'
import { Button, EmptyRow, StatusBadge, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { Icon } from '@/components/layout/Icon'
import { cn } from '@/lib/utils'
import { REGISTRAR_ENROLLMENTS, type EnrollmentRow } from '@/lib/mock/registrar-data'
import RowRadio from './RowRadio'
import StatGrid from './StatGrid'

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
      <Button variant="outline" disabled={!canDecide} onClick={() => decide('Rejected')} className="max-lg:h-11 max-sm:flex-1">
        Reject
      </Button>
      <Button disabled={!canDecide} onClick={() => decide('Approved')} className="gap-2 max-lg:h-11 max-sm:flex-1">
        <Icon name="check" className="size-4" />
        Approve enrollment
      </Button>
    </div>
  )
}

export function EnrollmentsBody() {
  const { rows, selected, select, current, note } = useReview()
  const count = (s: string) => rows.filter((r) => r.status === s).length
  const hint = !current
    ? 'Select a pending enrollment to approve or reject it.'
    : current.status === 'Pending'
      ? `Selected: ${current.name}.`
      : `${current.name} is already ${current.status.toLowerCase()}, so there is nothing to decide.`

  return (
    <div className="flex flex-col gap-4">
      <StatGrid
        items={[
          { label: 'Submitted', value: rows.length, hint: 'this term' },
          { label: 'Approved', value: count('Approved'), hint: 'enrolled', hue: count('Approved') ? 'teal' : undefined },
          { label: 'Pending', value: count('Pending'), hint: 'needs review', hue: count('Pending') ? 'amber' : undefined },
          { label: 'Current term', value: '1st Sem', hint: '2026-2027' },
        ]}
      />
      <p aria-live="polite" className="px-1 text-sm text-muted">
        {note || hint}
      </p>
      <div>
        <Table className="min-w-[720px]">
          <TableHeader>
            <tr>
              <TableHead className="w-12"><span className="sr-only">Select</span></TableHead>
              <TableHead>Student no.</TableHead>
              <TableHead>Student name</TableHead>
              <TableHead>Program</TableHead>
              <TableHead>Subjects</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Submitted on</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && <EmptyRow colSpan={7}>No enrollments submitted this term.</EmptyRow>}
            {rows.map((r) => (
              <TableRow key={r.id} className={cn(selected === r.id && 'bg-accent/60')}>
                <TableCell className="w-12 px-1.5">
                  <RowRadio name="enrollment" checked={selected === r.id} onChange={() => select(r.id)} label={`Select ${r.name}`} />
                </TableCell>
                <TableCell className="font-normal text-muted">{r.studentNo}</TableCell>
                <TableCell className="font-semibold">{r.name}</TableCell>
                <TableCell className="font-normal text-muted">{r.program}</TableCell>
                <TableCell className="font-normal text-muted">{r.subjects} subjects</TableCell>
                <TableCell><StatusBadge status={r.status} /></TableCell>
                <TableCell className="font-normal text-muted">{r.submitted}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <p className="px-1 pt-3 text-sm text-muted">
          Showing {rows.length} of {rows.length} enrollments
        </p>
      </div>
    </div>
  )
}
