import type { Hue } from './hue'

// The PM's photos (public/photos). Each one is about 736 px wide, so show it only as a crop or under a
// veil, never stretched across a wide screen. `position` keeps the subject in a short, wide crop.
// campus-building.jpg is left out on purpose: it is a real campus that is not Cabuyao University.
export const PHOTOS = {
  'study-desk': { src: '/photos/study-desk.jpg', width: 736, height: 981, position: '50% 42%' }, // notebook, pen, glasses
  'graduation-cap-books': { src: '/photos/graduation-cap-books.jpg', width: 470, height: 626, position: '60% 30%' }, // cap and tassel
  'lecture-hall': { src: '/photos/lecture-hall.jpg', width: 736, height: 981, position: '50% 50%' },
} as const

export type PhotoKey = keyof typeof PHOTOS

/** Deep veil color per hue (app/globals.css --veil-*). White text on it is >= 10:1 even over a white pixel at 85%. */
export const VEIL: Record<Hue, string> = {
  violet: 'var(--veil-violet)',
  sky: 'var(--veil-sky)',
  teal: 'var(--veil-teal)',
  amber: 'var(--veil-amber)',
  rose: 'var(--veil-rose)',
}
