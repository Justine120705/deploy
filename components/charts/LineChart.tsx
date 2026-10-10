import { cn } from '@/lib/utils'

const W = 740
const H = 200

// Area line chart. `values` are plotted evenly across the width; `yTicks` are listed top to bottom
// and the first and last tick are the top and bottom of the plot. The area under the line is filled.
export function LineChart({
  values,
  yTicks,
  xLabels,
  ariaLabel,
  className,
}: {
  values: number[]
  yTicks: number[]
  xLabels: string[]
  ariaLabel: string
  className?: string
}) {
  const first = yTicks[0]
  const last = yTicks[yTicks.length - 1]
  const toY = (v: number) => ((v - first) / (last - first)) * H
  const points = values.map((v, i) => [(i / Math.max(values.length - 1, 1)) * W, toY(v)] as const)
  const line = points.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(2)} ${y.toFixed(2)}`).join(' ')
  const area = `${line} V${H} H0 Z`

  return (
    <div role="img" aria-label={`${ariaLabel}: ${values.join(', ')}`} className={cn('w-full', className)}>
      <div aria-hidden="true" className="flex gap-3">
        <div className="flex h-[200px] w-10 flex-col justify-between text-sm font-medium text-muted">
          {yTicks.map((t) => (
            <span key={t}>{t.toFixed(2)}</span>
          ))}
        </div>
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="h-[200px] min-w-0 flex-1 overflow-visible">
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
          <path d={area} fill="var(--chart-area)" />
          <path
            d={line}
            fill="none"
            stroke="var(--foreground)"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            vectorEffect="non-scaling-stroke"
          />
        </svg>
      </div>
      <div aria-hidden="true" className="mt-2 flex justify-between pl-[52px] text-sm font-medium text-muted">
        {xLabels.map((l) => (
          <span key={l}>{l}</span>
        ))}
      </div>
    </div>
  )
}
