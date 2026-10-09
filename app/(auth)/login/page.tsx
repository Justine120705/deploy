'use client'

import Link from 'next/link'
import { useActionState, useState } from 'react'
import {
  ArrowIcon,
  EyeIcon,
  EyeOffIcon,
  LockIcon,
  MailIcon,
} from '@/components/auth/AuthIcons'
import { CabuyaoLogo } from '@/components/auth/CabuyaoLogo'
import { LoginHero } from '@/components/auth/LoginHero'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { login, type LoginState } from './actions'

const INITIAL_STATE: LoginState = { error: null }

const LABEL_CLASS = 'text-sm font-semibold text-[#121319] dark:text-[#a1a1b5]'
const FIELD_ICON_CLASS =
  'pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-[#6e6c85] dark:text-[#a1a1b5]'
const INPUT_CLASS =
  'h-14 rounded-lg border border-[#e5e7eb] bg-white pl-12 text-[15px] font-medium text-[#121319] focus:border-[#1b1c26] dark:border-[#2c3144] dark:bg-[#1f2333] dark:text-white dark:focus:border-[#c9a0e3]'

export default function LoginPage() {
  const [state, formAction, isPending] = useActionState(login, INITIAL_STATE)
  const [isPasswordVisible, setIsPasswordVisible] = useState(false)

  return (
    <main className="flex min-h-screen gap-4 bg-[#f5f3fa] sm:p-4 dark:bg-[#181b27]">
      <Card className="relative flex w-full flex-col justify-between gap-8 overflow-hidden border-[#e5e7eb] bg-white p-6 sm:p-8 lg:w-[560px] lg:shrink-0 dark:border-[#2c3144] dark:bg-[#181b27]">
        <div className="pointer-events-none absolute -left-3 -top-3 size-[120px] rounded-xl border border-[#e5e7eb] bg-[#f3e8ff] dark:border-0 dark:bg-[#2a2f42]" />
        <div className="pointer-events-none absolute -bottom-3 -right-3 size-[180px] rounded-xl border border-[#e5e7eb] bg-[#f3e8ff] dark:border-0 dark:bg-[#2a2f42]" />

        <div className="relative flex h-40 items-center justify-center">
          <CabuyaoLogo />
        </div>

        <div className="relative flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <h1 className="text-3xl font-extrabold tracking-tight text-[#121319] sm:text-[38px] dark:text-white">
              Welcome back
            </h1>
            <p className="text-[15px] text-[#6e6c85] dark:text-[#a1a1b5]">
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
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-[#6e6c85] hover:text-[#1b1c26] dark:text-[#a1a1b5] dark:hover:text-white"
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
              <label className="flex items-center gap-2.5 font-medium text-[#121319] dark:text-[#a1a1b5]">
                <input
                  type="checkbox"
                  name="remember"
                  className="size-5 rounded-md accent-[#1b1c26] dark:accent-[#c9a0e3]"
                />
                Keep me signed in
              </label>
              <Link
                href="/forgot-password"
                className="font-semibold text-[#1b1c26] hover:underline dark:text-[#d9b8ee]"
              >
                Forgot password?
              </Link>
            </div>

            {state.error && (
              <p role="alert" className="text-sm text-red-600 dark:text-red-400">
                {state.error}
              </p>
            )}

            <Button
              type="submit"
              disabled={isPending}
              className="h-14 w-full gap-2.5 bg-[#1b1c26] text-base font-bold text-white hover:bg-[#1b1c26]/90 dark:bg-[#c9a0e3] dark:text-[#343434] dark:hover:bg-[#c9a0e3]/90"
            >
              {isPending ? 'Signing in...' : 'Sign in'}
              {!isPending && <ArrowIcon className="size-[18px]" />}
            </Button>
          </form>
        </div>

        <footer className="relative flex items-center justify-between text-sm text-[#6e6c85] dark:text-[#a1a1b5]">
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