import { Badge } from './Badge'
import { cn } from '@/lib/utils'

// Marks a page or section that still shows made-up sample data, so it never reads as live.
export function SampleDataNote({ className, children }: { className?: string; children?: React.ReactNode }) {
  return (
    <p className={cn('flex flex-wrap items-center gap-2 text-sm text-muted', className)}>
      <Badge tone="info">Sample data</Badge>
      <span>{children ?? 'This section is not connected to live records yet.'}</span>
    </p>
  )
}
