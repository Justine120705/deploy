import { cn } from '@/lib/utils'

export type RecordField = { label: string; value: React.ReactNode }

export type RecordItem = {
  key: string
  title: string
  subtitle?: string
  badge?: React.ReactNode
  fields: RecordField[]
  footer?: React.ReactNode
}

const SHEET = 'overflow-hidden rounded-lg border border-edge bg-card'

// Phone version of a table: one hairline sheet, rows separated by rules, labelled fields per row.
// Pair it with a `hidden md:block` table and give this list `md:hidden`.
export function RecordList({ items, empty, className }: { items: RecordItem[]; empty: string; className?: string }) {
  if (items.length === 0) {
    return <p className={cn(SHEET, 'px-4 py-8 text-center text-sm text-muted', className)}>{empty}</p>
  }
  return (
    <ul className={cn(SHEET, 'divide-y divide-border-subtle', className)}>
      {items.map((item) => (
        <li key={item.key} className="flex flex-col gap-3 px-4 py-4">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="text-sm font-semibold">{item.title}</p>
              {item.subtitle && <p className="text-sm text-muted">{item.subtitle}</p>}
            </div>
            {item.badge}
          </div>
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            {item.fields.map((f) => (
              <div key={f.label} className="min-w-0">
                <dt className="text-xs font-medium text-muted">{f.label}</dt>
                <dd>{f.value}</dd>
              </div>
            ))}
          </dl>
          {item.footer}
        </li>
      ))}
    </ul>
  )
}
