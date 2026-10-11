import { Badge, StatusBadge } from '@/components/ui'

// A hold is a problem, so an active hold is rose ("danger"), unlike StatusBadge where Active is green.
export function HoldStatusBadge({ status }: { status: 'Active' | 'Lifted' }) {
  return <Badge tone={status === 'Active' ? 'danger' : 'neutral'}>{status === 'Active' ? 'Active hold' : 'Lifted'}</Badge>
}

export function HoldFlagBadge({ active }: { active: boolean }) {
  return <Badge tone={active ? 'danger' : 'neutral'}>{active ? 'Active hold' : 'No hold'}</Badge>
}

export function ItemStatusBadge({ status }: { status: string }) {
  return <StatusBadge status={status} />
}
