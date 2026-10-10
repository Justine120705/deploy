import { Card, CardHeader } from '@/components/ui'

// A titled card that holds a table (Figma admin frames). The table scrolls sideways inside the card
// on phones, so the page itself never scrolls sideways. `minWidth` keeps columns readable.
export default function TableCard({
  title,
  action,
  footer,
  minWidth = 'min-w-[560px]',
  children,
}: {
  title?: string
  action?: React.ReactNode
  footer?: React.ReactNode
  minWidth?: string
  children: React.ReactNode
}) {
  return (
    <Card className="overflow-hidden">
      {title && <CardHeader title={title} action={action} className="px-5 pb-3 pt-5" />}
      <div
        className="overflow-x-auto focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-ring"
        tabIndex={0}
        role="region"
        aria-label={title ?? 'Table'}
      >
        <table className={`w-full text-left text-sm text-foreground ${minWidth}`}>{children}</table>
      </div>
      {footer && <p className="border-t border-border-subtle px-5 py-3 text-sm text-muted">{footer}</p>}
    </Card>
  )
}
