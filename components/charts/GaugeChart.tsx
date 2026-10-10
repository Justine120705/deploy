import { cn } from '@/lib/utils'

const R = 64
const CX = 80
const CY = 80

// Half-circle progress gauge drawn from a 0-100 value. The big label sits inside the arc.
export function GaugeChart({
  value,
  label,
  color = 'var(--lilac)',
  trackColor = 'var(--track)',
  ariaLabel,
  className,
}: {
  value: number
  /** Text inside the arc; defaults to "75%". */
  label?: React.ReactNode
  /** Filled part of the arc (a CSS color, for example var(--hue-teal-solid)). */
  color?: string
  /** Unfilled part of the arc. */
  trackColor?: string
  ariaLabel?: string
  className?: string
}) {
  const fraction = Math.min(Math.max(value, 0), 100) / 100
  const angle = Math.PI * Math.min(fraction, 0.9999)
  const x = CX - R * Math.cos(angle)
  const y = CY - R * Math.sin(angle)

  return (
    <div
      role="img"
      aria-label={ariaLabel ?? `${Math.round(value)} percent`}
      className={cn('relative h-[92px] w-[160px]', className)}
    >
      <svg aria-hidden="true" viewBox="0 0 160 92" fill="none" className="absolute inset-0 size-full">
        <path
          d={`M ${CX - R} ${CY} A ${R} ${R} 0 0 1 ${CX + R} ${CY}`}
          stroke={trackColor}
          strokeWidth="14"
          strokeLinecap="round"
        />
        {fraction > 0 && (
          <path
            d={`M ${CX - R} ${CY} A ${R} ${R} 0 0 1 ${x.toFixed(3)} ${y.toFixed(3)}`}
            stroke={color}
            strokeWidth="14"
          />
        )}
      </svg>
      <p className="absolute inset-x-0 top-12 text-center text-2xl font-extrabold leading-normal">
        {label ?? `${Math.round(value)}%`}
      </p>
    </div>
  )
}

// Small colored dot plus label, used under charts.
export function LegendItem({ color, children }: { color: string; children: React.ReactNode }) {
  return (
    <span className="flex items-center gap-1.5 text-sm font-medium text-muted">
      <span aria-hidden="true" className="size-2 rounded-full" style={{ background: color }} />
      {children}
    </span>
  )
}
