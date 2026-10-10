'use client'

import { useState } from 'react'
import { cn } from '@/lib/utils'

export type CalendarTone = 'rose' | 'green' | 'amber'
export type CalendarEvent = { id: string; title: string; tone: CalendarTone; dates: readonly string[] }

const TINT: Record<CalendarTone, string> = {
  rose: 'bg-tint-rose',
  green: 'bg-tint-green',
  amber: 'bg-tint-amber',
}
const DOT: Record<CalendarTone, string> = {
  rose: 'bg-dot-rose',
  green: 'bg-dot-green',
  amber: 'bg-dot-amber',
}

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
  const tones = [...new Set(inMonth.map((e) => e.tone))]

  const cells: (number | null)[] = [
    ...Array<null>(offset).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]

  const navButton =
    'flex size-[26px] items-center justify-center rounded-full bg-chip text-sm font-bold text-accent-foreground transition-colors hover:bg-lilac-soft focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lilac'

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
          return (
            <div
              key={iso}
              role="gridcell"
              aria-current={isToday ? 'date' : undefined}
              aria-label={event ? `${day}, ${event.title}` : undefined}
              title={event?.title}
              className={cn(
                'flex size-[34px] items-center justify-center rounded-md text-sm font-medium',
                i % 7 === 0 ? 'text-danger' : 'text-foreground',
                event && !isToday && cn(TINT[event.tone], 'font-semibold text-foreground'),
                isToday && 'bg-ink font-semibold text-ink-foreground'
              )}
            >
              {day}
            </div>
          )
        })}
      </div>

      <p className="flex items-center justify-center gap-1.5 text-[13px] font-medium text-muted">
        {tones.map((t) => (
          <span key={t} aria-hidden="true" className={cn('size-1.5 rounded-full', DOT[t])} />
        ))}
        {inMonth.length} {inMonth.length === 1 ? 'event' : 'events'} this month
      </p>
    </div>
  )
}
