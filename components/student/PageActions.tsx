import { Button } from '@/components/ui'

// Heading button for something the portal cannot do yet. It stays visible but disabled, with the
// reason in words next to it.
export function UnavailableAction({ label, reason }: { label: string; reason: string }) {
  return (
    <div className="flex flex-col gap-1 sm:items-end">
      <Button variant="outline" disabled aria-describedby="unavailable-reason">
        {label}
      </Button>
      <p id="unavailable-reason" className="text-sm text-muted">
        {reason}
      </p>
    </div>
  )
}

// Heading link that jumps to a section of the same page. Looks like the primary button.
export function JumpLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      className="inline-flex h-9 items-center justify-center rounded-md bg-primary px-3.5 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring max-lg:h-11 max-lg:px-4"
    >
      {children}
    </a>
  )
}
