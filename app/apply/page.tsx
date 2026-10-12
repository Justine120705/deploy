import type { Metadata } from 'next'
import Image from 'next/image'
import Link from 'next/link'
import { ApplyFooter, ApplyHeader } from './ApplyChrome'

export const metadata: Metadata = {
  title: 'Enrollment | Cabuyao University',
  description: 'Enroll at Cabuyao University for A.Y. 2026-2027.',
}

const CTA =
  'inline-flex h-12 items-center justify-center rounded-full px-8 text-base font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring max-lg:h-12'

const STEPS = [
  { title: 'Fill in the form', text: 'Your name, email and the program you want. It takes about a minute.' },
  { title: 'The Registrar reviews it', text: 'A Registrar checks your application.' },
  {
    title: 'Get your student ID',
    text: 'If it is accepted, we email your student ID and a link to set your password. Then you sign in with your student ID.',
  },
] as const

// Public enrollment landing page for new applicants. No sign-in and no data: the form lives at /apply/enroll.
// After the form is sent, /apply?notice=submitted shows the confirmation in place of the landing.
export default async function ApplyPage({ searchParams }: { searchParams: Promise<{ notice?: string }> }) {
  const { notice } = await searchParams

  return (
    <div className="min-h-dvh">
      <ApplyHeader />
      <main>{notice === 'submitted' ? <Received /> : <Landing />}</main>
      <ApplyFooter />
    </div>
  )
}

function Landing() {
  return (
    <>
      <section aria-labelledby="hero-title" className="mx-auto grid w-full max-w-6xl items-center gap-8 px-5 pb-10 pt-4 sm:px-8 lg:grid-cols-[1.05fr_1fr] lg:gap-14 lg:pb-16 lg:pt-8">
        <div className="relative aspect-[4/3] w-full overflow-hidden rounded-3xl border border-edge shadow-elev-md">
          <Image
            src="/photos/campus-yellow-building.jpg"
            alt="A school building with a wide green field in front"
            fill
            priority
            sizes="(min-width: 1024px) 560px, 100vw"
            className="object-cover"
          />
          <div aria-hidden="true" className="absolute inset-x-0 bottom-0 h-1/3 bg-gradient-to-t from-black/30 to-transparent" />
          <span className="absolute bottom-4 left-4 inline-flex h-9 items-center rounded-full bg-gold px-4 text-sm font-semibold text-[#18181b]">
            A.Y. 2026-2027
          </span>
        </div>

        <div className="flex flex-col items-start">
          <h1
            id="hero-title"
            className="text-[clamp(2.25rem,5.2vw,3.75rem)] font-bold leading-[1.05] tracking-[-0.03em] text-foreground"
          >
            Enrollment
            <span className="mt-2 block w-fit rounded-2xl bg-gold px-4 py-1 text-[#18181b]">now ongoing!</span>
          </h1>
          <p className="mt-5 text-lg font-semibold text-foreground">For A.Y. 2026-2027</p>
          <p className="mt-2 max-w-[44ch] text-base leading-7 text-muted">
            Apply online and skip the line. No need to visit an office to start your enrollment.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link href="/apply/enroll" className={`${CTA} bg-primary text-primary-foreground hover:bg-primary-hover`}>
              Enroll now
            </Link>
            <Link
              href="/login"
              className={`${CTA} glass border border-field-border/60 bg-card text-foreground hover:border-field-border hover:bg-card-raised`}
            >
              I already have an account
            </Link>
          </div>
        </div>
      </section>

      <section aria-labelledby="steps-title" className="mx-auto w-full max-w-6xl px-5 pb-12 sm:px-8">
        <div className="glass rounded-3xl border border-edge bg-card p-6 shadow-elev-sm sm:p-8">
          <h2 id="steps-title" className="text-xl font-semibold">
            How enrollment works
          </h2>
          <ol className="mt-6 grid gap-6 md:grid-cols-3 md:gap-8">
            {STEPS.map((step, i) => (
              <li key={step.title} className="flex gap-4">
                <span
                  aria-hidden="true"
                  className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary text-sm font-semibold text-primary-foreground"
                >
                  {i + 1}
                </span>
                <div>
                  <h3 className="text-base font-semibold">{step.title}</h3>
                  <p className="mt-1 text-sm leading-6 text-muted">{step.text}</p>
                </div>
              </li>
            ))}
          </ol>
          <p className="mt-8 max-w-[75ch] border-t border-border pt-5 text-sm leading-6 text-muted">
            <span className="font-semibold text-foreground">Your data.</span> We collect only what we need: your name and email to review
            your application and contact you, your mobile number (optional) in case the Registrar needs to reach you, and the program you
            choose. It is used for enrollment only, as the Data Privacy Act requires.
          </p>
        </div>
      </section>
    </>
  )
}

function Received() {
  return (
    <section aria-labelledby="done-title" className="mx-auto flex w-full max-w-xl flex-col px-5 pb-16 pt-10 sm:px-8">
      <div className="glass rounded-3xl border border-warm-edge bg-warm-glass p-8 text-center shadow-elev-md">
        <span aria-hidden="true" className="mx-auto flex size-14 items-center justify-center rounded-full bg-gold text-[#18181b]">
          <svg viewBox="0 0 24 24" fill="none" className="size-7">
            <path d="m5 12.5 4.5 4.5L19 7.5" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
        <h1 id="done-title" className="mt-5 text-2xl font-semibold">
          Application received
        </h1>
        <p className="mt-3 text-sm leading-6 text-muted">
          Thank you. The Registrar will review your application. If it is accepted, you will receive an email with your student ID and a
          link to set your password. Please check your inbox, and your spam folder, in the coming days.
        </p>
        <div className="mt-6 flex flex-wrap justify-center gap-3">
          <Link href="/login" className={`${CTA} bg-primary text-primary-foreground hover:bg-primary-hover`}>
            Go to sign in
          </Link>
          <Link
            href="/apply"
            className={`${CTA} glass border border-field-border/60 bg-card text-foreground hover:border-field-border hover:bg-card-raised`}
          >
            Back to enrollment
          </Link>
        </div>
      </div>
    </section>
  )
}
