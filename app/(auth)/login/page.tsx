'use client'

import { use, useActionState, useState } from 'react'
import Link from 'next/link'
import { EyeIcon, EyeOffIcon, LockIcon, MailIcon } from '@/components/auth/AuthIcons'
import { CuMark } from '@/components/auth/CabuyaoLogo'
import { LoginShowcase } from '@/components/auth/LoginShowcase'
import { Button } from '@/components/ui/Button'
import { FIELD, FIELD_LABEL } from '@/components/ui/Input'
import { ThemeToggle } from '@/components/ui/ThemeToggle'
import { cn } from '@/lib/utils'
import { login, type LoginState } from './actions'

const INITIAL_STATE: LoginState = { error: null }

// Split sign-in: the form on the left on the page ground, a photo panel on the right (from lg up).
// On phones and tablets only the form shows. The panel text is plain product fact, no claims.
export default function LoginPage({ searchParams }: { searchParams: Promise<{ notice?: string; staff?: string }> }) {
  const { notice, staff } = use(searchParams)
  const isStaff = staff === '1'
  const [state, formAction, isPending] = useActionState(login, INITIAL_STATE)
  const [isPasswordVisible, setIsPasswordVisible] = useState(false)

  // Switching tabs swaps the sides of the page (lg and up): the photo panel slides across and the card pops
  // in on its new side. Nothing moves on the first render, only after a switch.
  const [wasStaff, setWasStaff] = useState(isStaff)
  const [motion, setMotion] = useState<'none' | 'toStaff' | 'toStudent'>('none')
  if (wasStaff !== isStaff) {
    setWasStaff(isStaff)
    setMotion(isStaff ? 'toStaff' : 'toStudent')
  }

  return (
    <main className={cn('grid min-h-dvh overflow-x-clip bg-background lg:grid-cols-2', isStaff && 'theme-staff')}>
      <div className={cn('relative z-10 flex min-h-dvh flex-col px-5 py-4 sm:px-10 lg:px-14', isStaff && 'lg:order-2')}>
        <div className="flex flex-1 items-center">
          <div className={cn('glass relative mx-auto my-6 w-full max-w-[420px] rounded-3xl border border-edge bg-card p-6 shadow-[0_8px_30px_rgb(0_0_0/0.12)] sm:p-8 dark:shadow-elev-lg', motion === 'toStaff' && 'anim-pop-a', motion === 'toStudent' && 'anim-pop-b')}>
            <div className="absolute left-3 top-3">
              <ThemeToggle />
            </div>
            <div className="mb-8 flex flex-col items-center text-center">
              <CuMark className="w-24" />
              <p className="mt-4 text-3xl font-semibold leading-tight tracking-[-0.01em]">
                <span className="text-accent-foreground">Cabuyao</span>{' '}
                <span className="text-foreground">University</span>
              </p>
              <p className="mt-1 text-sm font-medium tracking-wide text-muted">{isStaff ? 'Staff Portal' : 'Student Portal'}</p>
              <h1 className="mt-7 text-xl font-semibold text-foreground">{isStaff ? 'Staff sign in' : 'Welcome back'}</h1>
              <p className="mt-1 text-sm text-muted">
                {isStaff ? 'Registrar, Cashier, Department and Admin offices.' : 'Sign in with your student ID.'}
              </p>
            </div>

            <nav aria-label="Sign-in type" className="glass grid grid-cols-2 gap-1 rounded-full border border-border bg-card p-1">
              {[
                { href: '/login', label: 'Student', active: !isStaff },
                { href: '/login?staff=1', label: 'Staff', active: isStaff },
              ].map((tab) => (
                <Link
                  key={tab.label}
                  href={tab.href}
                  replace
                  aria-current={tab.active ? 'page' : undefined}
                  className={cn(
                    'flex h-9 items-center justify-center rounded-full text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring max-lg:h-11',
                    tab.active ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-hover-tint hover:text-foreground'
                  )}
                >
                  {tab.label}
                </Link>
              ))}
            </nav>

            {notice === 'link-expired' && (
              <p role="status" className="mt-6 rounded-md bg-accent px-3 py-2 text-sm text-accent-foreground">
                That link has expired or was already used. Contact the Registrar to get a new one.
              </p>
            )}

            <form action={formAction} className="mt-6 flex flex-col gap-4">
            <div className="flex flex-col gap-1.5">
              <label htmlFor="email" className={FIELD_LABEL}>
                {isStaff ? 'Work email' : 'Student ID (8 digits)'}
              </label>
              <div className="relative">
                <MailIcon className="pointer-events-none absolute left-3 top-1/2 z-10 size-[18px] -translate-y-1/2 text-muted" />
              <input
                id="email"
                name="email"
                type={isStaff ? 'email' : 'text'}
                inputMode={isStaff ? 'email' : 'numeric'}
                autoComplete="username"
                spellCheck={false}
                required
                aria-invalid={state.error ? true : undefined}
                className={cn(FIELD, 'pl-10')}
              />
              </div>
            </div>

            <div className="flex flex-col gap-1.5">
              <label htmlFor="password" className={FIELD_LABEL}>
                Password
              </label>
              <div className="relative">
                <LockIcon className="pointer-events-none absolute left-3 top-1/2 z-10 size-[18px] -translate-y-1/2 text-muted" />
                <input
                  id="password"
                  name="password"
                  type={isPasswordVisible ? 'text' : 'password'}
                  autoComplete="current-password"
                  required
                  aria-invalid={state.error ? true : undefined}
                  className={cn(FIELD, 'pl-10 pr-11')}
                />
                <button
                  type="button"
                  onClick={() => setIsPasswordVisible((isVisible) => !isVisible)}
                  aria-label={isPasswordVisible ? 'Hide password' : 'Show password'}
                  aria-pressed={isPasswordVisible}
                  aria-controls="password"
                  className="absolute inset-y-0 right-0 flex w-10 items-center justify-center rounded-r-md text-muted transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring max-lg:w-11"
                >
                  {isPasswordVisible ? <EyeOffIcon className="size-[18px]" /> : <EyeIcon className="size-[18px]" />}
                </button>
              </div>
            </div>

            {state.error && (
              <p id="login-error" role="alert" className="rounded-md bg-danger-soft px-3 py-2 text-sm text-danger">
                {state.error}
              </p>
            )}

            <Button type="submit" disabled={isPending} aria-busy={isPending} className="mt-1 w-full">
              {isPending ? 'Signing in...' : 'Sign in'}
            </Button>
          </form>

            {!isStaff && (
              <p className="mt-6 text-center text-sm text-muted">
                New student?{' '}
                <Link href="/apply" className="font-medium text-accent-foreground underline-offset-4 hover:underline">
                  Apply here
                </Link>
              </p>
            )}
          </div>
        </div>

        <footer className="text-xs text-muted">© 2026 Cabuyao University</footer>
      </div>

      <LoginShowcase
        variant={isStaff ? 'staff' : 'student'}
        side={isStaff ? 'left' : 'right'}
        className={cn(isStaff && 'lg:order-1', motion === 'toStaff' && 'anim-slide-from-right', motion === 'toStudent' && 'anim-slide-from-left')}
      />
    </main>
  )
}
