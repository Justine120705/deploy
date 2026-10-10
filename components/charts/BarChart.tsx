import { cn } from '@/lib/utils'
import type { Hue } from '@/components/ui/hue'
import { EmptyChart } from './EmptyChart'

// Every bar is drawn in the hue's solid tier (>= 3:1 on the card); the highlighted bar uses the
// deeper strong tier and carries the tooltip chip, so it stands out without a second hue.
const BAR: Record<Hue, { base: string; highlight: string }> = {
  violet: { base: 'bg-hue-violet-solid', highlight: 'bg-hue-violet-strong' },
  sky: { base: 'bg-hue-sky-solid', highlight: 'bg-hue-sky-strong' },
  teal: { base: 'bg-hue-teal-solid', highlight: 'bg-hue-teal-strong' },
  amber: { base: 'bg-hue-amber-solid', highlight: 'bg-hue-amber-strong' },
  rose: { base: 'bg-hue-rose-solid', highlight: 'bg-hue-rose-strong' },
}

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
  hue = 'teal',
  ariaLabel,
  className,
}: {
  data: BarDatum[]
  max?: number
  barHeight?: number
  /** Topic hue of the chart (components/ui/hue.ts). */
  hue?: Hue
  ariaLabel: string
  className?: string
}) {
  if (data.length === 0) return <EmptyChart ariaLabel={ariaLabel} className={className} />

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
              className={cn('w-3.5 rounded-[5px]', d.highlight ? BAR[hue].highlight : BAR[hue].base)}
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
