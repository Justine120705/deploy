import { Icon } from '@/components/layout/Icon'
import { Card, CardHeader, StatusBadge } from '@/components/ui'
import { cn } from '@/lib/utils'
import type { ChainOffice } from './ClearanceChain'

type Step = { name: string; status: 'Cleared' | 'Pending' | 'Waiting' | 'Approved' }

// The clearance chain for the Clearance page: the same chain as the dashboard card (ClearanceChain),
// every office in signing order and then the Registrar final approval, but without the "See all" link
// (this already is the full page). The first office that has not cleared is pulled out on top with
// its reason and next action. Status is always a word; the hue only repeats it.
export function ClearanceProgress({
  offices,
  activeHolds,
  className,
}: {
  offices: readonly ChainOffice[]
  activeHolds: number
  className?: string
}) {
  const blocker = offices.find((o) => o.status !== 'Cleared')
  const allCleared = !blocker && activeHolds === 0
  const steps: Step[] = [
    ...offices.map((o) => ({ name: o.name, status: o.status })),
    { name: 'Registrar final approval', status: allCleared ? 'Approved' : 'Waiting' },
  ]

  return (
    <Card elevation="raised" className={cn('flex flex-col gap-4 p-5', className)}>
      <CardHeader title="Clearance chain" icon="clearance" hue="teal" />

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
    </Card>
  )
}
