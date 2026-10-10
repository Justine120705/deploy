import type { RoleName } from '@/lib/auth/roles'
import { requireRole } from '@/lib/auth/session'
import { Card, CardHeader } from '@/components/ui'
import DashboardShell from './DashboardShell'

// Placeholder body for module screens that are not built yet. Replace per screen when it is
// implemented; the role check and shell stay the same.
export default async function ModulePage({
  role,
  title,
  subtitle,
  planned,
}: {
  role: RoleName
  title: string
  subtitle?: string
  planned: string[]
}) {
  const profile = await requireRole(role)

  return (
    <DashboardShell profile={profile} title={title} subtitle={subtitle}>
      <Card className="p-5">
        <CardHeader title="Coming soon" />
        <p className="mt-2 text-sm text-muted">This screen will contain:</p>
        <ul className="mt-3 list-disc space-y-1 pl-5 text-sm">
          {planned.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </Card>
    </DashboardShell>
  )
}
