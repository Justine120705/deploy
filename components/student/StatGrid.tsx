import { SummaryStrip, type Hue } from '@/components/ui'

export type Stat = {
  label: string
  value: React.ReactNode
  hint: string
  /** Colors the number. Use it only for status, and keep the status in the label or hint too. */
  hue?: Hue
}

// The numbers that matter, as one hairline sheet (two across on phones, up to four from lg) instead of
// a card per metric. Kept under its old name so existing screens keep working.
export function StatGrid({ stats, className }: { stats: readonly Stat[]; className?: string }) {
  return <SummaryStrip items={[...stats]} className={className} />
}
