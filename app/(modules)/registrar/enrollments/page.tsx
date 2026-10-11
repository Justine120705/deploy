import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { SampleDataNote } from '@/components/ui'
import { EnrollmentsActions, EnrollmentsBody, EnrollmentsProvider } from '@/components/registrar/EnrollmentsReview'

export default async function RegistrarEnrollmentsPage() {
  const profile = await requireRole('Registrar')
  return (
    <EnrollmentsProvider>
      <DashboardShell
        profile={profile}
        title="Enrollments"
        subtitle="1st Sem 2026-2027 · review and approve submitted enrollments"
        actions={<EnrollmentsActions />}
      >
        <div className="flex flex-col gap-4">
          <SampleDataNote />
          <EnrollmentsBody />
        </div>
      </DashboardShell>
    </EnrollmentsProvider>
  )
}
