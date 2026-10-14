'use client'

import { useLayoutEffect, useSyncExternalStore } from 'react'
import { cn } from '@/lib/utils'

type Theme = 'light' | 'dark'

const STORAGE_KEY = 'theme'
const CHANGE_EVENT = 'themechange'

// The theme lives in the data-theme attribute on <html>; an inline script in app/layout.tsx
// sets it before the first paint. This switch (sun left = light, moon right = dark) flips it and
// remembers the choice.
function readPreferred(): Theme {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored === 'light' || stored === 'dark') return stored
  } catch {}
  return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

function subscribe(onChange: () => void) {
  window.addEventListener(CHANGE_EVENT, onChange)
  window.addEventListener('storage', onChange)
  return () => {
    window.removeEventListener(CHANGE_EVENT, onChange)
    window.removeEventListener('storage', onChange)
  }
}

function getSnapshot(): Theme | null {
  const value = document.documentElement.getAttribute('data-theme')
  return value === 'light' || value === 'dark' ? value : null
}

function apply(theme: Theme) {
  document.documentElement.setAttribute('data-theme', theme)
  window.dispatchEvent(new Event(CHANGE_EVENT))
}

export function ThemeToggle({ className }: { className?: string }) {
  const theme = useSyncExternalStore(subscribe, getSnapshot, () => null)

  // React's dev-mode remount can clear the attribute the inline script set; put it back.
  useLayoutEffect(() => {
    if (getSnapshot() === null) apply(readPreferred())
  }, [])

  function toggle() {
    const next: Theme = (theme ?? readPreferred()) === 'dark' ? 'light' : 'dark'
    try {
      localStorage.setItem(STORAGE_KEY, next)
    } catch {}
    apply(next)
  }

  return (
    <button
      type="button"
      role="switch"
      aria-checked={theme === 'dark'}
      aria-label="Dark mode"
      onClick={toggle}
      className={cn(
        // The track: a recessed pill with a 3:1 stroke. A pseudo-element grows the tap area to 44px
        // high on small screens without changing the look.
        'relative inline-block h-7 w-14 shrink-0 rounded-full border border-field-border bg-track text-muted shadow-[inset_0_2px_4px_rgb(0_0_0/0.18)]',
        'transition-colors after:absolute after:-inset-x-1 after:-inset-y-2',
        'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring',
        className
      )}
    >
      {/* Both icons sit at the ends of the track; the thumb covers the one for the current mode.
          Position and colour come from the dark: variant (data-theme on <html>), so the switch is
          already correct on first paint, before React hydrates. */}
      <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" className="absolute top-1/2 left-[6px] size-[14px] -translate-y-1/2">
        <circle cx="12" cy="12" r="4" stroke="currentColor" strokeWidth="2" />
        <path
          d="M12 2.5v2.2M12 19.3v2.2M4.9 4.9l1.6 1.6M17.5 17.5l1.6 1.6M2.5 12h2.2M19.3 12h2.2M4.9 19.1l1.6-1.6M17.5 6.5l1.6-1.6"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        />
      </svg>
      <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" className="absolute top-1/2 right-[6px] size-[14px] -translate-y-1/2">
        <path
          d="M20.5 14.2A8.5 8.5 0 0 1 9.8 3.5a8.5 8.5 0 1 0 10.7 10.7Z"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinejoin="round"
        />
      </svg>
      <span
        aria-hidden="true"
        className="absolute top-[3px] left-[3px] size-5 rounded-full bg-white shadow-[0_1px_3px_rgb(0_0_0/0.35)] transition-transform duration-200 ease-out motion-reduce:transition-none dark:translate-x-7 dark:bg-muted"
      />
    </button>
  )
}
