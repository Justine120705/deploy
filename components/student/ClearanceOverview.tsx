'use client'

import { useState } from 'react'
import { Button, StatusBadge } from '@/components/ui'
import type { ChainOffice } from './ClearanceChain'
import { ClearanceProgress } from './ClearanceProgress'
import { formatShortDate } from './format'
import RequestClearanceButton from './RequestClearanceButton'
import { ResponsiveTable, type Column } from './ResponsiveTable'
import { StatGrid } from './StatGrid'

export type ClearanceOfficeRow = {
  id: number
  name: string
  type: string
  status: 'Cleared' | 'Pending'
  clearedAt: string | null
  remarks: string | null
}

// UI only for now: "Request clearance" marks the office as requested in local state, no backend call.
export default function ClearanceOverview({
  offices,
  activeHolds,
}: {
  offices: ClearanceOfficeRow[]
  activeHolds: number
}) {
  const [requested, setRequested] = useState<number[]>([])

  const cleared = offices.filter((o) => o.status === 'Cleared').length
  const pending = offices.length - cleared
  const waiting = offices.filter((o) => o.status === 'Pending' && !requested.includes(o.id))

  const chain: ChainOffice[] = offices.map((o) => {
    if (o.status === 'Cleared') return { name: o.name, status: 'Cleared', reason: '', nextAction: '' }
    return {
      name: o.name,
      status: 'Pending',
      reason: o.remarks ?? 'Awaiting review',
      nextAction: requested.includes(o.id)
        ? `Requested. ${o.name} is reviewing.`
        : `Request clearance from ${o.name}.`,
    }
  })

  const columns: Column<ClearanceOfficeRow>[] = [
    { key: 'office', header: 'Office', primary: true, cell: (o) => o.name },
    { key: 'type', header: 'Type', cell: (o) => o.type },
    { key: 'status', header: 'Status', badge: true, cell: (o) => <StatusBadge status={o.status} className="text-sm" /> },
    { key: 'cleared', header: 'Cleared on', cell: (o) => formatShortDate(o.clearedAt) },
    { key: 'remarks', header: 'Remarks', cell: (o) => o.remarks ?? '-' },
    {
      key: 'action',
      header: 'Action',
      className: 'text-right',
      cell: (o) =>
        o.status === 'Pending' ? (
          <RequestClearanceButton
            department={o.name}
            requested={requested.includes(o.id)}
            onRequest={() => setRequested((prev) => [...prev, o.id])}
          />
        ) : (
          <span className="text-muted">None needed</span>
        ),
    },
  ]

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted">The Registrar gives final approval once every office has cleared.</p>
        <Button
          className="max-lg:h-11"
          disabled={waiting.length === 0}
          onClick={() => setRequested((prev) => [...prev, ...waiting.map((o) => o.id)])}
        >
          {pending > 0 && waiting.length === 0 ? 'All requested' : 'Request clearance'}
        </Button>
      </div>

      <StatGrid
        stats={[
          { label: 'Offices', value: offices.length, hint: 'in total' },
          { label: 'Cleared', value: cleared, hint: `of ${offices.length} offices`, hue: cleared > 0 ? 'teal' : undefined },
          { label: 'Pending', value: pending, hint: 'awaiting review', hue: pending > 0 ? 'amber' : undefined },
          {
            label: 'Active holds',
            value: activeHolds,
            hint: activeHolds > 0 ? 'academic holds' : 'no academic holds',
            hue: activeHolds > 0 ? 'rose' : undefined,
          },
        ]}
      />

      <ClearanceProgress offices={chain} activeHolds={activeHolds} />

      <ResponsiveTable
        columns={columns}
        rows={offices}
        rowKey={(o) => o.id}
        caption="Clearance by office"
        empty="No clearance items yet."
      />
    </div>
  )
}
