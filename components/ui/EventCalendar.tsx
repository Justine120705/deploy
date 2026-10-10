'use client'

import { useState } from 'react'
import { cn } from '@/lib/utils'
import { HUE_SOLID, type Hue } from './hue'

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

// Compact month calendar: event days carry a dot in the event's hue. `today` is passed in (a "YYYY-MM-DD" string) instead of
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
  // Every dated event of this month as plain text (the colored cells alone are not readable by keyboard, touch or screen reader).
  const listed = inMonth
    .flatMap((e) => e.dates.filter((d) => d.startsWith(prefix)).map((d) => ({ e, day: Number(d.slice(8)), iso: d })))
    .sort((a, b) => a.iso.localeCompare(b.iso))
  const shown = listed.slice(0, 4)
  const dayLabel = (day: number) =>
    new Date(view.year, view.month, day).toLocaleString('en-US', { month: 'short', day: 'numeric' })

  const cells: (number | null)[] = [
    ...Array<null>(offset).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]

  // The button is a 44px touch target on small screens; the visible square inside stays 28px.
  const navButton =
    'group flex size-7 max-lg:-m-2 max-lg:size-11 items-center justify-center rounded-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
  const navSquare =
    'flex size-7 items-center justify-center rounded-md text-muted transition-colors group-hover:bg-hover-tint group-hover:text-foreground'

  return (
    <div className={cn('flex flex-col gap-3', className)}>
      <div className="flex items-center justify-between">
        <button type="button" aria-label="Previous month" onClick={() => shift(-1)} className={navButton}>
          <span aria-hidden="true" className={navSquare}>
            <Chevron dir="left" />
          </span>
        </button>
        <p aria-live="polite" className="text-sm font-semibold">
          {title}
        </p>
        <button type="button" aria-label="Next month" onClick={() => shift(1)} className={navButton}>
          <span aria-hidden="true" className={navSquare}>
            <Chevron dir="right" />
          </span>
        </button>
      </div>

      <div role="grid" aria-label={title} className="grid grid-cols-7 justify-items-center gap-y-1">
        {WEEKDAYS.map((d) => (
          <div
            key={d.name}
            role="columnheader"
            aria-label={d.name}
            className="flex size-8 items-center justify-center text-xs font-medium text-muted"
          >
            {d.letter}
          </div>
        ))}
        {cells.map((day, i) => {
          if (day === null) return <div key={`blank-${i}`} role="gridcell" className="size-8" />
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
                'relative flex size-8 items-center justify-center rounded-md text-sm tabular-nums',
                hue ? 'font-semibold text-foreground' : i % 7 === 0 ? 'text-muted' : 'text-foreground',
                // Today: the accent, solid, in both themes.
                isToday && 'bg-primary font-semibold text-primary-foreground'
              )}
            >
              {day}
              {hue && (
                // Event mark: a solid dot in the event's hue (>= 3:1 on the card).
                <span
                  aria-hidden="true"
                  className={cn(
                    'absolute bottom-0.5 left-1/2 size-1 -translate-x-1/2 rounded-full',
                    isToday ? 'bg-primary-foreground' : HUE_SOLID[hue]
                  )}
                />
              )}
            </div>
          )
        })}
      </div>

      <div className="flex flex-col gap-1.5">
        <h3 className="text-sm font-semibold">This month</h3>
        {shown.length === 0 ? (
          <p className="text-sm text-muted">No events this month.</p>
        ) : (
          <ul className="flex flex-col gap-1.5">
            {shown.map(({ e, day, iso }) => (
              <li key={`${e.id}-${iso}`} className="flex items-center gap-2 text-sm">
                <span aria-hidden="true" className={cn('size-2 shrink-0 rounded-full', HUE_SOLID[hueOf(e.tone)])} />
                <span className="w-14 shrink-0 font-medium text-muted tabular-nums">{dayLabel(day)}</span>
                <span className="min-w-0 truncate font-medium">{e.title}</span>
              </li>
            ))}
          </ul>
        )}
        {listed.length > shown.length && (
          <p className="text-sm text-muted">and {listed.length - shown.length} more</p>
        )}
      </div>
    </div>
  )
}

function Chevron({ dir }: { dir: 'left' | 'right' }) {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="size-4">
      <path
        d={dir === 'left' ? 'M10 3.5 5.5 8l4.5 4.5' : 'M6 3.5 10.5 8 6 12.5'}
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}
