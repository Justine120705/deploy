'use client'

import { useState } from 'react'
import { cn } from '@/lib/utils'
import { HUE_SOFT, HUE_SOLID, HUE_TEXT, type Hue } from './hue'

/** Event type color: a hue of the color system ('green' is kept as an alias of teal). */
export type CalendarTone = Hue | 'green'
export type CalendarEvent = { id: string; title: string; tone: CalendarTone; dates: readonly string[] }

const hueOf = (tone: CalendarTone): Hue => (tone === 'green' ? 'teal' : tone)

const WEEKDAYS = [
  { letter: 'S', name: 'Sunday' },
  { letter: 'M', name: 'Monday' },
  { letter: 'T', name: 'Tuesday' },
  { letter: 'W', name: 'Wednesday' },
  { letter: 'T', name: 'Thursday' },
  { letter: 'F', name: 'Friday' },
  { letter: 'S', name: 'Saturday' },
]

const pad = (n: number) => String(n).padStart(2, '0')

// Month calendar with tinted event days. `today` is passed in (a "YYYY-MM-DD" string) instead of
// read from the clock, so the server and the browser always render the same thing.
export function EventCalendar({
  year,
  month,
  today,
  events,
  className,
}: {
  year: number
  /** 0-based month of the first view. */
  month: number
  today?: string
  events: readonly CalendarEvent[]
  className?: string
}) {
  const [view, setView] = useState({ year, month })

  const shift = (delta: number) =>
    setView((v) => {
      const d = new Date(v.year, v.month + delta, 1)
      return { year: d.getFullYear(), month: d.getMonth() }
    })

  const prefix = `${view.year}-${pad(view.month + 1)}-`
  const daysInMonth = new Date(view.year, view.month + 1, 0).getDate()
  const offset = new Date(view.year, view.month, 1).getDay()
  const title = new Date(view.year, view.month, 1).toLocaleString('en-US', { month: 'long', year: 'numeric' })

  const byDate = new Map<string, CalendarEvent>()
  const inMonth = events.filter((e) => e.dates.some((d) => d.startsWith(prefix)))
  for (const e of events) for (const d of e.dates) byDate.set(d, e)
  const legend = [...new Map(inMonth.map((e) => [hueOf(e.tone), e])).values()]

  const cells: (number | null)[] = [
    ...Array<null>(offset).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]

  const navButton =
    'flex size-[26px] items-center justify-center rounded-full bg-chip text-sm font-bold text-accent-foreground transition-colors hover:bg-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'

  return (
    <div className={cn('flex flex-col gap-3', className)}>
      <div className="flex items-center justify-between">
        <button type="button" aria-label="Previous month" onClick={() => shift(-1)} className={navButton}>
          ‹
        </button>
        <p aria-live="polite" className="text-sm font-semibold">
          {title}
        </p>
        <button type="button" aria-label="Next month" onClick={() => shift(1)} className={navButton}>
          ›
        </button>
      </div>

      <div role="grid" aria-label={title} className="grid grid-cols-7 justify-items-center gap-y-3">
        {WEEKDAYS.map((d, i) => (
          <div
            key={d.name}
            role="columnheader"
            aria-label={d.name}
            className={cn(
              'flex size-[34px] items-center justify-center text-sm font-medium',
              i === 0 ? 'text-danger' : 'text-muted'
            )}
          >
            {d.letter}
          </div>
        ))}
        {cells.map((day, i) => {
          if (day === null) return <div key={`blank-${i}`} role="gridcell" className="size-[34px]" />
          const iso = `${prefix}${pad(day)}`
          const event = byDate.get(iso)
          const isToday = iso === today
          const hue = event ? hueOf(event.tone) : undefined
          return (
            <div
              key={iso}
              role="gridcell"
              aria-current={isToday ? 'date' : undefined}
              aria-label={event ? `${day}, ${event.title}` : undefined}
              title={event?.title}
              className={cn(
                'relative flex size-[34px] items-center justify-center rounded-md text-sm font-medium',
                i % 7 === 0 ? 'text-danger' : 'text-foreground',
                hue && !isToday && cn(HUE_SOFT[hue], HUE_TEXT[hue], 'font-bold'),
                isToday && 'bg-ink font-semibold text-ink-foreground'
              )}
            >
              {day}
              {hue && (
                // Solid dot under the number: the event mark keeps 3:1 even where the tint is faint.
                <span
                  aria-hidden="true"
                  className={cn('absolute bottom-1 left-1/2 size-1 -translate-x-1/2 rounded-full', HUE_SOLID[hue])}
                />
              )}
            </div>
          )
        })}
      </div>

      <p className="flex items-center justify-center gap-1.5 text-[13px] font-medium text-muted">
        {legend.map((e) => (
          <span
            key={e.id}
            aria-hidden="true"
            title={e.title}
            className={cn('size-1.5 rounded-full', HUE_SOLID[hueOf(e.tone)])}
          />
        ))}
        {inMonth.length} {inMonth.length === 1 ? 'event' : 'events'} this month
      </p>
    </div>
  )
}
