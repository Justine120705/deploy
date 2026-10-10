import { cn } from '@/lib/utils'

// The next class as plain text: course, code and start time. No ticking countdown (it moved every second
// and was announced as noise); room and section are not in the data yet, so they are not shown.
export function NextLesson({
  title,
  code,
  startsAt,
  className,
}: {
  title: string
  code: string
  startsAt: string
  className?: string
}) {
  return (
    <div className={cn('flex flex-col gap-0.5', className)}>
      <h3 className="text-sm font-semibold">Next class</h3>
      <p className="text-base font-semibold">
        {title} <span className="text-sm font-medium text-muted">{code}</span>
      </p>
      <p className="text-sm text-muted">
        Starts at <span className="font-semibold text-foreground tabular-nums">{startsAt}</span>
      </p>
    </div>
  )
}
