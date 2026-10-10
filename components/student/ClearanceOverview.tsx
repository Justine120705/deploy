'use client'

import { useState } from 'react'
import { Button, Section, StatusBadge, SummaryStrip } from '@/components/ui'
import { ClearanceRoute, type RouteOffice } from './ClearanceRoute'
import { formatShortDate } from './format'
import RequestClearanceButton from './RequestClearanceButton'
import { ResponsiveTable, type Column } from './ResponsiveTable'

export type ClearanceOfficeRow = {
  id: number
  name: string
  type: string
  status: 'Cleared' | 'Pending'
  clearedAt: string | null
  remarks: string | null
}

// UI only for now: "Request clearance" marks the office as requested in local state, no backend call.
// Order: the route (where it stands and what is next, with the one primary action), the counts, then
// the office table with a per-office request button.
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

  const route: RouteOffice[] = offices.map((o) => {
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
    { key: 'status', header: 'Status', badge: true, cell: (o) => <StatusBadge status={o.status} /> },
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
    <div className="flex flex-col gap-8">
      <ClearanceRoute
        detail
        offices={route}
        activeHolds={activeHolds}
        action={
          <Button
            disabled={waiting.length === 0}
            onClick={() => setRequested((prev) => [...prev, ...waiting.map((o) => o.id)])}
          >
            {pending > 0 && waiting.length === 0 ? 'All requested' : 'Request clearance'}
          </Button>
        }
      />

      <SummaryStrip
        items={[
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

      <Section title="Offices" description="The Registrar gives final approval once every office has cleared you.">
        <ResponsiveTable
          columns={columns}
          rows={offices}
          rowKey={(o) => o.id}
          caption="Clearance by office"
          empty="No clearance items yet."
        />
      </Section>
    </div>
  )
}
