import Link from 'next/link'
import { CuMark } from '@/components/auth/CabuyaoLogo'
import { ThemeToggle } from '@/components/ui/ThemeToggle'

// Shared top bar and footer of the public enrollment pages (/apply and /apply/enroll). Plain server
// components: no data, no sign-in.
export function ApplyHeader() {
  return (
    <header className="mx-auto flex w-full max-w-6xl items-center justify-between gap-3 px-5 py-4 sm:px-8">
      <Link href="/apply" className="flex min-w-0 items-center gap-3 rounded-full focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring">
        <CuMark className="w-10 shrink-0" />
        <span className="truncate text-base font-semibold tracking-[-0.01em]">Cabuyao University</span>
      </Link>
      <div className="flex items-center gap-2">
        <ThemeToggle />
        <Link
          href="/login"
          className="glass inline-flex h-10 items-center rounded-full border border-field-border/60 bg-card px-5 text-sm font-semibold text-foreground transition-colors hover:border-field-border hover:bg-card-raised focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring max-lg:h-11"
        >
          Sign in
        </Link>
      </div>
    </header>
  )
}

export function ApplyFooter() {
  return (
    <footer className="mx-auto w-full max-w-6xl px-5 py-6 text-xs text-muted sm:px-8">
      <p>© 2026 Cabuyao University</p>
    </footer>
  )
}
