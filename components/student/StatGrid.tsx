import { StatCard, HUE_TEXT, type Hue } from '@/components/ui'
import { cn } from '@/lib/utils'

export type Stat = {
  label: string
  value: React.ReactNode
  hint: string
  /** Colors the number. Use it only for status (teal good, amber attention, rose problem). */
  hue?: Hue
}

// Row of four summary cards under the page heading: two across on phones, four on desktop.
export function StatGrid({ stats, className }: { stats: readonly Stat[]; className?: string }) {
  return (
    <div className={cn('grid grid-cols-2 gap-4 lg:grid-cols-4', className)}>
      {stats.map((s) => (
        <StatCard
          key={s.label}
          label={s.label}
          hint={s.hint}
          value={<span className={s.hue ? HUE_TEXT[s.hue] : undefined}>{s.value}</span>}
          className="min-w-0"
        />
      ))}
    </div>
  )
}
