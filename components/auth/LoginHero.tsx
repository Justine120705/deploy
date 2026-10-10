import { CheckIcon } from './AuthIcons'

// Decorative preview of the portal (static sample data, same offices as the Figma design).
const OFFICES = [
  { name: "Cashier's Office", note: 'Completed', done: true },
  { name: 'CBA Department', note: 'Completed', done: true },
  { name: 'CAS Department', note: 'Completed', done: true },
  { name: 'CCS Department', note: 'Awaiting review', done: false },
]

const CLEARED = OFFICES.filter((office) => office.done).length

export function LoginHero() {
  return (
    <aside aria-hidden="true" className="relative hidden flex-1 items-center lg:flex">
      <div className="w-full max-w-xl py-12">
        <h2 className="text-5xl font-extrabold leading-[1.06] tracking-tight text-foreground xl:text-[60px]">
          Know where your semester stands.
        </h2>
        <p className="mt-5 max-w-md text-lg leading-relaxed text-muted">
          Grades, clearance and enrollment in one place, ready on any device.
        </p>

        <div className="mt-12 rounded-2xl border border-border bg-card p-7 shadow-xl shadow-black/5">
          <div className="flex items-baseline justify-between gap-4">
            <p className="text-base font-bold text-foreground">Clearance</p>
            <p className="text-sm font-medium text-muted">
              <span className="text-2xl font-extrabold text-foreground">{CLEARED}</span> of{' '}
              {OFFICES.length} offices cleared
            </p>
          </div>

          <ol className="relative mt-6 flex flex-col gap-6">
            {/* progress line: solid up to the last cleared office, faint after it */}
            <span
              className="absolute left-[15px] top-4 bottom-4 w-0.5 rounded-full"
              style={{
                background: `linear-gradient(to bottom, var(--success) 0 ${
                  ((CLEARED - 1) / (OFFICES.length - 1)) * 100
                }%, var(--border) ${((CLEARED - 1) / (OFFICES.length - 1)) * 100}% 100%)`,
              }}
            />
            {OFFICES.map((office) => (
              <li key={office.name} className="relative flex items-center gap-4">
                {office.done ? (
                  <span className="relative flex size-8 shrink-0 items-center justify-center rounded-full bg-success-soft text-success ring-4 ring-card">
                    <CheckIcon className="size-4" />
                  </span>
                ) : (
                  <span className="relative flex size-8 shrink-0 items-center justify-center rounded-full bg-warning-soft ring-4 ring-card">
                    <span className="login-pulse absolute size-3 rounded-full bg-warning" />
                    <span className="relative size-3 rounded-full bg-warning" />
                  </span>
                )}
                <span className="flex flex-1 flex-col leading-tight">
                  <span className="text-[15px] font-semibold text-foreground">{office.name}</span>
                  <span className="text-sm text-muted">{office.note}</span>
                </span>
                <span
                  className={`rounded-full px-2.5 py-1 text-sm font-semibold ${
                    office.done ? 'bg-success-soft text-success' : 'bg-warning-soft text-warning'
                  }`}
                >
                  {office.done ? 'Cleared' : 'Pending'}
                </span>
              </li>
            ))}
          </ol>
        </div>
      </div>
    </aside>
  )
}
