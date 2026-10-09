// Inline logo (matches the Figma "Approved logo" light + dark variants).
// No exported SVG files needed in /public — colors switch with the `dark:` variant.
export function CabuyaoLogo({ className = '' }: { className?: string }) {
  return (
    <div
      role="img"
      aria-label="Cabuyao University — Learn, grow, build tomorrow"
      className={`flex items-center gap-3 ${className}`}
    >
      <svg
        aria-hidden="true"
        viewBox="0 0 80 92"
        className="h-[88px] w-auto shrink-0"
        fill="none"
      >
        {/* hexagon body */}
        <path
          d="M40 0 80 23v46L40 92 0 69V23z"
          className="fill-[#1b1c26] dark:fill-white"
        />
        {/* purple top face */}
        <path d="M40 0 80 23 40 46 0 23z" className="fill-[#b78ae6] dark:fill-[#c9a0e3]" />
        {/* U-shaped cut-out */}
        <path
          d="M24 40v22l16 10 16-10V40"
          strokeWidth="8"
          strokeLinejoin="round"
          className="stroke-white dark:stroke-[#181b27]"
        />
      </svg>

      <div aria-hidden="true" className="flex flex-col">
        <span className="text-4xl font-extrabold leading-[1.05] tracking-tight text-[#121319] dark:text-white">
          Cabuyao
        </span>
        <span className="text-4xl font-extrabold leading-[1.05] tracking-tight text-[#7e4fb0] dark:text-[#d9b8ee]">
          University
        </span>
        <span className="mt-1 text-[10px] font-medium uppercase tracking-[0.14em] text-[#6e6c85] dark:text-[#a1a1b5]">
          Learn · Grow · Build tomorrow
        </span>
      </div>
    </div>
  )
}