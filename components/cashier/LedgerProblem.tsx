import { EmptyState } from '@/components/ui'

// Shown instead of a screen when the live data cannot be shown (no open term, or a read failed).
export default function LedgerProblem({ kind }: { kind: 'no-term' | 'error' }) {
  if (kind === 'no-term') {
    return (
      <EmptyState title="No term is open">
        Charges and clearance belong to the current term. They appear once the Registrar sets the current term.
      </EmptyState>
    )
  }
  return (
    <div role="alert">
      <EmptyState title="We could not load this page">
        Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
      </EmptyState>
    </div>
  )
}
