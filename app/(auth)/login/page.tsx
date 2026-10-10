'use client'

import { useActionState, useState } from 'react'
import { EyeIcon, EyeOffIcon } from '@/components/auth/AuthIcons'
import { CabuyaoLogo, LoginWatermark } from '@/components/auth/CabuyaoLogo'
import { Button } from '@/components/ui/Button'
import { FIELD, FIELD_LABEL } from '@/components/ui/Input'
import { ThemeToggle } from '@/components/ui/ThemeToggle'
import { cn } from '@/lib/utils'
import { login, type LoginState } from './actions'

const INITIAL_STATE: LoginState = { error: null }

// A plain sign-in form on the page ground: the form is the focus. The only branding is the lockup in the
// top bar and the monogram, very faint, bleeding off the bottom-right edge (from md up).
export default function LoginPage() {
  const [state, formAction, isPending] = useActionState(login, INITIAL_STATE)
  const [isPasswordVisible, setIsPasswordVisible] = useState(false)

  return (
    <main className="relative isolate flex min-h-dvh flex-col overflow-hidden bg-background">
      <LoginWatermark />

      <header className="flex items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <CabuyaoLogo />
        <ThemeToggle />
      </header>

      <div className="flex flex-1 items-center justify-center px-4 py-8 sm:py-12">
        <div className="w-full max-w-[380px] rounded-lg border border-edge bg-card p-5 sm:p-7">
          <h1 className="text-2xl font-semibold tracking-[-0.01em] text-foreground">Sign in</h1>
          <p className="mt-1 text-sm text-muted">Use your portal account email and password.</p>

          <form action={formAction} className="mt-6 flex flex-col gap-4">
            <div className="flex flex-col gap-1.5">
              <label htmlFor="email" className={FIELD_LABEL}>
                Email
              </label>
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="email"
                inputMode="email"
                spellCheck={false}
                required
                aria-invalid={state.error ? true : undefined}
                className={FIELD}
              />
            </div>

            <div className="flex flex-col gap-1.5">
              <label htmlFor="password" className={FIELD_LABEL}>
                Password
              </label>
              <div className="relative">
                <input
                  id="password"
                  name="password"
                  type={isPasswordVisible ? 'text' : 'password'}
                  autoComplete="current-password"
                  required
                  aria-invalid={state.error ? true : undefined}
                  className={cn(FIELD, 'pr-11')}
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

          <p className="mt-5 border-t border-border-subtle pt-4 text-sm text-muted">
            Forgot your password? Contact the portal Admin to reset it.
          </p>
        </div>
      </div>

      <footer className="px-4 py-4 text-xs text-muted sm:px-6">© 2026 Cabuyao University</footer>
    </main>
  )
}
