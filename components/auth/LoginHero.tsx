import { CheckIcon, ShieldIcon } from './AuthIcons'


const SURFACE = 'rounded-lg border border-[#e5e7eb] bg-white dark:border-[#2c3144] dark:bg-[#181b27]'
const CHIP = 'rounded-full px-2.5 py-1 text-sm font-semibold'
const CHIP_GREEN = `${CHIP} bg-[#ddf6e8] text-[#137337] dark:bg-[#34d399]/[0.18] dark:text-[#6ee7b7]`
const CHIP_AMBER = `${CHIP} bg-[#fff0d6] text-[#a54c08] dark:bg-[#fbbf24]/[0.18] dark:text-[#fcd34d]`
const MUTED = 'text-[#6b7280] dark:text-[#a1a1b5]'
const STRONG = 'text-[#121319] dark:text-white'

const CLEARANCE_SEGMENTS = [true, true, true, false]

// Decorative preview of the portal (static sample data, matches the Figma design).
export function LoginHero() {
  return (
    <aside
      aria-hidden="true"
      className="relative hidden flex-1 flex-col justify-between overflow-hidden rounded-xl border border-transparent bg-[#ebddf6] p-8 lg:flex dark:border-[#2c3144] dark:bg-[#1f2333]"
    >
      <div className="pointer-events-none absolute -bottom-3 -left-3 size-[220px] rounded-xl border border-[#e5e7eb] bg-[#f3e8ff] dark:border-0 dark:bg-[#2a2f42]" />
      <div className="pointer-events-none absolute -right-3 -top-3 size-[140px] rounded-xl border border-[#e5e7eb] bg-[#f3e8ff] dark:border-0 dark:bg-[#2a2f42]" />

      <div className="relative flex flex-col items-start gap-[18px]">
        <span className="flex items-center gap-2 rounded-full border border-[#e5e7eb] bg-[#f3e8ff] px-3.5 py-2 text-sm font-medium text-[#1b1c26] dark:border-[#2c3144] dark:bg-[#181b27] dark:text-[#a1a1b5]">
          <span className="size-2 rounded-full bg-[#1b1c26] dark:bg-[#34d399]" />
          Grades · Clearance · Enrollment
        </span>

        <h2 className={`text-5xl font-extrabold leading-[1.08] tracking-tight xl:text-[54px] ${STRONG}`}>
          Your semester,
          <br />
          <span className="text-[#7e4fb0] dark:text-[#d9b8ee]">at a glance.</span>
        </h2>

        {/* Figma wraps this line at "...from any / device." — so no narrow max-width */}
        <p className="text-base text-[#5e6571] dark:text-[#a1a1b5]">
          See posted grades, track clearance across every office, and stay on top
          of your enrollment — from any device.
        </p>
      </div>

      <div className="relative grid grid-cols-2 gap-4">
        <div className={`${SURFACE} flex flex-col gap-2.5 p-5`}>
          <p className={`text-sm font-medium ${MUTED}`}>Semester GWA</p>
          <div className="flex items-end gap-2.5">
            <p className={`text-[44px] font-extrabold leading-none ${STRONG}`}>1.75</p>
            <span className={CHIP_GREEN}>▲ 0.25</span>
          </div>
          <svg viewBox="0 0 200 56" className="h-14 w-full text-[#1b1c26] dark:text-[#d9b8ee]" fill="none">
            <path
              d="M2 40c20 0 22-6 42-6s22 10 42 4 24-16 44-14 24-6 40-12 20-6 28-6"
              stroke="currentColor"
              strokeWidth="2.5"
              strokeLinecap="round"
            />
            <circle cx="198" cy="6" r="3" fill="currentColor" />
          </svg>
        </div>

        <div className={`${SURFACE} flex flex-col gap-3.5 p-5`}>
          <div className="flex items-center justify-between">
            <p className={`text-sm font-medium ${MUTED}`}>Clearance</p>
            <span className={CHIP_AMBER}>In progress</span>
          </div>
          <p className="flex items-end gap-2 whitespace-nowrap">
            <span className={`text-[40px] font-extrabold leading-none ${STRONG}`}>3 / 4</span>
            <span className={`text-sm ${MUTED}`}>offices cleared</span>
          </p>
          <div className="flex gap-1.5">
            {CLEARANCE_SEGMENTS.map((isCleared, index) => (
              <span
                key={index}
                className={`h-2 flex-1 rounded ${isCleared ? 'bg-[#34d399]' : 'bg-[#e5e7eb] dark:bg-[#2a2f42]'}`}
              />
            ))}
          </div>
          <div className="flex items-center justify-between text-sm font-medium text-[#1b1c26] dark:text-white">
            Cashier&apos;s Office
            <span className={CHIP_GREEN}>Cleared</span>
          </div>
          <div className="flex items-center justify-between text-sm font-medium text-[#1b1c26] dark:text-white">
            CCS Department
            <span className={CHIP_AMBER}>Pending</span>
          </div>
        </div>
      </div>

      <div className="relative flex items-center gap-4">
        <div className={`${SURFACE} flex flex-1 items-center gap-3.5 px-5 py-4`}>
          <span className="flex size-10 items-center justify-center rounded-lg border border-[#e5e7eb] bg-[#ddf6e8] text-[#147a3a] dark:border-[#2c3144] dark:bg-[#34d399] dark:text-[#181b27]">
            <CheckIcon className="size-5" />
          </span>
          <span className="flex flex-1 flex-col text-sm">
            <span className="font-semibold text-[#1b1c26] dark:text-white">New grade posted</span>
            <span className={MUTED}>CS101 · Introduction to Computing</span>
          </span>
          <span className="text-[22px] font-extrabold text-[#147a3a] dark:text-[#6ee7b7]">1.75</span>
        </div>
        <div className={`${SURFACE} flex w-[220px] shrink-0 items-center gap-2 p-4`}>
          <ShieldIcon className="size-4 shrink-0 text-[#1b1c26] dark:text-[#a1a1b5]" />
          <span className="text-sm font-medium text-[#1b1c26] dark:text-[#a1a1b5]">
            Secure, encrypted sign-in
          </span>
        </div>
      </div>
    </aside>
  )
}