import { StatCard, HUE_TEXT, type Hue } from '@/components/ui'
import { cn } from '@/lib/utils'

export type DeptStat = { label: string; value: number; hint: string; hue?: Hue }

// Four stat cards in the Figma row: 2 columns on phones, 4 from lg. Value color is a hue tier; the
// label and hint carry the meaning in words.
export function DeptStats({ stats }: { stats: DeptStat[] }) {
  return (
    <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
      {stats.map((s) => (
        <StatCard
          key={s.label}
          label={s.label}
          hint={s.hint}
          value={<span className={cn(s.hue && HUE_TEXT[s.hue])}>{s.value}</span>}
        />
      ))}
    </div>
  )
}
