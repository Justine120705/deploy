import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { GradesActions, GradesBody, GradesProvider } from '@/components/registrar/GradesEncoder'

export default async function RegistrarGradesPage() {
  const profile = await requireRole('Registrar')
  return (
    <GradesProvider>
      <DashboardShell
        profile={profile}
        title="Encode grades"
        subtitle="CS101 · Introduction to Computing · 1st Sem 2026-2027"
        actions={<GradesActions />}
      >
        <GradesBody />
      </DashboardShell>
    </GradesProvider>
  )
}
