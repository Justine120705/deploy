'use client'

import { useActionState, useState } from 'react'
import { Button, EmptyRow, Section, Select, StatusBadge, SummaryStrip, TableBody, TableCell, TableHead, TableHeader, TableRow, Textarea } from '@/components/ui'
import { cn } from '@/lib/utils'
import { formatShortDate } from '@/components/student/format'
import { updateDocumentStatus, type UpdateDocumentState } from '@/lib/data/documents-actions'
import type { DocumentStatus, RegistrarDocumentRequest } from '@/lib/data/documents'
import RowRadio from './RowRadio'
import { QueueSheet, QueueTable, StatusLine, StudentCell } from './QueueParts'

// Legal next steps per status (same flow the database trigger enforces). Kept here, not imported from
// lib/data/documents, because that file reads the database and must stay out of the browser bundle.
const STEPS: Record<DocumentStatus, readonly { to: DocumentStatus; label: string; danger?: boolean }[]> = {
  Pending: [
    { to: 'Processing', label: 'Start processing' },
    { to: 'Rejected', label: 'Reject', danger: true },
  ],
  Processing: [
    { to: 'Ready', label: 'Mark as ready' },
    { to: 'Rejected', label: 'Reject', danger: true },
  ],
  Ready: [{ to: 'Released', label: 'Mark as released' }],
  Released: [],
  Rejected: [],
}

const FILTERS: readonly (DocumentStatus | 'All')[] = ['All', 'Pending', 'Processing', 'Ready', 'Released', 'Rejected']
const INITIAL: UpdateDocumentState = { status: 'idle', message: '' }

// The panel for one selected request: optional remarks and only the legal next actions. Remarks go
// together with the status change (the database refuses remark edits while a request is Pending).
function ProcessPanel({ request }: { request: RegistrarDocumentRequest }) {
  const [state, formAction, pending] = useActionState(updateDocumentStatus, INITIAL)
  const steps = STEPS[request.status]

  return (
    <form action={formAction} className="flex flex-col gap-4 rounded-lg border border-edge bg-card p-4 lg:p-5">
      <input type="hidden" name="requestId" value={request.id} />
      <input type="hidden" name="from" value={request.status} />
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold">
            {request.ticketNumber} · {request.typeName}
          </p>
          <p className="text-sm text-muted">
            {request.studentName}
            {request.studentNo && ` (${request.studentNo})`} · {request.copies} {request.copies === 1 ? 'copy' : 'copies'}
          </p>
          <p className="mt-1 text-sm">Purpose: {request.purpose}</p>
        </div>
        <StatusBadge status={request.status} />
      </div>
      {request.remarks && <p className="text-sm text-muted">Current remarks: {request.remarks}</p>}
      {steps.length === 0 ? (
        <p className="text-sm text-muted">
          This request is {request.status.toLowerCase()}, so there is no next step.
        </p>
      ) : (
        <>
          <Textarea
            key={request.status}
            id={`remarks-${request.id}`}
            name="remarks"
            label="Remarks (optional, required to reject)"
            rows={2}
            maxLength={300}
            placeholder="e.g. Please claim it at the Registrar window"
          />
          <div className="flex flex-wrap gap-2">
            {steps.map((s) => (
              <Button
                key={s.to}
                type="submit"
                name="status"
                value={s.to}
                variant={s.danger ? 'danger' : 'primary'}
                disabled={pending}
                aria-disabled={pending}
                className="max-sm:w-full"
              >
                {s.label}
              </Button>
            ))}
          </div>
        </>
      )}
      <p
        role="status"
        aria-live="polite"
        className={state.status === 'error' ? 'text-sm font-medium text-danger' : 'text-sm text-muted'}
      >
        {state.message}
      </p>
    </form>
  )
}

export default function DocumentsQueue({ requests }: { requests: RegistrarDocumentRequest[] }) {
  const [filter, setFilter] = useState<DocumentStatus | 'All'>('All')
  const [selectedId, setSelectedId] = useState<number | null>(null)

  const count = (s: DocumentStatus) => requests.filter((r) => r.status === s).length
  const shown = filter === 'All' ? requests : requests.filter((r) => r.status === filter)
  const current = requests.find((r) => r.id === selectedId)

  return (
    <div className="flex flex-col gap-6">
      <SummaryStrip
        items={[
          { label: 'Pending', value: count('Pending'), hint: 'new requests', hue: count('Pending') ? 'amber' : undefined },
          { label: 'Processing', value: count('Processing'), hint: 'in progress' },
          { label: 'Ready', value: count('Ready'), hint: 'for release', hue: count('Ready') ? 'teal' : undefined },
          { label: 'Released', value: count('Released'), hint: 'handed over' },
        ]}
      />

      <Section title="Requests">
        <QueueSheet
          toolbar={
            <>
              <div className="w-44 max-sm:w-full">
                <Select
                  id="doc-filter"
                  label="Show"
                  value={filter}
                  onChange={(e) => setFilter(e.target.value as DocumentStatus | 'All')}
                >
                  {FILTERS.map((f) => (
                    <option key={f} value={f}>
                      {f === 'All' ? 'All statuses' : f}
                    </option>
                  ))}
                </Select>
              </div>
              <StatusLine>
                {current ? `Selected: ${current.ticketNumber}, ${current.studentName}.` : 'Select a request to process it.'}
              </StatusLine>
            </>
          }
          footer={
            <p className="text-sm text-muted">
              {shown.length} {shown.length === 1 ? 'request' : 'requests'}
              {filter !== 'All' && ` · ${filter}`}
            </p>
          }
        >
          <QueueTable minWidth="min-w-[880px]">
            <TableHeader>
              <tr>
                <TableHead className="w-12"><span className="sr-only">Select</span></TableHead>
                <TableHead>Ticket</TableHead>
                <TableHead>Student</TableHead>
                <TableHead>Document</TableHead>
                <TableHead>Copies</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Requested</TableHead>
                <TableHead>Processed</TableHead>
              </tr>
            </TableHeader>
            <TableBody>
              {shown.length === 0 && (
                <EmptyRow colSpan={8}>
                  {requests.length === 0 ? 'No document requests yet.' : `No ${filter.toLowerCase()} requests.`}
                </EmptyRow>
              )}
              {shown.map((r) => (
                <TableRow key={r.id} className={cn(selectedId === r.id && 'bg-accent')}>
                  <TableCell className="w-12 px-1.5">
                    <RowRadio
                      name="document"
                      checked={selectedId === r.id}
                      onChange={() => setSelectedId(r.id)}
                      label={`Select ${r.ticketNumber}, ${r.studentName}`}
                    />
                  </TableCell>
                  <TableCell className="whitespace-nowrap text-muted">{r.ticketNumber}</TableCell>
                  <TableCell><StudentCell name={r.studentName} sub={r.studentNo} /></TableCell>
                  <TableCell>{r.typeName}</TableCell>
                  <TableCell className="text-muted">{r.copies}</TableCell>
                  <TableCell><StatusBadge status={r.status} /></TableCell>
                  <TableCell className="whitespace-nowrap text-muted">{formatShortDate(r.requestedAt)}</TableCell>
                  <TableCell className="text-muted">
                    {r.processedAt ? (
                      <>
                        <span className="block whitespace-nowrap">{formatShortDate(r.processedAt)}</span>
                        {r.processedByName && <span className="block text-xs">{r.processedByName}</span>}
                      </>
                    ) : (
                      '-'
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </QueueTable>
        </QueueSheet>
      </Section>

      {current && (
        <Section title="Process request">
          {/* key: a new selection starts a fresh form and message. */}
          <ProcessPanel key={current.id} request={current} />
        </Section>
      )}
    </div>
  )
}
