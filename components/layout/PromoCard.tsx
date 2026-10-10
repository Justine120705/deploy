import type { PhotoKey } from '@/components/ui/photos'

// Legacy: the flat shell no longer renders a sidebar promo (DashboardShell accepts and ignores it).
// If placed somewhere else it is a quiet sheet: figure, what it counts, optional note. `image` is
// accepted for compatibility and not drawn.
export default function PromoCard({
  value,
  label,
  note,
}: {
  value: React.ReactNode
  label: string
  note?: string
  image?: PhotoKey
}) {
  return (
    <div className="flex flex-col gap-0.5 rounded-lg border border-edge bg-card p-4">
      <p className="text-3xl font-semibold tabular-nums text-accent-foreground">{value}</p>
      <p className="text-sm font-medium text-foreground">{label}</p>
      {note && <p className="text-[13px] leading-5 text-muted">{note}</p>}
    </div>
  )
}
