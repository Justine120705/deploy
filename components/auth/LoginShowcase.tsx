'use client'

import Image from 'next/image'
import { useEffect, useState } from 'react'
import { cn } from '@/lib/utils'

// Photos are the PM's (public/photos); copy is plain product fact, no claims.
const SLIDES = [
  {
    src: '/photos/lecture-hall.jpg',
    alt: 'Students in a lecture hall with laptops',
    title: 'Enrollment, grades and clearance in one place.',
    text: 'Sign in to see where your requests stand and what to do next.',
  },
  {
    src: '/photos/study-desk.jpg',
    alt: 'A laptop, notebook and coffee on a desk',
    title: 'Request documents without lining up.',
    text: 'Track each request from pending to released, from any device.',
  },
] as const

const INTERVAL_MS = 7000

// Photo panel for the sign-in page: a slow crossfade between two photos with real dot controls.
// It pauses while the pointer or keyboard focus is inside, and does not auto-advance at all when the
// visitor prefers reduced motion. Dots are buttons, so the slides can always be changed by hand.
export function LoginShowcase() {
  const [index, setIndex] = useState(0)
  const [paused, setPaused] = useState(false)
  const [reduced, setReduced] = useState(false)

  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => setReduced(query.matches)
    update()
    query.addEventListener('change', update)
    return () => query.removeEventListener('change', update)
  }, [])

  useEffect(() => {
    if (paused || reduced) return
    const id = window.setInterval(() => setIndex((i) => (i + 1) % SLIDES.length), INTERVAL_MS)
    return () => window.clearInterval(id)
  }, [paused, reduced])

  return (
    <aside
      aria-label="About the portal"
      className="relative m-4 hidden overflow-hidden rounded-xl bg-ink lg:block"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocus={() => setPaused(true)}
      onBlur={() => setPaused(false)}
    >
      {SLIDES.map((slide, i) => (
        <Image
          key={slide.src}
          src={slide.src}
          alt={i === index ? slide.alt : ''}
          aria-hidden={i === index ? undefined : true}
          fill
          priority
          sizes="50vw"
          className={cn(
            'object-cover transition-opacity duration-1000 ease-out motion-reduce:transition-none',
            i === index ? 'opacity-100' : 'opacity-0'
          )}
        />
      ))}
      {/* Scrim for the text only: solid at the bottom where the text sits, clear at the top. */}
      <div aria-hidden="true" className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/35 to-transparent" />

      <div className="absolute inset-x-0 bottom-0 flex flex-col gap-6 p-10 text-white">
        <div aria-live={paused || reduced ? 'polite' : 'off'} className="min-h-[7.5rem]">
          <p className="max-w-md text-3xl font-semibold leading-tight tracking-[-0.01em]">{SLIDES[index].title}</p>
          <p className="mt-3 max-w-md text-sm leading-6 text-white/90">{SLIDES[index].text}</p>
        </div>

        <div className="flex items-center gap-1" role="group" aria-label="Choose a photo">
          {SLIDES.map((slide, i) => (
            <button
              key={slide.src}
              type="button"
              onClick={() => setIndex(i)}
              aria-label={`Show photo ${i + 1} of ${SLIDES.length}`}
              aria-current={i === index ? 'true' : undefined}
              className="group flex h-6 w-8 items-center justify-center rounded-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
            >
              <span
                className={cn(
                  'h-1.5 rounded-full transition-all duration-300 motion-reduce:transition-none',
                  i === index ? 'w-6 bg-white' : 'w-1.5 bg-white/55 group-hover:bg-white/80'
                )}
              />
            </button>
          ))}
        </div>
      </div>
    </aside>
  )
}
