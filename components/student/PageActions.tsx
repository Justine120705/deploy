import { Button } from '@/components/ui'

// Heading button for something the portal cannot do yet. It stays visible but disabled, with the
// reason in words next to it.
export function UnavailableAction({ label, reason }: { label: string; reason: string }) {
  return (
    <div className="flex flex-col gap-1 sm:items-end">
      <Button disabled aria-describedby="unavailable-reason" className="max-lg:h-11">
        {label}
      </Button>
      <p id="unavailable-reason" className="text-sm text-muted">
        {reason}
      </p>
    </div>
  )
}

// Heading link that jumps to a section of the same page, styled like the primary button.
export function JumpLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      className="inline-flex h-10 items-center justify-center rounded-full bg-primary px-5 text-sm font-semibold text-primary-foreground transition-colors hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring max-lg:h-11"
    >
      {children}
    </a>
  )
}
