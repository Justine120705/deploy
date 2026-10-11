// The five hues of the color system (app/globals.css, docs/design/colors.md). Use these maps instead
// of building class names from strings, so Tailwind can see every class at build time.
//
// Topic hues (keep them the same on every screen):
//   violet = grades and academics (brand)   sky   = enrollment, schedule, classes
//   teal   = clearance, done, good           amber = pending, fees, deadlines
//   rose   = holds, exams, problems
export type Hue = 'violet' | 'sky' | 'teal' | 'amber' | 'rose'

/** Soft tinted background. */
export const HUE_SOFT: Record<Hue, string> = {
  violet: 'bg-hue-violet-soft',
  sky: 'bg-hue-sky-soft',
  teal: 'bg-hue-teal-soft',
  amber: 'bg-hue-amber-soft',
  rose: 'bg-hue-rose-soft',
}

/** Text and icons; readable on the soft tint, on cards and on the page. */
export const HUE_TEXT: Record<Hue, string> = {
  violet: 'text-hue-violet-strong',
  sky: 'text-hue-sky-strong',
  teal: 'text-hue-teal-strong',
  amber: 'text-hue-amber-strong',
  rose: 'text-hue-rose-strong',
}

/** Solid fill for dots, bars and small marks. */
export const HUE_SOLID: Record<Hue, string> = {
  violet: 'bg-hue-violet-solid',
  sky: 'bg-hue-sky-solid',
  teal: 'bg-hue-teal-solid',
  amber: 'bg-hue-amber-solid',
  rose: 'bg-hue-rose-solid',
}

/** CSS value of a hue token, for SVG strokes and inline styles. */
export const hueVar = (hue: Hue, tier: 'soft' | 'strong' | 'solid') => `var(--hue-${hue}-${tier})`
