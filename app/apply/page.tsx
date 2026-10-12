import type { Metadata } from 'next'
import Link from 'next/link'
import { CuMark } from '@/components/auth/CabuyaoLogo'
import { ThemeToggle } from '@/components/ui/ThemeToggle'
import { ApplyForm } from './ApplyForm'
import { listPrograms } from './programs'

export const metadata: Metadata = {
  title: 'Apply for enrollment | Cabuyao University',
  description: 'Apply to enroll at Cabuyao University.',
}

// Public enrollment site for new applicants. No sign-in; the page only talks to the database through
// two rpcs that anon may call (list_programs, submit_application).
export default async function ApplyPage({ searchParams }: { searchParams: Promise<{ notice?: string }> }) {
  const { notice } = await searchParams
  const submitted = notice === 'submitted'
  const programs = submitted ? [] : await listPrograms()

  return (
    <main className="min-h-dvh bg-background">
      <div className="mx-auto flex min-h-dvh w-full max-w-xl flex-col px-5 py-4 sm:px-8">
        <header className="flex items-center justify-between">
          <ThemeToggle />
          <Link href="/login" className="text-sm font-medium text-accent-foreground underline-offset-4 hover:underline">
            Back to sign in
          </Link>
        </header>

        <div className="flex-1 py-8">
          <div className="mb-8 flex flex-col items-center text-center">
            <CuMark className="w-20" />
            <p className="mt-4 text-2xl font-semibold leading-tight tracking-[-0.01em]">
              <span className="text-accent-foreground">Cabuyao</span> <span className="text-foreground">University</span>
            </p>
            <p className="mt-1 text-sm font-medium tracking-wide text-muted">Enrollment</p>
          </div>

          {submitted ? (
            <section aria-labelledby="done-title" className="rounded-lg border border-border bg-card p-6">
              <h1 id="done-title" className="text-xl font-semibold text-foreground">
                Application received
              </h1>
              <p className="mt-2 text-sm leading-6 text-muted">
                Thank you. The Registrar will review your application. If it is accepted, you will receive an email with your
                student ID and a link to set your password. Please check your inbox, and your spam folder, in the coming days.
              </p>
              <Link href="/login" className="mt-5 inline-block text-sm font-medium text-accent-foreground underline-offset-4 hover:underline">
                Go to sign in
              </Link>
            </section>
          ) : (
            <>
              <h1 className="text-xl font-semibold text-foreground">Apply for enrollment</h1>
              <p className="mt-1 text-sm text-muted">For new students. It takes about a minute.</p>

              <div className="mt-6 rounded-lg border border-border bg-card p-5 sm:p-6">
                <ApplyForm programs={programs} />
              </div>

              <section aria-labelledby="next-title" className="mt-6 text-sm leading-6 text-muted">
                <h2 id="next-title" className="font-semibold text-foreground">
                  What happens next
                </h2>
                <p className="mt-1">
                  The Registrar reviews your application. If it is accepted, you will receive an email with your student ID and a
                  link to set your password. After that, you sign in to the student portal with your student ID.
                </p>
                <h2 className="mt-4 font-semibold text-foreground">Your data</h2>
                <p className="mt-1">
                  We collect only what we need: your name and email to review your application and contact you, your mobile number
                  (optional) in case the Registrar needs to reach you, and the program you choose. It is used for enrollment only,
                  as the Data Privacy Act requires.
                </p>
              </section>
            </>
          )}
        </div>

        <footer className="text-xs text-muted">© 2026 Cabuyao University</footer>
      </div>
    </main>
  )
}
