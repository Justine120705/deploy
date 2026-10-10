import { cn } from '@/lib/utils'

export type BarDatum = {
  label: string
  value: number
  /** Show the tooltip chip and the strong color for this bar. */
  highlight?: boolean
  /** Text of the tooltip chip and of the screen reader summary; defaults to the value. */
  display?: string
}

// Vertical bars scaled against `max` (the tallest allowed bar is `barHeight` px high). One bar can
// be highlighted with a dark tooltip chip above it.
export function BarChart({
  data,
  max,
  barHeight = 88,
  ariaLabel,
  className,
}: {
  data: BarDatum[]
  max?: number
  barHeight?: number
  ariaLabel: string
  className?: string
}) {
  const top = max ?? Math.max(...data.map((d) => d.value), 1)
  const summary = `${ariaLabel}: ${data.map((d) => `${d.label} ${d.display ?? d.value}`).join(', ')}`

  return (
    <div role="img" aria-label={summary} className={cn('w-full', className)}>
      <div aria-hidden="true" className="flex h-28 items-end">
        {data.map((d) => (
          <div key={d.label} className="flex min-w-0 flex-1 flex-col items-center gap-1">
            {d.highlight && (
              <span className="rounded-md bg-tooltip px-2 text-sm font-bold text-tooltip-foreground">
                {d.display ?? d.value}
              </span>
            )}
            <div
              className={cn('w-3.5 rounded-[5px]', d.highlight ? 'bg-chart-green' : 'bg-chart-green-soft')}
              style={{ height: `${(Math.max(d.value, 0) / top) * barHeight}px` }}
            />
          </div>
        ))}
      </div>
      <div aria-hidden="true" className="mt-3 flex text-center text-sm font-medium text-muted">
        {data.map((d) => (
          <p key={d.label} className="min-w-0 flex-1">
            {d.label}
          </p>
        ))}
      </div>
    </div>
  )
}
