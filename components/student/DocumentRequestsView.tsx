'use client'

import { useState } from 'react'
import {
  Button,
  Card,
  CardHeader,
  Input,
  Select,
  StatusBadge,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'

export type DocumentRequestRecord = {
  id: number
  ticket_number: string
  document_type_id: number
  purpose: string
  copies: number
  requested_at: string
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
        status: 'Pending',
      },
      ...prev,
    ])
    setPurpose('')
    setCopies('1')
  }

  return (
    <div className="flex flex-col gap-6">
      <Card className="p-5">
        <CardHeader title="New document request" />
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
            <Button type="submit">Submit request</Button>
          </div>
        </form>
      </Card>

      <div className="flex flex-col gap-3">
        <h2 className="text-base font-bold">Your requests</h2>
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead>Ticket</TableHead>
              <TableHead>Document</TableHead>
              <TableHead>Purpose</TableHead>
              <TableHead>Copies</TableHead>
              <TableHead>Requested</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {requests.length === 0 && (
              <TableRow className="hover:bg-transparent">
                <TableCell colSpan={6} className="text-muted">
                  No document requests yet.
                </TableCell>
              </TableRow>
            )}
            {requests.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-semibold">{r.ticket_number}</TableCell>
                <TableCell>{typeName(r.document_type_id)}</TableCell>
                <TableCell>{r.purpose}</TableCell>
                <TableCell>{r.copies}</TableCell>
                <TableCell>{r.requested_at.slice(0, 10)}</TableCell>
                <TableCell>
                  <StatusBadge status={r.status} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
