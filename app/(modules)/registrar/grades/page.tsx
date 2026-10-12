import { requireRole } from '@/lib/auth/session'
import DashboardShell from '@/components/layout/DashboardShell'
import { EmptyState } from '@/components/ui'
import GradesEncoder from '@/components/registrar/GradesEncoder'
import { getRegistrarGradesState } from '@/lib/data/grades'

export default async function RegistrarGradesPage() {
  const profile = await requireRole('Registrar')
  const state = await getRegistrarGradesState()

  const subtitle =
    state.kind === 'ready'
      ? `${state.term.semester} ${state.term.schoolYear} · approved enrollments only`
      : 'Approved enrollments only'

  return (
    <DashboardShell profile={profile} title="Encode grades" subtitle={subtitle}>
      {state.kind === 'error' ? (
        <div role="alert">
          <EmptyState title="We could not load the class records">
            Something went wrong on our side. Reload the page, and if it keeps happening, come back in a few minutes.
          </EmptyState>
        </div>
      ) : state.kind === 'no-term' ? (
        <EmptyState title="No term is open">Grades can be encoded once a current term is set.</EmptyState>
      ) : (
        <GradesEncoder items={state.items} scale={state.scale} />
      )}
    </DashboardShell>
  )
}
