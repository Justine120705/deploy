import { cn } from '@/lib/utils'
import { HUE_SOLID, HUE_TEXT, type Hue } from './hue'

/** Accent of a class. Courses use violet, sky or teal (amber and rose are kept for attention and
 *  problems); 'ink', 'lilac' and 'green' are the older names and still work. */
export type ScheduleTone = Hue | 'ink' | 'lilac' | 'green'
export type ScheduleEntry = { time: string; title: string; code: string; tone: ScheduleTone }

const LEGACY_BAR = { ink: 'bg-foreground', lilac: 'bg-lilac', green: 'bg-hue-teal-solid' } as const
const isLegacy = (t: ScheduleTone): t is keyof typeof LEGACY_BAR => t in LEGACY_BAR

// Class list: meeting time, a colored bar, then the title and course code (the code in the bar's hue).
export function ScheduleList({ items, className }: { items: readonly ScheduleEntry[]; className?: string }) {
  if (items.length === 0) {
    return <p className={cn('text-sm text-muted', className)}>No classes this term yet. They appear after you enroll.</p>
  }
  return (
    <ul className={cn('flex flex-col gap-3', className)}>
      {items.map((item) => (
        <li key={item.code} className="flex items-center gap-2.5">
          <span className="w-[4.5rem] shrink-0 text-sm font-medium tabular-nums text-muted">{item.time}</span>
          <span
            aria-hidden="true"
            className={cn(
              'h-8 w-0.5 shrink-0 rounded-full',
              isLegacy(item.tone) ? LEGACY_BAR[item.tone] : HUE_SOLID[item.tone]
            )}
          />
          <span className="flex min-w-0 flex-col text-sm">
            <span className="truncate font-semibold">{item.title}</span>
            <span className={cn('font-medium', isLegacy(item.tone) ? 'text-muted' : HUE_TEXT[item.tone])}>
              {item.code}
            </span>
          </span>
        </li>
      ))}
    </ul>
  )
}
