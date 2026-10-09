'use client'

import { useActionState, useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { login, type LoginState } from './actions'

const INITIAL_STATE: LoginState = { error: null }

export default function LoginPage() {
  const [state, formAction, isPending] = useActionState(login, INITIAL_STATE)
  const [isPasswordVisible, setIsPasswordVisible] = useState(false)

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#f5f3fa] p-4 sm:p-6">
      <Card className="flex w-full max-w-md flex-col gap-8 p-6 sm:p-8">
        <div className="text-center leading-tight">
          <p className="text-4xl font-extrabold tracking-tight text-[#121319]">Cabuyao</p>
          <p className="text-3xl font-extrabold tracking-tight text-[#7e4fb0]">University</p>
          <p className="mt-1 text-[10px] font-medium uppercase tracking-[0.12em] text-[#6e6c85]">
            Learn · Grow · Build Tomorrow
          </p>
        </div>

        <div className="flex flex-col gap-2">
          <h1 className="text-3xl font-extrabold tracking-tight text-[#121319] sm:text-4xl">
            Welcome back
          </h1>
          <p className="text-[15px] text-[#6e6c85]">Sign in to your portal account.</p>
        </div>

        <form action={formAction} className="flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <label htmlFor="email" className="text-sm font-semibold text-[#121319]">
              Email
            </label>
            <Input
              id="email"
              name="email"
              type="email"
              placeholder="Enter your email"
              autoComplete="email"
              required
              className="h-14"
            />
          </div>

          <div className="flex flex-col gap-2">
            <label htmlFor="password" className="text-sm font-semibold text-[#121319]">
              Password
            </label>
            <div className="relative">
              <Input
                id="password"
                name="password"
                type={isPasswordVisible ? 'text' : 'password'}
                placeholder="Enter your password"
                autoComplete="current-password"
                required
                className="h-14 pr-12"
              />
              <button
                type="button"
                onClick={() => setIsPasswordVisible((isVisible) => !isVisible)}
                aria-label={isPasswordVisible ? 'Hide password' : 'Show password'}
                aria-pressed={isPasswordVisible}
                className="absolute right-4 top-1/2 -translate-y-1/2 text-[#6e6c85] hover:text-[#1b1c26]"
              >
                <svg
                  viewBox="0 0 24 24"
                  className="size-5"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth={2}
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z" />
                  <circle cx="12" cy="12" r="3" />
                  {isPasswordVisible && <path d="m3 3 18 18" />}
                </svg>
              </button>
            </div>
          </div>

          {state.error && (
            <p role="alert" className="text-sm text-red-600">
              {state.error}
            </p>
          )}

          <Button type="submit" disabled={isPending} className="h-14 w-full text-base font-bold">
            {isPending ? 'Signing in...' : 'Sign in'}
          </Button>
        </form>

        <p className="text-center text-sm text-[#6e6c85]">© 2026 Student Portal</p>
      </Card>
    </main>
  )
}