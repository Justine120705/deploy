'use client'

import Image from 'next/image'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useState } from 'react'
import { cn } from '@/lib/utils'
import type { NavItem } from '@/lib/nav'
import { ThemeToggle } from '@/components/ui/ThemeToggle'
import { Icon } from './Icon'

const NAV_ITEM = 'flex h-11 w-full items-center gap-3 rounded-lg px-3 text-sm transition-colors'
// The active pill gets a lit top edge (shadow-pill), so it reads as pressed into the rail, not painted on.
const NAV_ACTIVE = 'rounded-[10px] bg-accent font-bold text-accent-foreground shadow-pill'
const NAV_IDLE = 'font-medium text-muted hover:bg-accent/60 hover:text-accent-foreground'
const ICON_BUTTON =
  'inline-flex size-8 items-center justify-center rounded-lg text-muted transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'

// Client half of the shell: sidebar with the active link, mobile drawer and top bar.
// The server half (DashboardShell) passes plain data plus the sign-out form.
export default function ShellFrame({
  items,
  roleLabel,
  userName,
  userMeta,
  signOut,
  promo,
  settingsHref,
  children,
}: {
  items: NavItem[]
  roleLabel: string
  userName: string
  /** Second line under the name in the top bar (for example "ID 2026-0001"). Defaults to the role. */
  userMeta?: string
  signOut: React.ReactNode
  /** Optional card above Settings at the bottom of the sidebar (see PromoCard). */
  promo?: React.ReactNode
  /** Where Settings goes. Without it the item is shown but disabled (there is no settings page yet). */
  settingsHref?: string
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
          'fixed inset-y-3 left-3 z-40 flex w-[232px] flex-col gap-2 overflow-y-auto rounded-2xl border border-edge bg-card px-[18px] py-6 surface',
          // Level 1 on desktop (chrome sits low so content floats above it); level 3 as the mobile drawer.
          'shadow-elev-lg lg:shadow-elev-xs',
          'transition-transform lg:sticky lg:inset-y-auto lg:top-4 lg:h-[calc(100vh-2rem)] lg:shrink-0 lg:translate-x-0',
          open ? 'translate-x-0' : '-translate-x-[110%]'
        )}
      >
        <div className="flex h-14 shrink-0 items-center gap-3 px-2">
          <LogoMark />
          <p className="text-xl font-extrabold leading-tight">
            <span className="text-accent-foreground">University</span> Portal
          </p>
        </div>

        <nav aria-label="Main" className="mt-[13px] flex flex-col gap-2">
          {items.map((item) => {
            const active = isActive(item.href)
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                aria-current={active ? 'page' : undefined}
                className={cn(NAV_ITEM, active ? NAV_ACTIVE : NAV_IDLE)}
              >
                <Icon name={item.icon} />
                {item.label}
              </Link>
            )
          })}
        </nav>

        <div className="mt-auto flex flex-col gap-2 pt-4">
          {promo}
          {settingsHref ? (
            <Link href={settingsHref} className={cn(NAV_ITEM, NAV_IDLE)}>
              <Icon name="settings" />
              Settings
            </Link>
          ) : (
            <button
              type="button"
              aria-disabled="true"
              title="Settings are not available yet"
              className={cn(NAV_ITEM, 'cursor-not-allowed font-medium text-muted')}
            >
              <Icon name="settings" />
              Settings
            </button>
          )}
          {signOut}
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col gap-4">
        <header className="flex h-[60px] shrink-0 items-center justify-between gap-3 rounded-2xl border border-edge bg-card px-5 shadow-elev-xs surface">
          <button
            type="button"
            aria-label="Open menu"
            onClick={() => setOpen(true)}
            className={cn(ICON_BUTTON, 'lg:hidden')}
          >
            <Icon name="menu" className="size-5" />
          </button>
          <div className="ml-auto flex items-center gap-3 sm:gap-[18px]">
            <button type="button" aria-label="Search" className={ICON_BUTTON}>
              <Icon name="search" className="size-5" />
            </button>
            <button type="button" aria-label="Notifications" className={ICON_BUTTON}>
              <Icon name="bell" className="size-5" />
            </button>
            <ThemeToggle />
            <div className="flex items-center gap-2.5">
              <span
                aria-hidden="true"
                className="flex size-9 shrink-0 items-center justify-center rounded-full bg-hue-violet-soft text-sm font-bold text-hue-violet-strong"
              >
                {userName.charAt(0)}
              </span>
              <div className="hidden text-sm leading-tight sm:block">
                <p className="font-bold">{userName}</p>
                <p className="text-muted">{userMeta ?? roleLabel}</p>
              </div>
            </div>
          </div>
        </header>
        <main className="flex min-w-0 flex-1 flex-col">{children}</main>
      </div>
    </div>
  )
}

// Cabuyao CU monogram: Figma's own vector (public/brand), same files as the login logo.
function LogoMark() {
  return (
    <>
      <Image
        src="/brand/cu-mark-light.svg"
        alt=""
        aria-hidden="true"
        width={82}
        height={77}
        unoptimized
        loading="eager"
        className="h-auto w-11 shrink-0 dark:hidden"
      />
      <Image
        src="/brand/cu-mark-dark.svg"
        alt=""
        aria-hidden="true"
        width={82}
        height={77}
        unoptimized
        loading="eager"
        className="hidden h-auto w-11 shrink-0 dark:block"
      />
    </>
  )
}
