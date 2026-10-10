'use client'

import { createContext, useContext, useState } from 'react'
import { Button, EmptyRow, StatusBadge, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { Icon } from '@/components/layout/Icon'
import { cn } from '@/lib/utils'
import { REGISTRAR_DOCUMENTS, type DocumentRow, type DocumentStatus } from '@/lib/mock/registrar-data'
import RowRadio from './RowRadio'
import StatGrid from './StatGrid'

// What the main button does for each status: [next status, button label].
const NEXT: Partial<Record<DocumentStatus, [DocumentStatus, string]>> = {
  Pending: ['Processing', 'Start processing'],
  Processing: ['Ready', 'Mark as ready'],
  Ready: ['Released', 'Mark as released'],
}

type Ctx = {
  rows: DocumentRow[]
  selected: string | null
  select: (id: string) => void
  advance: () => void
  current: DocumentRow | undefined
  note: string
}

const Context = createContext<Ctx | null>(null)

function useQueue() {
  const ctx = useContext(Context)
  if (!ctx) throw new Error('DocumentsQueue parts must be inside DocumentsProvider')
  return ctx
}

export function DocumentsProvider({ children }: { children: React.ReactNode }) {
  const [rows, setRows] = useState(REGISTRAR_DOCUMENTS)
  const [selected, setSelected] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const current = rows.find((r) => r.id === selected)

  function advance() {
    const step = current && NEXT[current.status]
    if (!current || !step) return
    setRows((rs) => rs.map((r) => (r.id === current.id ? { ...r, status: step[0] } : r)))
    setNote(`${current.ticket} is now ${step[0].toLowerCase()}. This is a preview and is not saved.`)
  }

  return (
    <Context.Provider value={{ rows, selected, select: setSelected, advance, current, note }}>
      {children}
    </Context.Provider>
  )
}

export function DocumentsActions() {
  const { current, advance } = useQueue()
  const step = current && NEXT[current.status]
  return (
    <Button disabled={!step} onClick={advance} className="gap-2 max-lg:h-11 max-sm:w-full">
      <Icon name="check" className="size-4" />
      {step ? step[1] : 'Mark as ready'}
    </Button>
  )
}

export function DocumentsBody() {
  const { rows, selected, select, current, note } = useQueue()
  const count = (s: string) => rows.filter((r) => r.status === s).length
  const hint = !current
    ? 'Select a request to move it to the next step.'
    : NEXT[current.status]
      ? `Selected: ${current.ticket}, ${current.name}.`
      : `${current.ticket} is already released, so there is no next step.`

  return (
    <div className="flex flex-col gap-4">
      <StatGrid
        items={[
          { label: 'Pending', value: count('Pending'), hint: 'new requests', hue: count('Pending') ? 'amber' : undefined },
          { label: 'Processing', value: count('Processing'), hint: 'in progress' },
          { label: 'Ready', value: count('Ready'), hint: 'for release', hue: count('Ready') ? 'teal' : undefined },
          { label: 'Released', value: count('Released'), hint: 'this term' },
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
              <TableHead>Ticket</TableHead>
              <TableHead>Student</TableHead>
              <TableHead>Document</TableHead>
              <TableHead>Copies</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Requested</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && <EmptyRow colSpan={7}>No document requests yet.</EmptyRow>}
            {rows.map((r) => (
              <TableRow key={r.id} className={cn(selected === r.id && 'bg-accent/60')}>
                <TableCell className="w-12 px-1.5">
                  <RowRadio name="document" checked={selected === r.id} onChange={() => select(r.id)} label={`Select ${r.ticket}, ${r.name}`} />
                </TableCell>
                <TableCell className="font-normal text-muted">{r.ticket}</TableCell>
                <TableCell className="font-semibold">{r.name}</TableCell>
                <TableCell className="font-normal text-muted">{r.document}</TableCell>
                <TableCell className="font-normal text-muted">{r.copies}</TableCell>
                <TableCell><StatusBadge status={r.status} /></TableCell>
                <TableCell className="font-normal text-muted">{r.requested}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <p className="px-1 pt-3 text-sm text-muted">
          Showing {rows.length} of {rows.length} requests
        </p>
      </div>
    </div>
  )
}
