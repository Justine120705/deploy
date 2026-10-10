import Image from 'next/image'
import { cn } from '@/lib/utils'
import type { Hue } from './hue'
import { PHOTOS, VEIL, type PhotoKey } from './photos'

const mix = (color: string, percent: number) => `color-mix(in srgb, ${color} ${percent}%, transparent)`

// Top-of-page banner: one of the PM's photos under a deep veil of the hue, white title and subtitle on
// the left, optional `aside` (for example a link) on the right. The highest surface on a page (level 3,
// docs/design/depth.md). No animation.
//
// The photo only fills the right ~64% from sm up, so the small source images are never stretched
// across a wide card; the left side is solid veil where the text sits. The veil stays at >= 90%
// wherever text can be (>= 85% on phones, where the photo is behind everything), so white text keeps
// >= 10:1 and the subtitle >= 7.9:1 even over a white pixel (docs/design/depth.md).
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
        'relative isolate flex min-h-[128px] flex-col justify-center gap-4 overflow-hidden rounded-2xl px-6 py-5 shadow-elev-lg sm:flex-row sm:items-center sm:justify-between sm:px-7',
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
        className="absolute inset-0 -z-10 size-full object-cover sm:left-auto sm:w-[64%]"
        style={{ objectPosition: photo.position }}
      />
      {/* Phones: the photo is behind the text, so the veil is even. */}
      <div aria-hidden="true" className="absolute inset-0 -z-10 sm:hidden" style={{ background: mix(veil, 85) }} />
      {/* sm and up: solid where the text is, opening up to the photo on the right. */}
      <div
        aria-hidden="true"
        className="absolute inset-0 -z-10 hidden sm:block"
        style={{
          background: `linear-gradient(90deg, ${veil} 0%, ${veil} 36%, ${mix(veil, 90)} 52%, ${mix(veil, 62)} 72%, ${mix(veil, 22)} 100%)`,
        }}
      />
      {/* Lit top edge, the same cue the dark cards use; gives the photo surface a physical edge. */}
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 rounded-2xl shadow-[inset_0_1px_0_rgb(255_255_255/0.12)]" />

      <div className="flex max-w-full flex-col gap-1 sm:max-w-[50%]">
        <h2 className="text-2xl font-extrabold leading-tight tracking-tight text-on-veil">{title}</h2>
        {subtitle && <p className="text-sm font-medium text-on-veil-muted">{subtitle}</p>}
      </div>
      {aside && <div className="relative shrink-0">{aside}</div>}
    </section>
  )
}
