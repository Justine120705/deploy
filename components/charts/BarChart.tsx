import { cn } from '@/lib/utils'
import type { Hue } from '@/components/ui/hue'
import { EmptyChart } from './EmptyChart'

// One series. Bars are a muted neutral (>= 3.3:1 on the card); the highlighted bar (the current term,
// the latest value) takes the hue's strong tier and carries its value as a label above it.
const HIGHLIGHT: Record<Hue, string> = {
  violet: 'bg-hue-violet-strong',
  sky: 'bg-hue-sky-strong',
  teal: 'bg-hue-teal-strong',
  amber: 'bg-hue-amber-strong',
  rose: 'bg-hue-rose-strong',
}

export type BarDatum = {
  label: string
  value: number
  /** Mark this bar in the accent and label its value. */
  highlight?: boolean
  /** Text of the value label and of the screen reader summary; defaults to the value. */
  display?: string
}

// Vertical bars scaled against `max` (the tallest allowed bar is `barHeight` px high), on a hairline
// baseline with 12px axis labels.
export function BarChart({
  data,
  max,
  barHeight = 88,
  hue = 'violet',
  ariaLabel,
  className,
}: {
  data: BarDatum[]
  max?: number
  barHeight?: number
  /** Hue of the highlighted bar (components/ui/hue.ts); violet is the brand accent. */
  hue?: Hue
  ariaLabel: string
  className?: string
}) {
  if (data.length === 0) return <EmptyChart ariaLabel={ariaLabel} className={className} />

  const top = max ?? Math.max(...data.map((d) => d.value), 1)
  const summary = `${ariaLabel}: ${data.map((d) => `${d.label} ${d.display ?? d.value}`).join(', ')}`

  return (
    <div role="img" aria-label={summary} className={cn('w-full', className)}>
      <div
        aria-hidden="true"
        className="flex items-end border-b border-border"
        style={{ height: `${barHeight + 24}px` }}
      >
        {data.map((d) => (
          <div key={d.label} className="flex min-w-0 flex-1 flex-col items-center gap-1">
            {d.highlight && (
              <span className="text-xs font-semibold tabular-nums text-foreground">{d.display ?? d.value}</span>
            )}
            <div
              className={cn('w-4 max-w-[60%] rounded-t-sm', d.highlight ? HIGHLIGHT[hue] : 'bg-chart-muted')}
              style={{ height: `${(Math.max(d.value, 0) / top) * barHeight}px` }}
            />
          </div>
        ))}
      </div>
      <div aria-hidden="true" className="mt-2 flex text-center text-xs text-muted">
        {data.map((d) => (
          <p key={d.label} className={cn('min-w-0 flex-1 truncate', d.highlight && 'font-semibold text-foreground')}>
            {d.label}
          </p>
        ))}
      </div>
    </div>
  )
}
