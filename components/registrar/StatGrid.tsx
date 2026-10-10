import { Card } from '@/components/ui'
import { HUE_TEXT, type Hue } from '@/components/ui/hue'
import { cn } from '@/lib/utils'

export type Stat = { label: string; value: React.ReactNode; hint: string; hue?: Hue }

// Row of four summary cards shown under the page title on every Registrar screen. The number takes
// the topic hue only when it needs attention (or is good news); the label and hint say what it is.
export default function StatGrid({ items }: { items: Stat[] }) {
  return (
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4">
      {items.map((s) => (
        <Card key={s.label} className="flex flex-col gap-1 p-5">
          <p className="text-sm font-medium text-muted">{s.label}</p>
          <p className={cn('text-3xl font-extrabold', s.hue && HUE_TEXT[s.hue])}>{s.value}</p>
          <p className="text-sm text-muted">{s.hint}</p>
        </Card>
      ))}
    </div>
  )
}
