import { cn } from '@/lib/utils'

// Shown by BarChart and LineChart when there is nothing to plot yet. The chart name stays available to
// screen readers.
export function EmptyChart({ ariaLabel, className }: { ariaLabel: string; className?: string }) {
  return (
    <div className={cn('flex min-h-28 w-full items-center justify-center rounded-xl bg-accent/40 px-4 py-6 text-center', className)}>
      <p className="max-w-[28ch] text-sm font-medium text-muted">
        <span className="sr-only">{ariaLabel}: </span>
        No grades yet. They appear after the Registrar encodes them.
      </p>
    </div>
  )
}
