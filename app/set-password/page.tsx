import type { Metadata } from 'next'
import { redirect } from 'next/navigation'
import { CuMark } from '@/components/auth/CabuyaoLogo'
import { ThemeToggle } from '@/components/ui/ThemeToggle'
import { createClient } from '@/lib/supabase/server'
import { SetPasswordForm } from './SetPasswordForm'

export const metadata: Metadata = { title: 'Choose your password | Cabuyao University' }

// Opened from the acceptance email via /auth/confirm, which creates the session. Without a session
// there is nothing to set a password for, so go to /login.
export default async function SetPasswordPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getUser()
  if (!data.user) redirect('/login')

  return (
    <main className="min-h-dvh bg-background">
      <div className="mx-auto flex min-h-dvh w-full max-w-[420px] flex-col px-5 py-4">
        <header className="flex justify-start">
          <ThemeToggle />
        </header>
        <div className="flex flex-1 flex-col justify-center py-10">
          <div className="mb-8 flex flex-col items-center text-center">
            <CuMark className="w-20" />
            <p className="mt-4 text-2xl font-semibold leading-tight tracking-[-0.01em]">
              <span className="text-accent-foreground">Cabuyao</span> <span className="text-foreground">University</span>
            </p>
            <h1 className="mt-7 text-xl font-semibold text-foreground">Choose your password</h1>
            <p className="mt-1 text-sm text-muted">You will use it with your student ID to sign in to the portal.</p>
          </div>
          <SetPasswordForm />
        </div>
        <footer className="text-xs text-muted">© 2026 Cabuyao University</footer>
      </div>
    </main>
  )
}
