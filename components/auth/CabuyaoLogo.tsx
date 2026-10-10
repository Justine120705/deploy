// Inline logo (matches the Figma "Approved logo" light + dark variants).
// No exported SVG files needed in /public. Colors follow the theme tokens.
const SIZES = {
  md: { mark: 'h-[88px]', name: 'text-4xl', tagline: 'text-[10px]' },
  lg: { mark: 'h-[88px] sm:h-[124px]', name: 'text-[38px] sm:text-[54px]', tagline: 'text-[10px] sm:text-xs' },
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
      className={`flex items-center gap-4 ${className}`}
    >
      <svg aria-hidden="true" viewBox="0 0 80 92" className={`${s.mark} w-auto shrink-0`} fill="none">
        {/* hexagon body */}
        <path d="M40 0 80 23v46L40 92 0 69V23z" className="fill-foreground" />
        {/* purple top face */}
        <path d="M40 0 80 23 40 46 0 23z" className="fill-[#b78ae6] dark:fill-[#c9a0e3]" />
        {/* U-shaped cut-out */}
        <path
          d="M24 40v22l16 10 16-10V40"
          strokeWidth="8"
          strokeLinejoin="round"
          className="stroke-card"
        />
      </svg>

      <div aria-hidden="true" className="flex flex-col">
        <span className={`${s.name} font-extrabold leading-[1.02] tracking-tight text-foreground`}>
          Cabuyao
        </span>
        <span className={`${s.name} font-extrabold leading-[1.02] tracking-tight text-accent-foreground`}>
          University
        </span>
        <span className={`mt-1.5 ${s.tagline} font-medium uppercase tracking-[0.14em] text-muted`}>
          Learn · Grow · Build tomorrow
        </span>
      </div>
    </div>
  )
}
