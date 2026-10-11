import Image from 'next/image'
import { cn } from '@/lib/utils'
import type { Hue } from './hue'
import { PHOTOS, VEIL, type PhotoKey } from './photos'

// Photo banner (used on the student dashboard). The photo fills the right side and dissolves into the
// veil colour toward the left through a mask, so there is no hard edge. Under one even veil (75%) white
// text keeps >= 6:1 even over a white pixel; on the left, where the text sits, the photo has already
// faded to nothing.
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
        className="absolute inset-y-0 right-0 -z-10 h-full w-full object-cover sm:w-[72%]"
        style={{
          objectPosition: photo.position,
          maskImage: 'linear-gradient(to right, transparent 0%, rgb(0 0 0 / 0.55) 35%, #000 75%)',
          WebkitMaskImage: 'linear-gradient(to right, transparent 0%, rgb(0 0 0 / 0.55) 35%, #000 75%)',
        }}
      />
      <div
        aria-hidden="true"
        className="absolute inset-0 -z-10"
        style={{ background: `color-mix(in srgb, ${veil} 75%, transparent)` }}
      />

      <div className="flex max-w-full flex-col gap-1 sm:max-w-[55%]">
        <h2 className="text-xl font-semibold text-on-veil">{title}</h2>
        {subtitle && <p className="text-sm text-on-veil-muted">{subtitle}</p>}
      </div>
      {aside && <div className="relative shrink-0">{aside}</div>}
    </section>
  )
}
