import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { ClearanceActions, ClearanceBody, ClearanceProvider } from '@/components/registrar/ClearanceReview'

export default async function RegistrarClearancePage() {
  const profile = await requireRole('Registrar')
  return (
    <ClearanceProvider>
      <DashboardShell
        profile={profile}
        title="Clearance"
        subtitle="1st Sem 2026-2027 · final approval once every office has cleared"
        actions={<ClearanceActions />}
      >
        <ClearanceBody />
      </DashboardShell>
    </ClearanceProvider>
  )
}
