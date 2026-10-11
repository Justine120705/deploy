import { Icon } from '@/components/layout/Icon'
import { StatusBadge } from '@/components/ui'
import { cn } from '@/lib/utils'

export type OfficeRow = { name: string; note: string; status: 'Cleared' | 'Pending' }

// One row per clearance office: round status icon, name and note, status pill.
export function ClearanceOfficesList({ offices }: { offices: readonly OfficeRow[] }) {
  if (offices.length === 0) {
    return <p className="px-[18px] py-2 text-sm text-muted">No clearance items yet.</p>
  }
  return (
    <ul>
      {offices.map((o) => {
        const cleared = o.status === 'Cleared'
        return (
          <li key={o.name} className="flex items-center gap-3 px-[18px] py-2">
            <span
              className={cn(
                'flex size-[34px] shrink-0 items-center justify-center rounded-full',
                cleared ? 'bg-success-soft text-success' : 'bg-warning-soft text-warning'
              )}
            >
              <Icon name={cleared ? 'check' : 'clock'} className="size-4" />
            </span>
            <span className="flex min-w-0 flex-1 flex-col text-sm">
              <span className="truncate font-bold">{o.name}</span>
              <span className="text-muted">{o.note}</span>
            </span>
            <StatusBadge status={o.status} className="text-sm" />
          </li>
        )
      })}
    </ul>
  )
}
