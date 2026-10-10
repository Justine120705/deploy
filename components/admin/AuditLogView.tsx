'use client'

import { useId, useMemo, useState } from 'react'
import TableCard from '@/components/admin/TableCard'
import { Icon } from '@/components/layout/Icon'
import {
  Badge,
  Button,
  Card,
  EmptyRow,
  HUE_TEXT,
  Input,
  Select,
  StatCard,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import type { AuditRow } from '@/lib/mock/admin-data'

const ACTION_TONE = { Insert: 'success', Update: 'warning', Delete: 'danger' } as const

// Spreadsheet programs run text that starts with these characters as a formula.
function csvCell(value: string) {
  const safe = /^[=+\-@\t\r]/.test(value) ? `'${value}` : value
  return `"${safe.replace(/"/g, '""')}"`
}

// Read-only view of the append-only audit log: no edit or delete controls exist here.
export default function AuditLogView({ rows }: { rows: AuditRow[] }) {
  const uid = useId()
  const [action, setAction] = useState('')
  const [query, setQuery] = useState('')

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    return rows.filter(
      (r) =>
        (!action || r.action === action) &&
        (!q ||
          [r.actor, r.table, r.record, r.details].some((v) => v.toLowerCase().includes(q)))
    )
  }, [rows, action, query])

  const count = (a: string) => rows.filter((r) => r.action === a).length

  function exportCsv() {
    const head = ['Time', 'Actor', 'Action', 'Table', 'Record', 'Details']
    const lines = [head, ...visible.map((r) => [r.when, r.actor, r.action, r.table, r.record, r.details])]
    const csv = lines.map((l) => l.map(csvCell).join(',')).join('\r\n')
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = 'audit-log.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Entries" value={rows.length} hint="recorded so far" />
        <StatCard label="Inserts" value={<span className={HUE_TEXT.teal}>{count('Insert')}</span>} hint="new records" />
        <StatCard label="Updates" value={<span className={HUE_TEXT.amber}>{count('Update')}</span>} hint="changes" />
        <StatCard label="Deletes" value={count('Delete')} hint="records" />
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <div className="min-w-[200px] flex-1">
          <Input
            id={`${uid}-search`}
            label="Search entries"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="w-full sm:w-48">
          <Select id={`${uid}-action`} label="Action" value={action} onChange={(e) => setAction(e.target.value)}>
            <option value="">All actions</option>
            <option value="Insert">Insert</option>
            <option value="Update">Update</option>
            <option value="Delete">Delete</option>
          </Select>
        </div>
        <Button onClick={exportCsv} className="max-lg:h-11 max-sm:w-full" disabled={visible.length === 0}>
          <Icon name="check" className="mr-2 size-4" />
          Export CSV
        </Button>
      </div>

      {/* Phone: one card per entry. */}
      <ul className="flex flex-col gap-3 md:hidden">
        {visible.length === 0 && (
          <li>
            <Card className="p-5 text-center text-sm font-medium text-muted">No entries match.</Card>
          </li>
        )}
        {visible.map((r) => (
          <li key={r.id}>
            <Card className="flex flex-col gap-2 p-4">
              <div className="flex items-start justify-between gap-2">
                <p className="font-bold">{r.actor}</p>
                <Badge tone={ACTION_TONE[r.action]}>{r.action}</Badge>
              </div>
              <p className="text-sm text-muted">{r.when}</p>
              <p className="text-sm">
                <span className="text-muted">Table:</span> {r.table}
              </p>
              <p className="text-sm">
                <span className="text-muted">Record:</span> {r.record}
              </p>
              <p className="text-sm">
                <span className="text-muted">Details:</span> {r.details}
              </p>
            </Card>
          </li>
        ))}
      </ul>

      <div className="max-md:hidden">
        <TableCard
          minWidth="min-w-[860px]"
          footer={`Showing ${visible.length} of ${rows.length} entries. The log cannot be edited or deleted.`}
        >
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead scope="col">Time</TableHead>
              <TableHead scope="col">Actor</TableHead>
              <TableHead scope="col">Action</TableHead>
              <TableHead scope="col">Table</TableHead>
              <TableHead scope="col">Record</TableHead>
              <TableHead scope="col">Details</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.length === 0 && <EmptyRow colSpan={6}>No entries match.</EmptyRow>}
            {visible.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="whitespace-nowrap font-normal text-muted">{r.when}</TableCell>
                <TableCell>{r.actor}</TableCell>
                <TableCell>
                  <Badge tone={ACTION_TONE[r.action]}>{r.action}</Badge>
                </TableCell>
                <TableCell className="font-normal text-muted">{r.table}</TableCell>
                <TableCell className="font-normal text-muted">{r.record}</TableCell>
                <TableCell className="font-normal text-muted">{r.details}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>
      </div>
    </div>
  )
}
