import Image from 'next/image'

// Cabuyao University lockup from the Figma file ("Approved logo / Light" and "/ Dark").
// The CU monogram is Figma's own vector (public/brand), shown at the lockup's 82 x 76.6 size
// and scaled up on the login page. Brand colors are fixed on purpose, as in the design.
const SIZES = {
  md: {
    gap: 'gap-[18px]',
    mark: 'w-[82px]',
    name: 'text-[36px] leading-[38px] tracking-[-0.36px]',
    university: 'text-[32.89px] leading-[30px] tracking-[-0.3289px]',
    tagline: 'text-[10px] leading-4 tracking-[1.2px]',
  },
  lg: {
    gap: 'gap-[18px] sm:gap-6',
    mark: 'w-[82px] sm:w-[123px]',
    name: 'text-[36px] leading-[38px] tracking-[-0.36px] sm:text-[54px] sm:leading-[57px] sm:tracking-[-0.54px]',
    university:
      'text-[32.89px] leading-[30px] tracking-[-0.3289px] sm:text-[49.3px] sm:leading-[45px] sm:tracking-[-0.49px]',
    tagline: 'text-[10px] leading-4 tracking-[1.2px] sm:text-[13px] sm:leading-5 sm:tracking-[1.8px]',
  },
} as const

export function CabuyaoLogo({
  className = '',
  size = 'md',
}: {
  className?: string
  size?: keyof typeof SIZES
}) {
  const s = SIZES[size]
  return (
    <div
      role="img"
      aria-label="Cabuyao University: Learn, grow, build tomorrow"
      className={`flex items-center ${s.gap} ${className}`}
    >
      <Image
        src="/brand/cu-mark-light.svg"
        alt=""
        width={82}
        height={77}
        unoptimized
        loading="eager"
        className={`${s.mark} h-auto shrink-0 dark:hidden`}
      />
      <Image
        src="/brand/cu-mark-dark.svg"
        alt=""
        width={82}
        height={77}
        unoptimized
        loading="eager"
        className={`${s.mark} hidden h-auto shrink-0 dark:block`}
      />

      <div aria-hidden="true" className="flex flex-col whitespace-nowrap">
        <span className={`${s.name} font-extrabold text-[#121319] dark:text-white`}>Cabuyao</span>
        <span className={`${s.university} font-extrabold text-[#7e4fb0] dark:text-[#d9b8ee]`}>
          University
        </span>
        <span className={`${s.tagline} font-medium uppercase text-[#6e6c85] dark:text-[#a1a1b5]`}>
          Learn · Grow · Build tomorrow
        </span>
      </div>
    </div>
  )
}
