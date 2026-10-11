import Image from 'next/image'
import { cn } from '@/lib/utils'

// The real CU monogram (public/brand, never redrawn): the light file on light ground, the dark file on
// dark ground. Decorative here; the visible name next to it carries the meaning.
export function CuMark({ className }: { className?: string }) {
  return (
    <>
      <Image
        src="/brand/cu-mark-light.svg"
        alt=""
        width={82}
        height={77}
        unoptimized
        loading="eager"
        className={cn('h-auto shrink-0 dark:hidden', className)}
      />
      <Image
        src="/brand/cu-mark-dark.svg"
        alt=""
        width={82}
        height={77}
        unoptimized
        loading="eager"
        className={cn('hidden h-auto shrink-0 dark:block', className)}
      />
    </>
  )
}

// Compact lockup for the sign-in page: mark plus the public name, at body size.
export function CabuyaoLogo({ className }: { className?: string }) {
  return (
    <div className={cn('flex items-center gap-2.5', className)}>
      <CuMark className="w-8" />
      <span className="text-base font-semibold text-foreground">Cabuyao University</span>
    </div>
  )
}

// The monogram, large and very low contrast, bleeding off one edge of the sign-in page.
export function LoginWatermark() {
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute -bottom-24 -right-28 -z-10 hidden w-[560px] opacity-[0.06] md:block dark:opacity-[0.07]"
    >
      <CuMark className="w-full" />
    </div>
  )
}
