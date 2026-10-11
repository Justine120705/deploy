import { cn } from '@/lib/utils'
import { hueVar, type Hue } from '@/components/ui/hue'
import { EmptyChart } from './EmptyChart'

const W = 740
const H = 200

// Single-series line chart. `values` are plotted evenly across the width; `yTicks` are listed top to
// bottom and the first and last tick are the top and bottom of the plot. A solid 2px line in the hue's
// strong tier (violet, the brand accent, by default) over hairline gridlines; no area fill.
// `mark` pins a labeled point (for example the best term) on one value.
export function LineChart({
  values,
  yTicks,
  xLabels,
  ariaLabel,
  hue,
  mark,
  className,
}: {
  values: number[]
  yTicks: number[]
  xLabels: string[]
  ariaLabel: string
  hue?: Hue
  mark?: { index: number; label: string }
  className?: string
}) {
  if (values.length === 0) return <EmptyChart ariaLabel={ariaLabel} className={className} />

  const first = yTicks[0]
  const last = yTicks[yTicks.length - 1]
  const toY = (v: number) => ((v - first) / (last - first)) * H
  const points = values.map((v, i) => [(i / Math.max(values.length - 1, 1)) * W, toY(v)] as const)
  const line = points.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(2)} ${y.toFixed(2)}`).join(' ')
  const stroke = hueVar(hue ?? 'violet', 'strong')
  const marked = mark ? points[mark.index] : undefined

  return (
    <div role="img" aria-label={`${ariaLabel}: ${values.join(', ')}`} className={cn('w-full', className)}>
      <div aria-hidden="true" className="flex gap-3">
        <div className="flex h-[200px] w-10 flex-col justify-between text-xs tabular-nums text-muted">
          {yTicks.map((t) => (
            <span key={t}>{t.toFixed(2)}</span>
          ))}
        </div>
        <div className="relative h-[200px] min-w-0 flex-1">
          <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="size-full overflow-visible">
            {yTicks.map((t) => (
              <line
                key={t}
                x1="0"
                x2={W}
                y1={toY(t)}
                y2={toY(t)}
                stroke="var(--border-subtle)"
                vectorEffect="non-scaling-stroke"
              />
            ))}
            <path
              d={line}
              fill="none"
              stroke={stroke}
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              vectorEffect="non-scaling-stroke"
            />
          </svg>
          {/* Points as HTML, so the dots stay round while the plot stretches. */}
          {points.map(([x, y], i) => (
            <span
              key={i}
              aria-hidden="true"
              className="pointer-events-none absolute size-1.5 -translate-x-1/2 -translate-y-1/2 rounded-full"
              style={{ left: `${(x / W) * 100}%`, top: `${(y / H) * 100}%`, background: stroke }}
            />
          ))}
          {marked && mark && (
            <div
              className="pointer-events-none absolute flex -translate-y-1/2 items-center gap-1.5"
              style={{ left: `${(marked[0] / W) * 100}%`, top: `${(marked[1] / H) * 100}%`, marginLeft: -5 }}
            >
              <span className="size-2.5 shrink-0 rounded-full border-2 border-card" style={{ background: stroke }} />
              <span className="whitespace-nowrap rounded-md border border-border bg-card px-1.5 text-xs font-semibold tabular-nums text-foreground">
                {mark.label}
              </span>
            </div>
          )}
        </div>
      </div>
      <div aria-hidden="true" className="mt-2 flex justify-between pl-[52px] text-xs text-muted">
        {xLabels.map((l) => (
          <span key={l}>{l}</span>
        ))}
      </div>
    </div>
  )
}
