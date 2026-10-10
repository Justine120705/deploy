'use client'

import Image from 'next/image'
import { useActionState, useState } from 'react'
import { EyeIcon, EyeOffIcon } from '@/components/auth/AuthIcons'
import { CabuyaoLogo } from '@/components/auth/CabuyaoLogo'
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
        <header className="flex items-center justify-between gap-3">
          <CabuyaoLogo />
          <ThemeToggle />
        </header>

        <div className="flex flex-1 items-center">
          <div className="mx-auto w-full max-w-[360px] py-10">
            <h1 className="text-2xl font-semibold tracking-[-0.01em] text-foreground">Welcome back</h1>
            <p className="mt-1 text-sm text-muted">Sign in to your portal account.</p>

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

            <p className="mt-6 text-sm text-muted">Forgot your password? Contact the portal Admin to reset it.</p>
          </div>
        </div>

        <footer className="text-xs text-muted">© 2026 Cabuyao University</footer>
      </div>

      <aside className="relative m-4 hidden overflow-hidden rounded-xl bg-ink lg:block">
        <Image
          src="/photos/lecture-hall.jpg"
          alt="Students in a lecture hall with laptops"
          fill
          priority
          sizes="50vw"
          className="object-cover"
        />
        {/* Scrim for the text only: solid at the bottom where the text sits, clear at the top. */}
        <div aria-hidden="true" className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/35 to-transparent" />
        <div className="absolute inset-x-0 bottom-0 p-10 text-white">
          <p className="max-w-md text-3xl font-semibold leading-tight tracking-[-0.01em]">
            Enrollment, grades and clearance in one place.
          </p>
          <p className="mt-3 max-w-md text-sm leading-6 text-white/90">
            Sign in to see where your requests stand and what to do next.
          </p>
        </div>
      </aside>
    </main>
  )
}
