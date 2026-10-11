import Link from 'next/link'
import { Icon } from '@/components/layout/Icon'
import { Card, CardHeader, StatusBadge } from '@/components/ui'
import { cn } from '@/lib/utils'

export type ChainOffice = {
  name: string
  status: 'Cleared' | 'Pending'
  /** Why the office has not cleared the student yet (empty when cleared). */
  reason: string
  /** What happens next, or what the student must do (empty when cleared). */
  nextAction: string
}

type Step = { name: string; status: 'Cleared' | 'Pending' | 'Waiting' | 'Approved' }

const LINK =
  'inline-flex items-center text-sm font-semibold max-lg:min-h-11 text-accent-foreground hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'

// The clearance as one ordered chain: every office in signing order, then the Registrar's final
// approval. The first office that has not cleared the student is pulled out on top with its reason and
// the next action, so "who is holding it up and what is next" is always the first thing read. Status is
// always a word (StatusBadge); the hue only repeats it (teal good, amber attention, rose problem).
export function ClearanceChain({
  offices,
  activeHolds,
  approved,
  className,
}: {
  offices: readonly ChainOffice[]
  activeHolds: number
  /** The Registrar has approved (live data). Leave out to derive it from offices and holds. */
  approved?: boolean
  className?: string
}) {
  const cleared = offices.filter((o) => o.status === 'Cleared').length
  const blocker = offices.find((o) => o.status !== 'Cleared')
  const allCleared = !blocker && (approved ?? activeHolds === 0)
  const steps: Step[] = [
    ...offices.map((o) => ({ name: o.name, status: o.status })),
    { name: 'Registrar final approval', status: allCleared ? 'Approved' : 'Waiting' },
  ]

  return (
    <Card elevation="raised" className={cn('flex flex-col gap-4 p-5', className)}>
      <CardHeader tinted
        title="Clearance"
        icon="clearance"
        hue="teal"
        action={
          <Link href="/student/clearance" aria-label="See all clearance" className={LINK}>
            See all
          </Link>
        }
      />

      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 text-sm">
        <p>
          <span className="text-2xl font-extrabold">{cleared}</span>
          <span className="font-semibold"> of {offices.length} offices cleared</span>
        </p>
        <p className="font-semibold">
          Active holds:{' '}
          <span className={activeHolds > 0 ? 'text-hue-rose-strong' : 'text-hue-teal-strong'}>{activeHolds}</span>
        </p>
      </div>

      {blocker ? (
        <div className="flex flex-col gap-1 rounded-xl border border-hue-amber-solid/40 bg-hue-amber-soft p-3 text-sm">
          <p className="font-bold text-hue-amber-strong">Waiting on {blocker.name}</p>
          {blocker.reason && <p>{blocker.reason}</p>}
          {blocker.nextAction && <p className="font-semibold">{blocker.nextAction}</p>}
        </div>
      ) : (
        <div className="rounded-xl bg-hue-teal-soft p-3 text-sm font-bold text-hue-teal-strong">
          {allCleared ? 'Your clearance is complete.' : 'All offices cleared. Waiting for the Registrar.'}
        </div>
      )}

      <ol aria-label="Clearance steps, in signing order" className="flex flex-col">
        {steps.map((s, i) => {
          const done = s.status === 'Cleared' || s.status === 'Approved'
          const current = blocker?.name === s.name
          const last = i === steps.length - 1
          return (
            <li
              key={s.name}
              aria-current={current ? 'step' : undefined}
              className={cn(
                'relative flex items-center gap-3 rounded-lg px-2 py-1.5 text-sm',
                current && 'bg-hue-amber-soft',
                // Connector line from this marker to the next one.
                !last &&
                  'after:absolute after:left-[21px] after:top-[calc(50%+14px)] after:h-[calc(100%-28px)] after:w-0.5 after:rounded-full after:bg-border'
              )}
            >
              <span
                aria-hidden="true"
                className={cn(
                  'flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-bold',
                  done && 'bg-hue-teal-soft text-hue-teal-strong',
                  s.status === 'Pending' && 'bg-hue-amber-soft text-hue-amber-strong ring-2 ring-hue-amber-solid',
                  s.status === 'Waiting' && 'bg-neutral-soft text-neutral'
                )}
              >
                {done ? (
                  <Icon name="check" className="size-3.5" />
                ) : s.status === 'Pending' ? (
                  <Icon name="clock" className="size-3.5" />
                ) : (
                  i + 1
                )}
              </span>
              <span className={cn('min-w-0 flex-1', current ? 'font-bold' : 'font-semibold')}>{s.name}</span>
              <StatusBadge status={s.status} className="text-sm" />
            </li>
          )
        })}
      </ol>

      <p className="text-sm text-muted">
        After all {offices.length} offices clear you, the Registrar gives the final approval.
      </p>
    </Card>
  )
}
