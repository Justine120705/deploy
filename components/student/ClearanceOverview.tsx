import { Section, StatusBadge, SummaryStrip } from '@/components/ui'
import { toOfficeSteps, type ActiveHold, type ClearanceItem } from '@/lib/data/clearance'
import { ClearanceRoute } from './ClearanceRoute'
import { formatShortDate } from './format'
import { ResponsiveTable, type Column } from './ResponsiveTable'

// Live clearance of the signed-in student: the route (where it stands and what is next), the counts,
// then the office table. The Registrar's final approval comes from the clearance itself.
export default function ClearanceOverview({
  offices,
  holds,
  approved,
  approvedAt,
}: {
  offices: ClearanceItem[]
  holds: ActiveHold[]
  approved: boolean
  approvedAt: string | null
}) {
  const activeHolds = holds.length
  const cleared = offices.filter((o) => o.status === 'Cleared').length
  const pending = offices.length - cleared

  const columns: Column<ClearanceItem>[] = [
    { key: 'office', header: 'Office', primary: true, cell: (o) => o.name },
    { key: 'type', header: 'Type', cell: (o) => o.type },
    { key: 'status', header: 'Status', badge: true, cell: (o) => <StatusBadge status={o.status} /> },
    { key: 'cleared', header: 'Cleared on', cell: (o) => formatShortDate(o.clearedAt) },
    { key: 'remarks', header: 'Remarks', cell: (o) => o.remarks ?? '-' },
  ]

  return (
    <div className="flex flex-col gap-8">
      <ClearanceRoute detail offices={toOfficeSteps(offices, holds)} activeHolds={activeHolds} approved={approved} />

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

      <Section
        title="Offices"
        description={
          approved
            ? `The Registrar approved your clearance${approvedAt ? ` on ${formatShortDate(approvedAt)}` : ''}.`
            : 'The Registrar gives final approval once every office has cleared you.'
        }
      >
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
