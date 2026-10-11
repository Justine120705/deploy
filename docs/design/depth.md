# Depth

Direction "soft depth": the Figma layout and palette stay, surfaces get real height. Tokens live in
`app/globals.css`; use the Tailwind names, never raw shadows.

## Levels

| Level | Utility | What sits here |
| --- | --- | --- |
| 0 page | none | `bg-background` |
| 1 chrome | `shadow-elev-xs` | sidebar (desktop), top bar. Low on purpose, so content floats above it |
| 2 content | `shadow-elev-sm` | every `Card` (default `elevation="base"`), `Table` wrapper, promo card inside the sidebar (`shadow-elev-md`, one step above its rail) |
| 3 feature | `shadow-elev-md` / `shadow-elev-lg` | `Card elevation="raised"` (`bg-card-raised`), Next lesson block, interactive card on hover, `PhotoBanner` and the mobile drawer (`lg`) |

One `lg` surface per screen: the photo banner. Do not give ordinary cards `md` or `lg`; the
difference between levels is the hierarchy.

## Values

| Token | Light (shadow tinted #2e1a47) | Dark (light instead of shadow) |
| --- | --- | --- |
| `--elevation-xs` | `0 1px 2px / 5%` | inset top highlight 4% white |
| `--elevation-sm` | `0 1px 2px / 6%` + `0 6px 16px -4px / 9%` | inset 6% + 1px lilac ring 3% |
| `--elevation-md` | `0 1px 3px / 8%` + `0 12px 28px -8px / 16%` | inset 8% + ring 7% |
| `--elevation-lg` | `0 2px 4px / 8%` + `0 24px 48px -14px / 32%` | inset 10% + ring 12% + violet glow `0 20px 44px -18px` |
| `--card-raised` | #ffffff | #15121f (card is #0d0b14) |
| `--edge` (`border-edge`) | violet 8% | lilac 13% |
| `--card-surface` (`surface`) | bottom 45% settles by 2.5% violet | top 72px lit by 3.5% white |
| `--pill-highlight` (`shadow-pill`) | inset white top + 1px contact shadow | inset 7% white + lilac ring |

Radii follow the level: page chrome and cards 16px (`rounded-2xl`), surfaces nested in a card or in
the sidebar 12px (`rounded-xl`), nav pills 10px, chips 6 to 8px.

## Rules

1. Shadows are always violet-tinted and two-layered; never `shadow-black/..` on new work.
2. `surface` is a translucent overlay, so a card with a `bg-*` override still shows its color.
3. `Card interactive` only when the whole card is one link or button: 2px lift and `md` shadow on
   hover (200 ms, none under reduced motion), focus ring when anything inside has keyboard focus.
4. Photos (`components/ui/photos.ts`) appear only under a veil (`--veil-<hue>`) and only as a crop
   (they are about 736 px wide). `campus-building.jpg` is not Cabuyao University and is not used.
5. Text on a veil: white (`text-on-veil`) or `text-on-veil-muted` (#e8ddf7), only where the veil is
   at least 85% opaque. Worst case (a white pixel under 85% veil): white 10.36:1 / 11.47:1, muted
   7.95:1 / 8.80:1 (light / dark, violet; the other hues are >= 9.11 and >= 6.99).
