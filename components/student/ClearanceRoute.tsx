import { cn } from '@/lib/utils'

export type RouteOffice = {
  name: string
  status: 'Cleared' | 'Pending'
  /** Why the office has not cleared the student yet (empty when cleared). */
  reason: string
  /** What happens next, or what the student must do (empty when cleared). */
  nextAction: string
}

type StationState = 'Cleared' | 'Pending' | 'Waiting' | 'Approved'
type Station = { name: string; state: StationState; reason?: string; terminal?: boolean }

const STATE_TEXT: Record<StationState, string> = {
  Cleared: 'text-hue-teal-strong',
  Approved: 'text-hue-teal-strong',
  Pending: 'text-hue-amber-strong',
  Waiting: 'text-muted',
}

// Station mark on the route line. Decorative: the state is always written next to it in words.
// Offices are round; the Registrar's final approval is the square terminal.
function Mark({ state, terminal }: { state: StationState; terminal?: boolean }) {
  const shape = terminal ? 'rounded-[3px]' : 'rounded-full'
  if (state === 'Cleared' || state === 'Approved') {
    return (
      <span aria-hidden="true" className={cn('relative z-10 flex size-4 shrink-0 items-center justify-center bg-hue-teal-solid text-card', shape)}>
        <svg viewBox="0 0 16 16" fill="none" className="size-3">
          <path d="m4 8.2 2.6 2.6L12 5.4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
    )
  }
  if (state === 'Pending') {
    return (
      <span aria-hidden="true" className={cn('relative z-10 flex size-4 shrink-0 items-center justify-center border-2 border-hue-amber-solid bg-card', shape)}>
        <span className={cn('size-1.5 bg-hue-amber-solid', shape)} />
      </span>
    )
  }
  return <span aria-hidden="true" className={cn('relative z-10 size-4 shrink-0 border-2 border-field-border bg-card', shape)} />
}

// The clearance as a route: every office in signing order as a station on one ruled line, ending at the
// Registrar's final approval. Horizontal from md, a vertical list on phones. The first office that has
// not cleared the student is named under the line with its reason and the next action, so "who is
// holding it up and what is next" is read before anything else. `action` is the one primary button.
// `detail` adds each pending office's reason under its station (the Clearance page). Server-safe.
export function ClearanceRoute({
  offices,
  activeHolds,
  approved,
  action,
  detail = false,
  headingLevel = 'h2',
  className,
}: {
  offices: readonly RouteOffice[]
  activeHolds: number
  /** The Registrar has approved (live data). Leave out to derive it from offices and holds. */
  approved?: boolean
  action?: React.ReactNode
  detail?: boolean
  headingLevel?: 'h2' | 'h3'
  className?: string
}) {
  const Heading = headingLevel
  const cleared = offices.filter((o) => o.status === 'Cleared').length
  const blocker = offices.find((o) => o.status !== 'Cleared')
  const allCleared = !blocker && (approved ?? activeHolds === 0)
  const stations: Station[] = [
    ...offices.map((o) => ({
      name: o.name,
      state: o.status === 'Cleared' ? ('Cleared' as const) : ('Pending' as const),
      reason: o.reason,
    })),
    { name: 'Registrar final approval', state: allCleared ? 'Approved' : 'Waiting', terminal: true },
  ]

  const holdsText =
    activeHolds === 0 ? 'No active holds' : `${activeHolds} active ${activeHolds === 1 ? 'hold' : 'holds'}`

  return (
    <section
      aria-labelledby="clearance-route-title"
      className={cn('rounded-lg border border-edge bg-card', className)}
    >
      <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-3 px-4 pt-4 sm:px-5 sm:pt-5">
        <div className="min-w-0">
          <Heading id="clearance-route-title" className="text-base font-semibold">
            Clearance
          </Heading>
          <p className="mt-0.5 text-sm text-muted">
            <span className="font-semibold text-foreground tabular-nums">
              {cleared} of {offices.length}
            </span>{' '}
            offices cleared
            <span aria-hidden="true"> · </span>
            <span className="sr-only">. </span>
            <span className={cn('font-medium', activeHolds > 0 ? 'text-hue-rose-strong' : 'text-muted')}>{holdsText}</span>
          </p>
        </div>
        {action && <div className="shrink-0 max-sm:w-full [&>*]:max-sm:w-full">{action}</div>}
      </div>

      <ol aria-label="Clearance route, in signing order" className="flex flex-col px-4 pt-5 sm:px-5 md:flex-row">
        {stations.map((s, i) => {
          const last = i === stations.length - 1
          const current = blocker?.name === s.name
          const travelled = s.state === 'Cleared'
          return (
            <li
              key={s.name}
              aria-current={current ? 'step' : undefined}
              className={cn(
                'relative flex min-w-0 gap-3 pb-4 last:pb-0 md:flex-1 md:flex-col md:gap-2.5 md:pb-0 md:pr-4',
                last && 'md:flex-none md:pr-0'
              )}
            >
              {!last && (
                <span
                  aria-hidden="true"
                  className={cn(
                    'absolute left-[7.5px] top-4 bottom-0 w-px md:left-4 md:right-0 md:top-[7.5px] md:bottom-auto md:h-px md:w-auto',
                    travelled ? 'bg-hue-teal-solid' : 'bg-field-border'
                  )}
                />
              )}
              <Mark state={s.state} terminal={s.terminal} />
              <div className="-mt-0.5 flex min-w-0 flex-col md:mt-0">
                <span className={cn('text-sm', current || s.terminal ? 'font-semibold' : 'font-medium')}>{s.name}</span>
                <span className={cn('text-xs font-semibold', STATE_TEXT[s.state])}>{s.state}</span>
                {detail && s.state === 'Pending' && s.reason && (
                  <span className="mt-0.5 text-xs text-muted">{s.reason}</span>
                )}
              </div>
            </li>
          )
        })}
      </ol>

      <div className="mt-5 border-t border-border-subtle px-4 py-3.5 text-sm sm:px-5">
        {blocker ? (
          <p className="flex flex-col gap-0.5 sm:flex-row sm:flex-wrap sm:gap-x-2">
            <span className="font-semibold">
              <span className="text-hue-amber-strong">Waiting on</span> {blocker.name}
            </span>
            {blocker.reason && <span className="text-muted">{blocker.reason}.</span>}
            {blocker.nextAction && <span className="font-medium">{blocker.nextAction}</span>}
          </p>
        ) : (
          <p className="font-semibold text-hue-teal-strong">
            {allCleared
              ? 'Your clearance is complete.'
              : activeHolds > 0
                ? 'All offices cleared. Lift the active holds before the Registrar can approve.'
                : 'All offices cleared. Waiting for the Registrar.'}
          </p>
        )}
      </div>
    </section>
  )
}
