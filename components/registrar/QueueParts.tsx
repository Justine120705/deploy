import { cn } from '@/lib/utils'

// One hairline sheet that holds a toolbar row (filters, status line) and the table under it, so the
// queue reads as a single object instead of three stacked boxes.
export function QueueSheet({ toolbar, footer, children }: { toolbar?: React.ReactNode; footer?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="overflow-hidden rounded-lg border border-edge bg-card">
      {toolbar && <div className="flex flex-wrap items-end gap-x-4 gap-y-3 border-b border-border px-4 py-3">{toolbar}</div>}
      <div className="w-full overflow-x-auto">{children}</div>
      {footer && <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">{footer}</div>}
    </div>
  )
}

// Plain table that sits inside a QueueSheet (the sheet already draws the border). minWidth keeps the
// columns readable; on a phone the sheet scrolls sideways.
export function QueueTable({ minWidth, children }: { minWidth: string; children: React.ReactNode }) {
  return <table className={cn('w-full text-left text-sm tabular-nums text-foreground', minWidth)}>{children}</table>
}

// The line that says what is selected or what just happened. Announced politely to screen readers.
export function StatusLine({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <p aria-live="polite" className={cn('min-w-0 flex-1 basis-64 text-sm text-muted', className)}>
      {children}
    </p>
  )
}

// Student cell: name, with the student number under it so one column carries both.
export function StudentCell({ name, sub }: { name: string; sub?: string }) {
  return (
    <>
      <span className="block font-semibold">{name}</span>
      {sub && <span className="block text-xs text-muted">{sub}</span>}
    </>
  )
}
