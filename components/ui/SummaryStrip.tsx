import { cn } from '@/lib/utils'
import { HUE_TEXT, type Hue } from './hue'

export type SummaryItem = {
  label: string
  value: React.ReactNode
  /** Short line under the value, for example "of 4 offices". */
  hint?: string
  /** Colours the number only when it carries status (the hint or label must still say it in words). */
  hue?: Hue
}

// One sheet with hairline dividers instead of a separate card per metric. 2 across on phones, up to
// 4 across from lg. Use it as the first block of a screen (what is the state of things right now).
export function SummaryStrip({ items, className }: { items: SummaryItem[]; className?: string }) {
  const cols = items.length <= 3 ? 'lg:grid-cols-3' : 'lg:grid-cols-4'
  return (
    <dl
      className={cn(
        'grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-edge bg-edge',
        cols,
        className
      )}
    >
      {items.map((item, i) => (
        <div
          key={item.label}
          // An odd count would leave a blank cell in the 2-column phone grid: let the last item fill the row.
          className={cn(
            'flex flex-col gap-0.5 bg-card px-4 py-3.5 lg:px-5',
            items.length % 2 === 1 && i === items.length - 1 && 'col-span-2 lg:col-span-1'
          )}
        >
          <dt className="text-[13px] font-medium leading-5 text-muted">{item.label}</dt>
          <dd className={cn('text-2xl font-semibold leading-8 tabular-nums', item.hue && HUE_TEXT[item.hue])}>
            {item.value}
          </dd>
          {item.hint && <dd className="text-[13px] leading-5 text-muted">{item.hint}</dd>}
        </div>
      ))}
    </dl>
  )
}

// A heading above a block of content (table, list, form) with an optional right-hand action. Replaces
// "a titled card around every widget": the title sits on the page, hairlines do the separating.
export function Section({
  title,
  action,
  description,
  children,
  className,
}: {
  title: string
  action?: React.ReactNode
  description?: string
  children: React.ReactNode
  className?: string
}) {
  return (
    <section className={cn('flex flex-col gap-3', className)}>
      <div className="flex items-end justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-base font-semibold leading-6">{title}</h2>
          {description && <p className="text-sm text-muted">{description}</p>}
        </div>
        {action}
      </div>
      {children}
    </section>
  )
}
