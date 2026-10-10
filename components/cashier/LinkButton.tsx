import Link from 'next/link'
import { Icon, type IconKey } from '@/components/layout/Icon'

// Link that looks like the primary Button (the shared Button is not a link).
export function LinkButton({ href, icon, children }: { href: string; icon?: IconKey; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-flex h-9 items-center justify-center gap-2 rounded-md bg-primary px-3.5 text-sm font-semibold whitespace-nowrap text-primary-foreground transition-colors hover:bg-primary-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring max-lg:h-11 max-lg:px-4"
    >
      {icon && <Icon name={icon} className="size-4" />}
      {children}
    </Link>
  )
}
