import { SummaryStrip, type Hue } from '@/components/ui'

export type DeptStat = { label: string; value: number; hint: string; hue?: Hue }

// One summary strip (not four cards). The number is coloured only when it carries status, and the
// label and hint always say it in words.
export function DeptStats({ stats }: { stats: DeptStat[] }) {
  return <SummaryStrip items={stats} />
}
