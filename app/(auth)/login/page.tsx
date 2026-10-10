'use client'

import Link from 'next/link'
import { useActionState, useState } from 'react'
import {
  ArrowIcon,
  EyeIcon,
  EyeOffIcon,
  LockIcon,
  MailIcon,
  ShieldIcon,
} from '@/components/auth/AuthIcons'
import { CabuyaoLogo } from '@/components/auth/CabuyaoLogo'
import { LoginBackdrop } from '@/components/auth/LoginBackdrop'
import { LoginHero } from '@/components/auth/LoginHero'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { login, type LoginState } from './actions'

const INITIAL_STATE: LoginState = { error: null }

const LABEL_CLASS = 'text-sm font-semibold text-foreground'
const FIELD_ICON_CLASS = 'pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-muted'
const INPUT_CLASS =
  'h-14 rounded-lg border-border bg-card pl-12 text-[15px] font-medium focus:border-primary focus:outline-lilac'

export default function LoginPage() {
  const [state, formAction, isPending] = useActionState(login, INITIAL_STATE)
  const [isPasswordVisible, setIsPasswordVisible] = useState(false)

  return (
    <main className="relative flex min-h-screen overflow-hidden bg-background p-3 sm:p-4 lg:gap-12 lg:p-6">
      <LoginBackdrop />

      <Card className="relative flex w-full flex-col justify-between gap-10 p-6 shadow-xl shadow-black/5 sm:p-10 lg:w-[560px] lg:shrink-0">
        <CabuyaoLogo size="lg" className="max-w-full" />

        <div className="relative flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <h1 className="text-3xl font-extrabold tracking-tight text-foreground sm:text-[38px]">
              Welcome back
            </h1>
            <p className="text-[15px] text-muted">
              Sign in to your portal account.
            </p>
          </div>

          <form action={formAction} className="flex flex-col gap-4">
            <div className="flex flex-col gap-3.5">
              <div className="flex flex-col gap-2">
                <label htmlFor="email" className={LABEL_CLASS}>
                  Email
                </label>
                <div className="relative">
                  <MailIcon className={FIELD_ICON_CLASS} />
                  <Input
                    id="email"
                    name="email"
                    type="email"
                    placeholder="Enter your email"
                    autoComplete="email"
                    required
                    className={INPUT_CLASS}
                  />
                </div>
              </div>

              <div className="flex flex-col gap-2">
                <label htmlFor="password" className={LABEL_CLASS}>
                  Password
                </label>
                <div className="relative">
                  <LockIcon className={FIELD_ICON_CLASS} />
                  <Input
                    id="password"
                    name="password"
                    type={isPasswordVisible ? 'text' : 'password'}
                    placeholder="Enter your password"
                    autoComplete="current-password"
                    required
                    className={`${INPUT_CLASS} pr-12`}
                  />
                  <button
                    type="button"
                    onClick={() => setIsPasswordVisible((isVisible) => !isVisible)}
                    aria-label={isPasswordVisible ? 'Hide password' : 'Show password'}
                    aria-pressed={isPasswordVisible}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-muted hover:text-foreground"
                  >
                    {isPasswordVisible ? (
                      <EyeOffIcon className="size-5" />
                    ) : (
                      <EyeIcon className="size-5" />
                    )}
                  </button>
                </div>
              </div>
            </div>

            <div className="flex items-center justify-between gap-2 text-sm">
              <label className="flex items-center gap-2.5 font-medium text-foreground">
                <input
                  type="checkbox"
                  name="remember"
                  className="size-5 rounded-md accent-primary"
                />
                Keep me signed in
              </label>
              <Link
                href="/forgot-password"
                className="font-semibold text-accent-foreground hover:underline"
              >
                Forgot password?
              </Link>
            </div>

            {state.error && (
              <p role="alert" className="text-sm text-danger">
                {state.error}
              </p>
            )}

            <Button
              type="submit"
              disabled={isPending}
              className="h-14 w-full gap-2.5 text-base font-bold"
            >
              {isPending ? 'Signing in...' : 'Sign in'}
              {!isPending && <ArrowIcon className="size-[18px]" />}
            </Button>

            <p className="flex items-center justify-center gap-2 text-sm text-muted">
              <ShieldIcon className="size-4 shrink-0" />
              Your sign-in is encrypted.
            </p>
          </form>
        </div>

        <footer className="relative flex items-center justify-between text-sm text-muted">
          <p>© 2026 Student Portal</p>
          <div className="flex gap-4 font-medium">
            <Link href="/privacy" className="hover:underline">Privacy</Link>
            <Link href="/help" className="hover:underline">Help</Link>
          </div>
        </footer>
      </Card>

      <LoginHero />
    </main>
  )
}