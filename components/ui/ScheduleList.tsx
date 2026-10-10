import { cn } from '@/lib/utils'

export type ScheduleTone = 'ink' | 'lilac' | 'green'
export type ScheduleEntry = { time: string; title: string; code: string; tone: ScheduleTone }

const BAR: Record<ScheduleTone, string> = {
  ink: 'bg-foreground',
  lilac: 'bg-lilac',
  green: 'bg-chart-green',
}

// Class list: meeting time, a colored bar, then the title and course code.
export function ScheduleList({ items, className }: { items: readonly ScheduleEntry[]; className?: string }) {
  return (
    <ul className={cn('flex flex-col gap-3', className)}>
      {items.map((item) => (
        <li key={item.code} className="flex items-center gap-2.5">
          <span className="shrink-0 text-sm font-semibold text-muted">{item.time}</span>
          <span aria-hidden="true" className={cn('h-8 w-[3px] shrink-0 rounded-sm', BAR[item.tone])} />
          <span className="flex min-w-0 flex-col text-sm">
            <span className="truncate font-bold">{item.title}</span>
            <span className="text-muted">{item.code}</span>
          </span>
        </li>
      ))}
    </ul>
  )
}
