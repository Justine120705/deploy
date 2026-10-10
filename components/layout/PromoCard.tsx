import Image from 'next/image'
import { PHOTOS, VEIL, type PhotoKey } from '@/components/ui/photos'

// Sidebar card: a big number, what it counts and an encouraging line. Pass it to DashboardShell's
// `promo` prop; roles without one simply leave it out.
//
// With `image` it is a photo card: the photo under a deep violet veil that is light at the top (the
// subject shows) and >= 88% from the middle down, where the text sits (white >= 11:1, lilac note
// >= 8:1 even over a white pixel). It is raised above the sidebar (level 2 on a level 1 rail,
// docs/design/depth.md). Without `image` it keeps the soft violet-to-sky wash.
export default function PromoCard({
  value,
  label,
  note,
  image,
}: {
  value: React.ReactNode
  label: string
  note?: string
  image?: PhotoKey
}) {
  if (image) {
    const photo = PHOTOS[image]
    const veil = VEIL.violet
    const mix = (p: number) => `color-mix(in srgb, ${veil} ${p}%, transparent)`
    return (
      <div className="relative isolate flex min-h-[188px] flex-col justify-end gap-0.5 overflow-hidden rounded-xl p-4 shadow-elev-md">
        <Image
          src={photo.src}
          alt=""
          width={photo.width}
          height={photo.height}
          unoptimized
          loading="eager"
          className="absolute inset-0 -z-10 size-full object-cover"
          style={{ objectPosition: photo.position }}
        />
        <div
          aria-hidden="true"
          className="absolute inset-0 -z-10"
          style={{ background: `linear-gradient(180deg, ${mix(15)} 0%, ${mix(88)} 48%, ${veil} 100%)` }}
        />
        <div aria-hidden="true" className="pointer-events-none absolute inset-0 rounded-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.14)]" />
        <p className="text-3xl font-extrabold leading-tight text-on-veil">{value}</p>
        <p className="text-sm font-medium text-on-veil">{label}</p>
        {note && <p className="text-sm font-semibold text-on-veil-muted">{note}</p>}
      </div>
    )
  }

  return (
    <div className="flex flex-col items-center gap-2 rounded-xl bg-linear-160 from-hue-violet-soft to-hue-sky-soft p-4 text-center shadow-elev-sm">
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
      <p className="text-3xl font-extrabold leading-tight text-hue-violet-strong">{value}</p>
      <p className="text-sm font-medium text-foreground">{label}</p>
      {note && <p className="text-sm font-semibold text-hue-sky-strong">{note}</p>}
    </div>
  )
}
