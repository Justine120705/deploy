import { cn } from '@/lib/utils'

const R = 64
const CX = 80
const CY = 80

// Legacy half-circle progress gauge (0-100). Prefer a plain figure or a progress bar in new screens.
// Flat strokes, no rounded caps; the figure sits inside the arc.
export function GaugeChart({
  value,
  label,
  color = 'var(--accent-foreground)',
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
        <path d={`M ${CX - R} ${CY} A ${R} ${R} 0 0 1 ${CX + R} ${CY}`} stroke={trackColor} strokeWidth="10" />
        {fraction > 0 && (
          <path
            d={`M ${CX - R} ${CY} A ${R} ${R} 0 0 1 ${x.toFixed(3)} ${y.toFixed(3)}`}
            stroke={color}
            strokeWidth="10"
          />
        )}
      </svg>
      <p className="absolute inset-x-0 top-12 text-center text-3xl font-semibold tabular-nums">
        {label ?? `${Math.round(value)}%`}
      </p>
    </div>
  )
}

// Small colored dot plus label, used under charts.
export function LegendItem({ color, children }: { color: string; children: React.ReactNode }) {
  return (
    <span className="flex items-center gap-1.5 text-xs text-muted">
      <span aria-hidden="true" className="size-2 rounded-full" style={{ background: color }} />
      {children}
    </span>
  )
}
