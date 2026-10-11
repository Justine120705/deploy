import Image from 'next/image'

// Photo panel for the sign-in page (from lg up): one photo inside a large circle that bleeds off the
// right edge, a thin ring just outside it, and a lavender tint that is deepest at the bottom where the
// text sits. The photo is the PM's (public/photos); the copy is plain product fact, no claims.
export function LoginShowcase() {
  return (
    <aside aria-label="About the portal" className="relative hidden overflow-hidden lg:block">
      <div className="absolute left-[6%] top-1/2 aspect-square w-[min(56vw,96vh)] -translate-y-1/2">
        <div aria-hidden="true" className="absolute -inset-5 rounded-full border border-hue-violet-solid/30" />
        <div className="absolute inset-0 overflow-hidden rounded-full bg-ink">
          <Image
            src="/photos/lecture-hall.jpg"
            alt="Students in a lecture hall with laptops"
            fill
            priority
            sizes="50vw"
            className="object-cover"
          />
          <div
            aria-hidden="true"
            className="absolute inset-0"
            style={{
              background:
                'linear-gradient(to top, color-mix(in srgb, var(--veil-violet) 94%, transparent), color-mix(in srgb, var(--veil-violet) 62%, transparent) 55%, color-mix(in srgb, var(--veil-violet) 38%, transparent))',
            }}
          />
          <div className="absolute inset-x-0 bottom-0 pb-[16%] pl-[16%] pr-[26%] text-white">
            <p className="text-3xl font-semibold leading-tight tracking-[-0.01em]">
              Enrollment, grades and clearance in one place.
            </p>
            <p className="mt-3 text-sm leading-6 text-white/90">
              Sign in to see where your requests stand and what to do next.
            </p>
          </div>
        </div>
      </div>
    </aside>
  )
}
