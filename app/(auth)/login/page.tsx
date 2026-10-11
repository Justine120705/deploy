'use client'

import { useActionState, useState } from 'react'
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
export default function LoginPage() {
  const [state, formAction, isPending] = useActionState(login, INITIAL_STATE)
  const [isPasswordVisible, setIsPasswordVisible] = useState(false)

  return (
    <main className="grid min-h-dvh bg-background lg:grid-cols-2">
      <div className="flex min-h-dvh flex-col px-5 py-4 sm:px-10 lg:px-14">
        <header className="flex justify-end">
          <ThemeToggle />
        </header>

        <div className="flex flex-1 items-center">
          <div className="mx-auto w-full max-w-[360px] py-10">
            <div className="mb-8 flex flex-col items-center text-center">
              <CuMark className="w-24" />
              <p className="mt-4 text-3xl font-semibold leading-tight tracking-[-0.01em]">
                <span className="text-accent-foreground">Cabuyao</span>{' '}
                <span className="text-foreground">University</span>
              </p>
              <p className="mt-1 text-sm font-medium tracking-wide text-muted">Student Portal</p>
              <h1 className="mt-7 text-xl font-semibold text-foreground">Welcome back</h1>
              <p className="mt-1 text-sm text-muted">Sign in to your portal account.</p>
            </div>

            <form action={formAction} className="mt-6 flex flex-col gap-4">
            <div className="flex flex-col gap-1.5">
              <label htmlFor="email" className={FIELD_LABEL}>
                Email
              </label>
              <div className="relative">
                <MailIcon className="pointer-events-none absolute left-3 top-1/2 size-[18px] -translate-y-1/2 text-muted" />
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="email"
                inputMode="email"
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
                <LockIcon className="pointer-events-none absolute left-3 top-1/2 size-[18px] -translate-y-1/2 text-muted" />
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

            <p className="mt-6 text-center text-sm text-muted">Forgot your password? Contact the portal Admin to reset it.</p>
          </div>
        </div>

        <footer className="text-xs text-muted">© 2026 Cabuyao University</footer>
      </div>

      <LoginShowcase />
    </main>
  )
}
