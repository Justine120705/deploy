import { Icon } from '@/components/layout/Icon'
import { cn } from '@/lib/utils'

// Three-dot button in the corner of a dashboard card. Pass onClick from a client component when
// it needs to open a menu; without it the button is only a visual placeholder.
export function CardMenuButton({
  label = 'More options',
  className,
  ...props
}: { label?: string } & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      aria-label={label}
      className={cn(
        'inline-flex size-7 max-lg:-m-2 max-lg:size-11 items-center justify-center rounded-md text-muted transition-colors hover:bg-hover-tint hover:text-foreground',
        'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring',
        className
      )}
      {...props}
    >
      <Icon name="more" />
    </button>
  )
}
