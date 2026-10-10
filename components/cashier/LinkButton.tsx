import Link from 'next/link'
import { Icon, type IconKey } from '@/components/layout/Icon'

// Pill link that looks like the primary Button (the shared Button is not a link).
export function LinkButton({ href, icon, children }: { href: string; icon?: IconKey; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-flex h-11 items-center justify-center gap-2 rounded-full bg-primary px-5 text-sm font-semibold text-primary-foreground transition-colors hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring lg:h-10"
    >
      {icon && <Icon name={icon} className="size-4" />}
      {children}
    </Link>
  )
}
