import Image from 'next/image'

// Sidebar card: a big number, what it counts and an encouraging line, on a soft violet-to-sky wash
// (the only gradient in the shell; both ends are soft tints, so text keeps its contrast). Pass it to DashboardShell's `promo` prop; roles without one simply leave it out.
export default function PromoCard({
  value,
  label,
  note,
}: {
  value: React.ReactNode
  label: string
  note?: string
}) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-lg bg-linear-160 from-hue-violet-soft to-hue-sky-soft p-4 text-center">
      <div className="flex size-24 items-center justify-center bg-card">
        <Image
          src="/figma/art/promo-cu.svg"
          alt=""
          aria-hidden="true"
          width={64}
          height={60}
          unoptimized
          className="h-auto w-16 dark:hidden"
        />
        <Image
          src="/brand/cu-mark-dark.svg"
          alt=""
          aria-hidden="true"
          width={82}
          height={77}
          unoptimized
          className="hidden h-auto w-16 dark:block"
        />
      </div>
      <p className="text-[28px] font-extrabold leading-tight text-hue-violet-strong">{value}</p>
      <p className="text-sm font-medium text-foreground">{label}</p>
      {note && <p className="text-sm font-semibold text-hue-sky-strong">{note}</p>}
    </div>
  )
}
