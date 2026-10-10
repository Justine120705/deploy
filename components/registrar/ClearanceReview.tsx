'use client'

import { createContext, useContext, useState } from 'react'
import { Button, EmptyRow, StatusBadge, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { Icon } from '@/components/layout/Icon'
import { cn } from '@/lib/utils'
import { REGISTRAR_CLEARANCES, type ClearanceRow } from '@/lib/mock/registrar-data'
import RowRadio from './RowRadio'
import StatGrid from './StatGrid'

const isReady = (r: ClearanceRow) => r.status === 'Pending' && r.cleared === r.total && r.holds === 0

type Ctx = {
  rows: ClearanceRow[]
  selected: string | null
  select: (id: string) => void
  issue: () => void
  current: ClearanceRow | undefined
  note: string
}

const Context = createContext<Ctx | null>(null)

function useClearance() {
  const ctx = useContext(Context)
  if (!ctx) throw new Error('ClearanceReview parts must be inside ClearanceProvider')
  return ctx
}

export function ClearanceProvider({ children }: { children: React.ReactNode }) {
  const [rows, setRows] = useState(REGISTRAR_CLEARANCES)
  const [selected, setSelected] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const current = rows.find((r) => r.id === selected)

  function issue() {
    if (!current || !isReady(current)) return
    setRows((rs) => rs.map((r) => (r.id === current.id ? { ...r, status: 'Approved' } : r)))
    setNote(`Final clearance issued for ${current.name}. This is a preview and is not saved.`)
    setSelected(null)
  }

  return (
    <Context.Provider value={{ rows, selected, select: setSelected, issue, current, note }}>
      {children}
    </Context.Provider>
  )
}

export function ClearanceActions() {
  const { current, issue } = useClearance()
  return (
    <Button disabled={!current || !isReady(current)} onClick={issue} className="gap-2 max-lg:h-11 max-sm:w-full">
      <Icon name="check" className="size-4" />
      Issue final clearance
    </Button>
  )
}

export function ClearanceBody() {
  const { rows, selected, select, current, note } = useClearance()
  const ready = rows.filter(isReady).length
  const waiting = rows.filter((r) => r.status === 'Pending' && !isReady(r)).length
  const approved = rows.filter((r) => r.status === 'Approved').length

  let hint = 'Select a student to check whether final clearance can be issued.'
  if (current) {
    if (current.status === 'Approved') hint = `${current.name} already has final clearance.`
    else if (current.holds > 0) hint = `${current.name} has ${current.holds} active hold. Final clearance stays locked until it is lifted.`
    else if (current.cleared < current.total) hint = `${current.name} has cleared ${current.cleared} of ${current.total} offices. Final clearance stays locked until every office has cleared.`
    else hint = `${current.name} has cleared every office. Final clearance can be issued.`
  }

  return (
    <div className="flex flex-col gap-4">
      <StatGrid
        items={[
          { label: 'Requested', value: rows.length, hint: 'this term' },
          { label: 'Ready', value: ready, hint: 'for final approval', hue: ready ? 'teal' : undefined },
          { label: 'Waiting', value: waiting, hint: 'offices pending', hue: waiting ? 'amber' : undefined },
          { label: 'Approved', value: approved, hint: 'so far' },
        ]}
      />
      <p aria-live="polite" className="px-1 text-sm text-muted">
        {note || hint}
      </p>
      <div>
        <Table className="min-w-[760px]">
          <TableHeader>
            <tr>
              <TableHead className="w-12"><span className="sr-only">Select</span></TableHead>
              <TableHead>Student no.</TableHead>
              <TableHead>Student name</TableHead>
              <TableHead>Offices cleared</TableHead>
              <TableHead>Active holds</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Requested</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && <EmptyRow colSpan={7}>No clearance requests this term.</EmptyRow>}
            {rows.map((r) => (
              <TableRow key={r.id} className={cn(selected === r.id && 'bg-accent/60')}>
                <TableCell className="w-12 px-1.5">
                  <RowRadio name="clearance" checked={selected === r.id} onChange={() => select(r.id)} label={`Select ${r.name}`} />
                </TableCell>
                <TableCell className="font-normal text-muted">{r.studentNo}</TableCell>
                <TableCell className="font-semibold">{r.name}</TableCell>
                <TableCell className="font-normal text-muted">{r.cleared} of {r.total}</TableCell>
                <TableCell className="font-normal text-muted">{r.holds}</TableCell>
                <TableCell><StatusBadge status={r.status} /></TableCell>
                <TableCell className="font-normal text-muted">{r.requested}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <p className="px-1 pt-3 text-sm text-muted">
          Final approval unlocks only when every item, including Finance, is cleared.
        </p>
      </div>
    </div>
  )
}
