import { StatCard } from '@/components/ui'
import { HUE_TEXT, type Hue } from '@/components/ui/hue'
import { cn } from '@/lib/utils'

export type CashierStat = { label: string; value: string; hint: string; hue?: Hue }

// Four stat cards: one column on phones, two on tablets, four on desktop. A hue colors the number
// (teal = collected, amber = still to collect); the label and hint say the same thing in words.
export function StatRow({ stats }: { stats: CashierStat[] }) {
  return (
    <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
      {stats.map((s) => (
        <StatCard
          key={s.label}
          label={s.label}
          value={<span className={cn(s.hue && HUE_TEXT[s.hue])}>{s.value}</span>}
          hint={s.hint}
        />
      ))}
    </div>
  )
}
