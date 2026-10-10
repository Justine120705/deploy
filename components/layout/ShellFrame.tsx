'use client'

import Image from 'next/image'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useEffect, useRef, useState } from 'react'
import { cn } from '@/lib/utils'
import type { NavItem } from '@/lib/nav'
import { ThemeToggle } from '@/components/ui/ThemeToggle'
import { Icon } from './Icon'

const FOCUS = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const NAV_ITEM = `flex h-11 w-full items-center gap-3 rounded-lg px-3 text-sm transition-colors ${FOCUS}`
// The active pill gets a lit top edge (shadow-pill), so it reads as pressed into the rail, not painted on.
const NAV_ACTIVE = 'rounded-[10px] bg-accent font-bold text-accent-foreground shadow-pill'
const NAV_IDLE = 'font-medium text-muted hover:bg-accent/60 hover:text-accent-foreground'
// Staff shell (Figma Registrar frame): the active item is a solid ink pill, not the soft violet one.
const NAV_ACTIVE_STAFF = 'rounded-[10px] bg-primary font-bold text-primary-foreground shadow-elev-xs'
// 44px: the menu button only exists below lg, where it is a touch target.
const ICON_BUTTON = `inline-flex size-11 items-center justify-center rounded-lg text-muted transition-colors hover:text-foreground ${FOCUS}`

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
  variant = 'student',
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
  /** `student`: floating topbar and promo card. `staff`: no topbar on desktop, role label, user card with sign-out. */
  variant?: 'student' | 'staff'
  children: React.ReactNode
}) {
  const staff = variant === 'staff'
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  const homeHref = items[0].href
  const menuRef = useRef<HTMLButtonElement>(null)
  const drawerRef = useRef<HTMLElement>(null)
  const wasOpen = useRef(false)

  // Mobile drawer: Escape closes it, focus moves in when it opens and back to the menu button when it closes.
  useEffect(() => {
    if (open) {
      wasOpen.current = true
      drawerRef.current?.querySelector<HTMLElement>('a[href], button:not([aria-disabled])')?.focus()
      const onKey = (e: KeyboardEvent) => {
        if (e.key === 'Escape') setOpen(false)
      }
      document.addEventListener('keydown', onKey)
      return () => document.removeEventListener('keydown', onKey)
    }
    if (wasOpen.current) {
      wasOpen.current = false
      menuRef.current?.focus()
    }
  }, [open])

  const isActive = (href: string) =>
    href === homeHref ? pathname === href : pathname === href || pathname.startsWith(href + '/')

  return (
    <div className="flex min-h-screen gap-4 bg-background p-3 text-foreground lg:p-4">
      <a
        href="#main"
        inert={open}
        className={cn(
          'sr-only rounded-lg bg-card px-4 py-2 text-sm font-semibold text-foreground focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:shadow-elev-lg',
          'focus:outline-2 focus:outline-offset-2 focus:outline-ring'
        )}
      >
        Skip to main content
      </a>
      {open && (
        <button
          type="button"
          aria-label="Close menu"
          tabIndex={-1}
          onClick={() => setOpen(false)}
          className="fixed inset-0 z-30 bg-black/40 lg:hidden"
        />
      )}

      <aside
        ref={drawerRef}
        className={cn(
          'fixed inset-y-3 left-3 z-40 flex flex-col gap-2 overflow-y-auto rounded-2xl border border-edge bg-card px-[18px] py-6 surface',
          // Level 1 on desktop (chrome sits low so content floats above it); level 3 as the mobile drawer.
          staff ? 'w-[248px]' : 'w-[232px]',
          'shadow-elev-lg lg:shadow-elev-xs',
          'transition-[transform,visibility] lg:sticky lg:inset-y-auto lg:top-4 lg:h-[calc(100vh-2rem)] lg:shrink-0 lg:translate-x-0',
          // Closed on a phone: off screen and out of the Tab order (visibility switches after the slide).
          // Opening skips the visibility transition so the first link can take focus at once.
          open ? 'translate-x-0 transition-transform' : '-translate-x-[110%] max-lg:invisible'
        )}
      >
        <div className="flex h-14 shrink-0 items-center gap-3 px-2">
          <LogoMark />
          <p className="text-xl font-extrabold leading-tight">
            <span className="text-accent-foreground">Cabuyao</span> University
          </p>
        </div>

        {staff && (
          <div className="mt-2 flex items-center justify-between px-2">
            <p className="text-xs font-semibold uppercase tracking-widest text-muted">{roleLabel}</p>
            <ThemeToggle />
          </div>
        )}

        <nav aria-label="Main" className={cn('flex flex-col gap-2', staff ? 'mt-1' : 'mt-[13px]')}>
          {items.map((item) => {
            const active = isActive(item.href)
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                aria-current={active ? 'page' : undefined}
                className={cn(NAV_ITEM, active ? (staff ? NAV_ACTIVE_STAFF : NAV_ACTIVE) : NAV_IDLE)}
              >
                <Icon name={item.icon} />
                {item.label}
              </Link>
            )
          })}
        </nav>

        <div className="mt-auto flex flex-col gap-2 pt-4">
          {!staff && promo}
          {!staff && (settingsHref ? (
            <Link href={settingsHref} className={cn(NAV_ITEM, NAV_IDLE)}>
              <Icon name="settings" />
              Settings
            </Link>
          ) : (
            <button
              type="button"
              aria-disabled="true"
              className={cn(NAV_ITEM, 'cursor-not-allowed font-medium text-muted')}
            >
              <Icon name="settings" />
              Settings
              <span className="ml-auto text-xs font-medium">Soon</span>
            </button>
          ))}
          {staff && (
            <div className="flex items-center gap-3 rounded-xl bg-accent/60 px-3 py-2.5">
              <span
                aria-hidden="true"
                className="flex size-9 shrink-0 items-center justify-center rounded-full bg-hue-violet-soft text-sm font-bold text-hue-violet-strong"
              >
                {userName.charAt(0)}
              </span>
              <div className="min-w-0 flex-1 text-sm leading-tight">
                <p className="truncate font-bold">{userName}</p>
                <p className="truncate text-muted">{roleLabel}</p>
              </div>
              {signOut}
            </div>
          )}
          {!staff && signOut}
        </div>
      </aside>

      <div inert={open} className="flex min-w-0 flex-1 flex-col gap-4">
        <header
          className={cn(
            'flex h-[60px] shrink-0 items-center justify-between gap-3 rounded-2xl border border-edge bg-card px-5 shadow-elev-xs surface',
            staff && 'lg:hidden'
          )}
        >
          <button
            type="button"
            ref={menuRef}
            aria-label="Open menu"
            onClick={() => setOpen(true)}
            className={cn(ICON_BUTTON, 'lg:hidden')}
          >
            <Icon name="menu" className="size-5" />
          </button>
          <div className={cn('ml-auto flex items-center gap-3 sm:gap-[18px]', staff && 'hidden')}>
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
        <main id="main" tabIndex={-1} className="flex min-w-0 flex-1 flex-col outline-none">{children}</main>
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
