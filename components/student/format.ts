// Dates on the student pages are shown in Philippine time, so the server and the browser print the
// same text (no hydration mismatch) whatever time zone they run in.
const SHORT = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  timeZone: 'Asia/Manila',
})

/** "Oct 3, 2026". Empty or missing dates show a dash. */
export function formatShortDate(iso: string | null | undefined) {
  if (!iso) return '-'
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '-' : SHORT.format(d)
}
