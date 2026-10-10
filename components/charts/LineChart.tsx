import { cn } from '@/lib/utils'
import { hueVar, type Hue } from '@/components/ui/hue'

const W = 740
const H = 200

// Area line chart. `values` are plotted evenly across the width; `yTicks` are listed top to bottom
// and the first and last tick are the top and bottom of the plot. The area under the line is filled.
// With a `hue` the line takes the hue's strong tier and the area fades from its solid tier to clear;
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
  const first = yTicks[0]
  const last = yTicks[yTicks.length - 1]
  const toY = (v: number) => ((v - first) / (last - first)) * H
  const points = values.map((v, i) => [(i / Math.max(values.length - 1, 1)) * W, toY(v)] as const)
  const line = points.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(2)} ${y.toFixed(2)}`).join(' ')
  const area = `${line} V${H} H0 Z`
  const fillId = `line-fill-${hue ?? 'plain'}`
  const marked = mark ? points[mark.index] : undefined

  return (
    <div role="img" aria-label={`${ariaLabel}: ${values.join(', ')}`} className={cn('w-full', className)}>
      <div aria-hidden="true" className="flex gap-3">
        <div className="flex h-[200px] w-10 flex-col justify-between text-sm font-medium text-muted">
          {yTicks.map((t) => (
            <span key={t}>{t.toFixed(2)}</span>
          ))}
        </div>
        <div className="relative h-[200px] min-w-0 flex-1">
          <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="size-full overflow-visible">
            {hue && (
              <defs>
                <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={hueVar(hue, 'solid')} stopOpacity="0.32" />
                  <stop offset="100%" stopColor={hueVar(hue, 'solid')} stopOpacity="0" />
                </linearGradient>
              </defs>
            )}
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
            <path d={area} fill={hue ? `url(#${fillId})` : 'var(--chart-area)'} />
            <path
              d={line}
              fill="none"
              stroke={hue ? hueVar(hue, 'strong') : 'var(--foreground)'}
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              vectorEffect="non-scaling-stroke"
            />
          </svg>
          {marked && mark && (
            // HTML, not SVG, so the dot stays round while the plot stretches.
            <div
              className="pointer-events-none absolute flex -translate-y-1/2 items-center gap-1.5"
              style={{ left: `${(marked[0] / W) * 100}%`, top: `${(marked[1] / H) * 100}%`, marginLeft: -6 }}
            >
              <span
                className="size-3 shrink-0 rounded-full border-2 border-card"
                style={{ background: hue ? hueVar(hue, 'strong') : 'var(--foreground)' }}
              />
              <span className="whitespace-nowrap rounded-md bg-tooltip px-2 text-sm font-bold text-tooltip-foreground">
                {mark.label}
              </span>
            </div>
          )}
        </div>
      </div>
      <div aria-hidden="true" className="mt-2 flex justify-between pl-[52px] text-sm font-medium text-muted">
        {xLabels.map((l) => (
          <span key={l}>{l}</span>
        ))}
      </div>
    </div>
  )
}
