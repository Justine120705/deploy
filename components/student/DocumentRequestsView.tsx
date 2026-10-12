'use client'

import { useActionState } from 'react'
import { Button, Input, Section, Select, StatusBadge } from '@/components/ui'
import { requestDocument, type RequestDocumentState } from '@/lib/data/documents-actions'
import type { DocumentRequest, DocumentTypeOption } from '@/lib/data/documents'
import { formatShortDate } from './format'
import { ResponsiveTable, type Column } from './ResponsiveTable'
import { StatGrid } from './StatGrid'

const INITIAL: RequestDocumentState = { status: 'idle', message: '' }

// New-request form. Server action: the database makes the ticket number and sets the status to Pending.
// On success the action redirects back to the page with a notice, and the list below shows the request.
function NewRequestForm({ types }: { types: DocumentTypeOption[] }) {
  const [state, formAction, pending] = useActionState(requestDocument, INITIAL)
  const errors = state.fieldErrors ?? {}

  return (
    <form
      id="new-request"
      action={formAction}
      className="flex scroll-mt-4 flex-col gap-4 rounded-lg border border-edge bg-card p-4 lg:p-5"
    >
      <div className="grid gap-4 sm:grid-cols-[2fr_3fr_1fr]">
        <Select id="doc-type" name="documentTypeId" label="Document type" required error={errors.type}>
          {types.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </Select>
        <Input
          id="doc-purpose"
          name="purpose"
          label="Purpose"
          required
          maxLength={200}
          placeholder="e.g. Scholarship application"
          error={errors.purpose}
        />
        <Input
          id="doc-copies"
          name="copies"
          label="Copies"
          type="number"
          inputMode="numeric"
          min={1}
          max={10}
          step={1}
          defaultValue={1}
          required
          error={errors.copies}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={pending} aria-disabled={pending}>
          {pending ? 'Sending...' : 'Submit request'}
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

// Live: the student's own requests (RLS) and the form to file a new one. The Registrar changes the status.
export default function DocumentRequestsView({
  documentTypes,
  requests,
}: {
  documentTypes: DocumentTypeOption[]
  requests: DocumentRequest[]
}) {
  const count = (status: string) => requests.filter((r) => r.status === status).length

  const columns: Column<DocumentRequest>[] = [
    {
      key: 'document',
      header: 'Document',
      primary: true,
      cell: (r) => (
        <>
          {r.typeName}
          <span className="block text-sm font-normal text-muted">{r.ticketNumber}</span>
        </>
      ),
    },
    { key: 'purpose', header: 'Purpose', cell: (r) => r.purpose },
    { key: 'copies', header: 'Copies', className: 'w-20', cell: (r) => r.copies },
    { key: 'requested', header: 'Requested on', cell: (r) => formatShortDate(r.requestedAt) },
    { key: 'status', header: 'Status', badge: true, cell: (r) => <StatusBadge status={r.status} /> },
    { key: 'processed', header: 'Processed on', cell: (r) => formatShortDate(r.processedAt) },
    { key: 'remarks', header: 'Remarks', cell: (r) => r.remarks ?? '-' },
  ]

  return (
    <div className="flex flex-col gap-8">
      <StatGrid
        stats={[
          { label: 'Requests', value: requests.length, hint: 'all time' },
          { label: 'Pending', value: count('Pending'), hint: 'not yet processed', hue: count('Pending') > 0 ? 'amber' : undefined },
          { label: 'In progress', value: count('Processing') + count('Ready'), hint: 'with the Registrar', hue: count('Processing') + count('Ready') > 0 ? 'violet' : undefined },
          { label: 'Released', value: count('Released'), hint: 'collected', hue: count('Released') > 0 ? 'teal' : undefined },
        ]}
      />

      <Section title="Your requests" description="Students can only file requests. The Registrar updates the status.">
        <ResponsiveTable
          columns={columns}
          rows={requests}
          rowKey={(r) => r.id}
          caption="Your document requests"
          empty="No document requests yet. File one with the form below."
        />
      </Section>

      <Section title="New document request">
        {documentTypes.length === 0 ? (
          <p className="rounded-lg border border-dashed border-border px-4 py-6 text-sm text-muted">
            No document types are available yet. Check back later.
          </p>
        ) : (
          // Remounts after each new request so the fields and any old message are cleared.
          <NewRequestForm key={requests.length} types={documentTypes} />
        )}
      </Section>
    </div>
  )
}
