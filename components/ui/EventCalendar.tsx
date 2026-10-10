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

  // The button is a 44px touch target on small screens; the visible circle inside stays 26px.
  const navButton =
    'group flex size-[26px] max-lg:-m-[9px] max-lg:size-11 items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
  const navCircle =
    'flex size-[26px] items-center justify-center rounded-full bg-chip text-sm font-bold text-accent-foreground transition-colors group-hover:bg-accent'

  return (
    <div className={cn('flex flex-col gap-3', className)}>
      <div className="flex items-center justify-between">
        <button type="button" aria-label="Previous month" onClick={() => shift(-1)} className={navButton}>
          <span aria-hidden="true" className={navCircle}>
            ‹
          </span>
        </button>
        <p aria-live="polite" className="text-sm font-semibold">
          {title}
        </p>
        <button type="button" aria-label="Next month" onClick={() => shift(1)} className={navButton}>
          <span aria-hidden="true" className={navCircle}>
            ›
          </span>
        </button>
      </div>

      <div role="grid" aria-label={title} className="grid grid-cols-7 justify-items-center gap-y-3">
        {WEEKDAYS.map((d) => (
          <div
            key={d.name}
            role="columnheader"
            aria-label={d.name}
            className={cn(
              'flex size-[34px] items-center justify-center text-sm font-medium',
              'text-muted'
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
                hue && !isToday
                  ? cn(HUE_SOFT[hue], HUE_TEXT[hue], 'font-bold')
                  : i % 7 === 0
                    ? 'text-muted'
                    : 'text-foreground',
                // Today: a filled pill in the primary color (ink in light, lilac in dark), readable on the card in both themes.
                isToday && 'rounded-full bg-primary font-bold text-primary-foreground'
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

      <div className="flex flex-col gap-1.5">
        <h3 className="text-sm font-semibold">This month</h3>
        {shown.length === 0 ? (
          <p className="text-sm text-muted">No events this month.</p>
        ) : (
          <ul className="flex flex-col gap-1.5">
            {shown.map(({ e, day, iso }) => (
              <li key={`${e.id}-${iso}`} className="flex items-center gap-2 text-sm">
                <span aria-hidden="true" className={cn('size-2 shrink-0 rounded-full', HUE_SOLID[hueOf(e.tone)])} />
                <span className="w-14 shrink-0 font-semibold text-muted">{dayLabel(day)}</span>
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
