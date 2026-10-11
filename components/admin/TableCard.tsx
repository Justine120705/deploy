import { Section } from '@/components/ui'

// A hairline table sheet, optionally under a Section heading. The table scrolls sideways inside the
// sheet on phones, so the page itself never scrolls sideways. `minWidth` keeps columns readable.
export default function TableCard({
  title,
  action,
  description,
  footer,
  minWidth = 'min-w-[560px]',
  children,
}: {
  title?: string
  action?: React.ReactNode
  description?: string
  footer?: React.ReactNode
  minWidth?: string
  children: React.ReactNode
}) {
  const sheet = (
    <div className="overflow-hidden rounded-lg border border-edge bg-card">
      <div
        className="overflow-x-auto focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring"
        tabIndex={0}
        role="region"
        aria-label={title ?? 'Table'}
      >
        <table className={`w-full text-left text-sm tabular-nums text-foreground ${minWidth}`}>{children}</table>
      </div>
      {footer && <p className="border-t border-border-subtle px-4 py-3 text-sm text-muted">{footer}</p>}
    </div>
  )
  if (!title) return sheet
  return (
    <Section title={title} action={action} description={description}>
      {sheet}
    </Section>
  )
}
