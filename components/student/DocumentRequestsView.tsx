'use client'

import { useState } from 'react'
import { Button, Card, CardHeader, Input, Select, StatusBadge } from '@/components/ui'
import { formatShortDate } from './format'
import { ResponsiveTable, type Column } from './ResponsiveTable'
import { StatGrid } from './StatGrid'

export type DocumentRequestRecord = {
  id: number
  ticket_number: string
  document_type_id: number
  purpose: string
  copies: number
  requested_at: string
  /** When the Registrar processed it; empty until then. */
  processed_at?: string | null
  status: string
}

export type DocumentTypeOption = { document_type_id: number; name: string }

function nextTicket(requests: DocumentRequestRecord[]) {
  const year = new Date().getFullYear()
  const used = requests.map((r) => Number(r.ticket_number.split('-')[2]) || 0)
  return `DOC-${year}-${String(Math.max(0, ...used) + 1).padStart(4, '0')}`
}

// UI only for now: submitting adds a Pending request to local state, no backend call.
export default function DocumentRequestsView({
  documentTypes,
  initialRequests,
}: {
  documentTypes: DocumentTypeOption[]
  initialRequests: DocumentRequestRecord[]
}) {
  const [requests, setRequests] = useState(initialRequests)
  const [typeId, setTypeId] = useState(documentTypes[0]?.document_type_id ?? 0)
  const [purpose, setPurpose] = useState('')
  const [copies, setCopies] = useState('1')
  const [errors, setErrors] = useState<{ purpose?: string; copies?: string }>({})

  const typeName = (id: number) => documentTypes.find((t) => t.document_type_id === id)?.name ?? ''

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const n = Number(copies)
    const next: { purpose?: string; copies?: string } = {}
    if (!purpose.trim()) next.purpose = 'Enter the purpose of the request.'
    if (!Number.isInteger(n) || n < 1 || n > 10) next.copies = 'Copies must be from 1 to 10.'
    setErrors(next)
    if (next.purpose || next.copies) return

    setRequests((prev) => [
      {
        id: Math.max(0, ...prev.map((r) => r.id)) + 1,
        ticket_number: nextTicket(prev),
        document_type_id: typeId,
        purpose: purpose.trim(),
        copies: n,
        requested_at: new Date().toISOString(),
        processed_at: null,
        status: 'Pending',
      },
      ...prev,
    ])
    setPurpose('')
    setCopies('1')
  }

  const count = (status: string) => requests.filter((r) => r.status === status).length

  const columns: Column<DocumentRequestRecord>[] = [
    {
      key: 'document',
      header: 'Document',
      primary: true,
      cell: (r) => (
        <>
          {typeName(r.document_type_id)}
          <span className="block text-sm font-medium text-muted">{r.ticket_number}</span>
        </>
      ),
    },
    { key: 'purpose', header: 'Purpose', cell: (r) => r.purpose },
    { key: 'copies', header: 'Copies', className: 'w-20', cell: (r) => r.copies },
    { key: 'requested', header: 'Requested on', cell: (r) => formatShortDate(r.requested_at) },
    { key: 'status', header: 'Status', badge: true, cell: (r) => <StatusBadge status={r.status} className="text-sm" /> },
    { key: 'processed', header: 'Processed on', cell: (r) => formatShortDate(r.processed_at) },
  ]

  return (
    <div className="flex flex-col gap-4">
      <StatGrid
        stats={[
          { label: 'Requests', value: requests.length, hint: 'all time' },
          { label: 'Pending', value: count('Pending'), hint: 'not yet processed', hue: count('Pending') > 0 ? 'amber' : undefined },
          { label: 'Processing', value: count('Processing'), hint: 'with the Registrar', hue: count('Processing') > 0 ? 'violet' : undefined },
          { label: 'Released', value: count('Released'), hint: 'collected', hue: count('Released') > 0 ? 'teal' : undefined },
        ]}
      />

      <ResponsiveTable
        columns={columns}
        rows={requests}
        rowKey={(r) => r.id}
        caption="Your document requests"
        empty="No document requests yet."
        footer="Students can only file requests. The Registrar updates the status."
      />

      <Card className="scroll-mt-4 p-5" id="new-request">
        <CardHeader title="New document request" icon="documents" hue="violet" />
        <form onSubmit={handleSubmit} noValidate className="mt-4 flex flex-col gap-4">
          <div className="grid gap-4 sm:grid-cols-[2fr_3fr_1fr]">
            <Select
              id="doc-type"
              label="Document type"
              value={typeId}
              onChange={(e) => setTypeId(Number(e.target.value))}
            >
              {documentTypes.map((t) => (
                <option key={t.document_type_id} value={t.document_type_id}>
                  {t.name}
                </option>
              ))}
            </Select>
            <Input
              id="doc-purpose"
              label="Purpose"
              value={purpose}
              onChange={(e) => setPurpose(e.target.value)}
              placeholder="e.g. Scholarship application"
              error={errors.purpose}
            />
            <Input
              id="doc-copies"
              label="Copies"
              type="number"
              min={1}
              max={10}
              value={copies}
              onChange={(e) => setCopies(e.target.value)}
              error={errors.copies}
            />
          </div>
          <div>
            <Button type="submit" className="max-lg:h-11">
              Submit request
            </Button>
          </div>
        </form>
      </Card>
    </div>
  )
}
