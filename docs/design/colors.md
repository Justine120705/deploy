# Color system

The portal stays calm and lilac. Color is added through one family of five hues that share the brand
purple's lightness and chroma, so they read as one set. Tokens live in `app/globals.css` (light in
`:root`, dark in `:root[data-theme='dark']`) and are registered for Tailwind, so `bg-hue-sky-soft`,
`text-hue-sky-strong` and `bg-hue-sky-solid` work. Class maps for code: `components/ui/hue.ts`.

## Tiers

Every hue has three tokens, built in OKLCH with the same lightness and chroma per tier:

| Tier | Light (OKLCH L / C) | Dark (OKLCH L / C) | Use |
| --- | --- | --- | --- |
| `-soft` | 0.955 / 0.03 | 0.25 / 0.05 | Tinted background: chips, icon tiles, event days, badges |
| `-strong` | 0.515 / 0.13 (violet = brand #7e4fb0) | 0.85 / 0.09 | Text and icons on the soft tint, a card or the page |
| `-solid` | 0.615 / 0.135 | 0.72 / 0.115 | Chart marks, bars, dots, accent bars |

## Palette

| Token | Light | Dark | Intended use |
| --- | --- | --- | --- |
| `--hue-violet-soft` | #f4ecff | #271b35 | Grades and academics; brand. Also `--accent` |
| `--hue-violet-strong` | #7e4fb0 | #dac0fe | Also `--accent-foreground` |
| `--hue-violet-solid` | #976ec6 | #b492df | |
| `--hue-sky-soft` | #e2f3fe | #032536 | Enrollment, schedule, classes |
| `--hue-sky-strong` | #03709e | #96d7ff | |
| `--hue-sky-solid` | #078fc8 | #53afe3 | |
| `--hue-teal-soft` | #dbf8eb | #02291c | Clearance, done, good. Also `--success-soft`, `--tint-green` |
| `--hue-teal-strong` | #037a59 | #93e1c0 | Also `--success` |
| `--hue-teal-solid` | #049c73 | #51bb94 | Also `--chart-green`, `--dot-green` |
| `--hue-amber-soft` | #feefdd | #331f04 | Pending, fees, deadlines. Also `--warning-soft`, `--tint-amber` |
| `--hue-amber-strong` | #8d5b04 | #f3c58c | Also `--warning` |
| `--hue-amber-solid` | #bc7b00 | #e0a454 | Also `--dot-amber` |
| `--hue-rose-soft` | #ffebec | #36171a | Holds, exams, problems. Also `--danger-soft`, `--tint-rose` |
| `--hue-rose-strong` | #a44250 | #ffb8bd | Also `--danger` |
| `--hue-rose-solid` | #c85e6c | #e3858f | Also `--dot-rose` |
| `--ring` | #976ec6 | #c9a0e3 | Focus outline (`outline-ring`); `outline-lilac` is only 2.2:1 on white |

All older token names still work; the status, tint, dot and chart-green tokens now point at the family.

## Rules

1. **Hue follows the topic, the same on every screen**: violet = grades, sky = enrollment and
   schedule, teal = clearance and anything done, amber = pending, fees and deadlines, rose = holds,
   exams and problems. Status keeps its meaning: green (teal) good, amber attention, rose problem.
2. **One topic hue per card**, plus status colors where a status is shown. Never more than two hues
   in one card (the clearance gauge is teal + amber because it shows cleared vs pending).
3. **Categories without status meaning** (for example one color per course) use violet, sky and teal
   only. Amber and rose are reserved for attention and problems.
4. **Text on a soft tint is `-strong` or `foreground`**, never `muted` (muted is 4.4:1 on the light
   tints). Solid is for marks, not for text.
5. **Color is never alone**: chips keep their words, calendar events keep their titles (and a dot),
   charts have a text label or tooltip for the value that matters.
6. **One memorable moment per screen**. On the student dashboard it is the Progress chart (violet
   line, fading violet area, the best term pinned). The shell (sidebar, top bar, page) stays neutral.
7. Gradients only between two soft tints (the sidebar promo card) or as a chart area fill.

## Contrast (WCAG 2.x)

Targets: 4.5:1 for text, 3:1 for chart marks, dots and focus rings. Card is #ffffff / #0d0b14,
background #f5f3fa / #000000. All pairs pass.

| Hue | Pair | Target | Light | Dark |
| --- | --- | --- | --- | --- |
| violet | strong on soft / card / page | 4.5 | 5.03 / 5.78 / 5.25 | 10.01 / 12.05 / 12.95 |
| violet | solid vs card / page / soft | 3 | 3.92 / 3.56 / 3.41 | 7.55 / 8.12 / 6.27 |
| sky | strong on soft / card / page | 4.5 | 4.85 / 5.50 / 5.00 | 10.18 / 12.52 / 13.46 |
| sky | solid vs card / page / soft | 3 | 3.64 / 3.31 / 3.20 | 8.01 / 8.61 / 6.51 |
| teal | strong on soft / card / page | 4.5 | 4.74 / 5.34 / 4.85 | 10.30 / 12.81 / 13.77 |
| teal | solid vs card / page / soft | 3 | 3.50 / 3.18 / 3.10 | 8.27 / 8.89 / 6.65 |
| amber | strong on soft / card / page | 4.5 | 5.12 / 5.78 / 5.26 | 9.84 / 12.26 / 13.18 |
| amber | solid vs card / page / soft | 3 | 3.52 / 3.20 / 3.12 | 8.94 / 9.61 / 7.18 |
| rose | strong on soft / card / page | 4.5 | 5.28 / 6.05 / 5.49 | 9.92 / 11.95 / 12.84 |
| rose | solid vs card / page / soft | 3 | 3.98 / 3.62 / 3.48 | 7.46 / 8.02 / 6.19 |
| all | foreground on any soft | 4.5 | 13.38 to 13.64 | 14.22 to 14.70 |
| | `--ring` vs card / page | 3 | 3.92 / 3.56 | 8.95 / 9.62 |
| | promo: sky-strong on violet-soft, violet-strong on sky-soft | 4.5 | 4.79 / 5.09 | 10.40 / 9.80 |

Known gap outside this system: `outline-lilac` (#c9a0e3) is 2.2:1 on white. The student dashboard and
the shell use `outline-ring`; other screens should switch when they are rebuilt.
