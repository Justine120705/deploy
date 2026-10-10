'use client'

import { useEffect, useState } from 'react'

const pad = (n: number) => String(n).padStart(2, '0')

// Dark "Next lesson in" card, raised one level above its card (shadow-elev-md) with a hh:mm:ss countdown. The first render uses `seconds` exactly as
// given (same on server and browser); it only starts ticking after mount, so there is no hydration
// mismatch.
export function NextLesson({ seconds, title }: { seconds: number; title: string }) {
  const [left, setLeft] = useState(seconds)

  useEffect(() => {
    const id = setInterval(() => setLeft((s) => Math.max(s - 1, 0)), 1000)
    return () => clearInterval(id)
  }, [])

  const parts = [Math.floor(left / 3600), Math.floor((left % 3600) / 60), left % 60]

  return (
    <div className="flex flex-col gap-2 rounded-xl bg-ink p-4 text-ink-foreground shadow-elev-md">
      <p className="text-sm font-medium">Next lesson in</p>
      <p
        role="timer"
        aria-label={`${parts[0]} hours ${parts[1]} minutes ${parts[2]} seconds`}
        className="flex items-center gap-1.5"
      >
        {parts.map((p, i) => (
          <span key={i} aria-hidden="true" className="flex items-center gap-1.5">
            {i > 0 && <span className="text-base font-bold">:</span>}
            <span className="rounded-md px-2.5 py-2 text-lg font-extrabold tabular-nums">{pad(p)}</span>
          </span>
        ))}
      </p>
      <p className="text-sm font-medium">{title}</p>
    </div>
  )
}
