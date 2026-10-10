'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useState } from 'react'
import { cn } from '@/lib/utils'
import type { NavItem } from '@/lib/nav'
import { Icon } from './Icon'

// Client half of the shell: sidebar with the active link, mobile drawer and top bar.
// The server half (DashboardShell) passes plain data plus the sign-out form.
export default function ShellFrame({
  items,
  roleLabel,
  userName,
  signOut,
  children,
}: {
  items: NavItem[]
  roleLabel: string
  userName: string
  signOut: React.ReactNode
  children: React.ReactNode
}) {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  const homeHref = items[0].href

  const isActive = (href: string) =>
    href === homeHref ? pathname === href : pathname === href || pathname.startsWith(href + '/')

  return (
    <div className="flex min-h-screen gap-4 bg-background p-3 text-foreground lg:p-4">
      {open && (
        <button
          type="button"
          aria-label="Close menu"
          onClick={() => setOpen(false)}
          className="fixed inset-0 z-30 bg-black/40 lg:hidden"
        />
      )}

      <aside
        className={cn(
          'fixed inset-y-3 left-3 z-40 flex w-[232px] flex-col gap-2 rounded-xl border border-border bg-card px-[18px] py-6',
          'transition-transform lg:sticky lg:inset-y-auto lg:top-4 lg:h-[calc(100vh-2rem)] lg:shrink-0 lg:translate-x-0',
          open ? 'translate-x-0' : '-translate-x-[110%]'
        )}
      >
        <div className="flex h-14 items-center gap-3 px-2">
          <LogoMark />
          <p className="text-xl font-extrabold leading-tight">
            <span className="text-accent-foreground">University</span> Portal
          </p>
        </div>

        <nav aria-label="Main" className="mt-3 flex flex-col gap-2">
          {items.map((item) => {
            const active = isActive(item.href)
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                aria-current={active ? 'page' : undefined}
                className={cn(
                  'flex h-11 items-center gap-3 rounded-lg px-3 text-sm transition-colors',
                  active
                    ? 'rounded-[10px] bg-accent font-bold text-accent-foreground'
                    : 'font-medium text-muted hover:bg-accent/60 hover:text-accent-foreground'
                )}
              >
                <Icon name={item.icon} />
                {item.label}
              </Link>
            )
          })}
        </nav>

        <div className="mt-auto">{signOut}</div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col gap-4">
        <header className="flex h-[60px] shrink-0 items-center justify-between rounded-xl border border-border bg-card px-5">
          <button
            type="button"
            aria-label="Open menu"
            onClick={() => setOpen(true)}
            className="text-muted hover:text-foreground lg:hidden"
          >
            <Icon name="menu" className="size-5" />
          </button>
          <span className="hidden text-sm font-semibold text-muted lg:block">{roleLabel}</span>
          <div className="flex items-center gap-2.5">
            <span className="flex size-9 items-center justify-center rounded-full bg-lilac-soft text-sm font-bold text-accent-foreground">
              {userName.charAt(0)}
            </span>
            <div className="text-sm leading-tight">
              <p className="font-bold">{userName}</p>
              <p className="text-muted">{roleLabel}</p>
            </div>
          </div>
        </header>
        <main className="flex-1">{children}</main>
      </div>
    </div>
  )
}

// Small version of the Cabuyao hexagon mark (same shapes as components/auth/CabuyaoLogo).
function LogoMark() {
  return (
    <svg aria-hidden="true" viewBox="0 0 80 92" fill="none" className="h-10 w-auto shrink-0">
      <path d="M40 0 80 23v46L40 92 0 69V23z" className="fill-[#1b1c26] dark:fill-white" />
      <path d="M40 0 80 23 40 46 0 23z" className="fill-[#b78ae6] dark:fill-[#c9a0e3]" />
      <path
        d="M24 40v22l16 10 16-10V40"
        strokeWidth="8"
        strokeLinejoin="round"
        className="stroke-white dark:stroke-[#181b27]"
      />
    </svg>
  )
}
