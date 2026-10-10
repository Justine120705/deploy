import { Card, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { cn } from '@/lib/utils'

export type Column<T> = {
  key: string
  header: string
  cell: (row: T) => React.ReactNode
  className?: string
  /** Phone card: shown as the bold title of the card. Use for exactly one column. */
  primary?: boolean
  /** Phone card: shown top right, next to the title (for a status badge). */
  badge?: boolean
}

// A table from md up; on phones each row becomes a card with the same cells as label/value pairs, so
// nothing needs sideways scrolling. Server-safe: pass it plain data and cell render functions from a
// server file, or use it inside a client component.
export function ResponsiveTable<T>({
  columns,
  rows,
  rowKey,
  caption,
  empty,
  footer,
  className,
}: {
  columns: readonly Column<T>[]
  rows: readonly T[]
  rowKey: (row: T) => string | number
  caption: string
  empty: string
  footer?: React.ReactNode
  className?: string
}) {
  const primary = columns.find((c) => c.primary)
  const badge = columns.find((c) => c.badge)
  const rest = columns.filter((c) => c !== primary && c !== badge)

  return (
    <Card className={cn('overflow-hidden', className)}>
      {rows.length === 0 ? (
        <p className="px-5 py-8 text-center text-sm font-medium text-muted">{empty}</p>
      ) : (
        <>
          <table className="hidden w-full text-left text-sm md:table">
            <caption className="sr-only">{caption}</caption>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                {columns.map((c) => (
                  <TableHead key={c.key} scope="col" className={cn('px-4 text-sm', c.className)}>
                    {c.header}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={rowKey(r)}>
                  {columns.map((c, i) => (
                    <TableCell key={c.key} className={cn('px-4', i === 0 ? 'font-semibold' : 'font-normal', c.className)}>
                      {c.cell(r)}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </table>

          <ul aria-label={caption} className="divide-y divide-border-subtle md:hidden">
            {rows.map((r) => (
              <li key={rowKey(r)} className="flex flex-col gap-3 px-4 py-4 text-sm">
                {(primary || badge) && (
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 font-bold">{primary?.cell(r)}</div>
                    {badge && <div className="shrink-0">{badge.cell(r)}</div>}
                  </div>
                )}
                <dl className="grid grid-cols-[minmax(0,8rem)_minmax(0,1fr)] gap-x-3 gap-y-1.5">
                  {rest.map((c) => (
                    <div key={c.key} className="contents">
                      <dt className="text-muted">{c.header}</dt>
                      <dd className="min-w-0 break-words font-medium">{c.cell(r)}</dd>
                    </div>
                  ))}
                </dl>
              </li>
            ))}
          </ul>
        </>
      )}
      {footer && <div className="border-t border-border-subtle px-5 py-3.5 text-sm text-muted">{footer}</div>}
    </Card>
  )
}
