import Image from 'next/image'
import { cn } from '@/lib/utils'
import type { Hue } from './hue'
import { PHOTOS, VEIL, type PhotoKey } from './photos'

// Legacy: the new direction has no photo banners (use a plain page heading). Kept working and flat:
// the photo sits on the right from sm up under one even veil (85%), so white text keeps >= 10:1 even
// over a white pixel. No shadow, no gradient, no lit edge.
export function PhotoBanner({
  image,
  title,
  subtitle,
  aside,
  tone = 'violet',
  className,
}: {
  image: PhotoKey
  title: React.ReactNode
  subtitle?: React.ReactNode
  aside?: React.ReactNode
  tone?: Hue
  className?: string
}) {
  const photo = PHOTOS[image]
  const veil = VEIL[tone]

  return (
    <section
      className={cn(
        'relative isolate flex min-h-[112px] flex-col justify-center gap-4 overflow-hidden rounded-lg px-5 py-5 sm:flex-row sm:items-center sm:justify-between sm:px-6',
        className
      )}
      style={{ backgroundColor: veil }}
    >
      <Image
        src={photo.src}
        alt=""
        width={photo.width}
        height={photo.height}
        unoptimized
        loading="eager"
        className="absolute inset-0 -z-10 size-full object-cover sm:left-auto sm:w-1/2"
        style={{ objectPosition: photo.position }}
      />
      <div
        aria-hidden="true"
        className="absolute inset-0 -z-10"
        style={{ background: `color-mix(in srgb, ${veil} 85%, transparent)` }}
      />

      <div className="flex max-w-full flex-col gap-1 sm:max-w-[55%]">
        <h2 className="text-xl font-semibold text-on-veil">{title}</h2>
        {subtitle && <p className="text-sm text-on-veil-muted">{subtitle}</p>}
      </div>
      {aside && <div className="relative shrink-0">{aside}</div>}
    </section>
  )
}
