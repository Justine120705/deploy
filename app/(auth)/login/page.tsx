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
    <main className="flex min-h-screen items-center justify-center p-4 sm:p-6">
      <Card className="w-full max-w-sm p-6 sm:max-w-md sm:p-8">
        <h1 className="mb-6 text-center text-2xl font-semibold">
          Student Portal Login
        </h1>

        <form action={formAction} className="flex flex-col gap-4">
          <Input
            name="email"
            type="email"
            placeholder="Email"
            autoComplete="email"
            required
          />

          <div className="relative">
            <Input
              name="password"
              type={isPasswordVisible ? 'text' : 'password'}
              placeholder="Password"
              autoComplete="current-password"
              required
            />
            <button
              type="button"
              onClick={() => setIsPasswordVisible((isVisible) => !isVisible)}
              aria-label={isPasswordVisible ? 'Hide password' : 'Show password'}
              className="absolute inset-y-0 right-3 text-sm text-gray-500 hover:text-gray-700"
            >
              {isPasswordVisible ? 'Hide' : 'Show'}
            </button>
          </div>

          {state.error && (
            <p role="alert" className="text-sm text-red-600">
              {state.error}
            </p>
          )}

          <Button type="submit" disabled={isPending} className="w-full">
            {isPending ? 'Signing in...' : 'Sign in'}
          </Button>
        </form>
      </Card>
    </main>
  )
}