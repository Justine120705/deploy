import { logout } from '@/app/(auth)/login/actions'
import type { CurrentProfile } from '@/lib/auth/session'
import { NAV_ITEMS } from '@/lib/nav'
import { Icon } from './Icon'
import ShellFrame from './ShellFrame'

// Shared frame for every module page: role-based sidebar, top bar, page title and sign-out.
// Build each module's real UI inside {children}.
export default function DashboardShell({
  profile,
  title,
  subtitle,
  actions,
  children,
}: {
  profile: CurrentProfile
  title: string
  subtitle?: string
  actions?: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <ShellFrame
      items={NAV_ITEMS[profile.role]}
      roleLabel={profile.role}
      userName={`${profile.firstName} ${profile.lastName}`}
      signOut={
        <form action={logout}>
          <button className="flex h-11 w-full items-center gap-3 rounded-lg px-3 text-sm font-medium text-muted transition-colors hover:bg-accent/60 hover:text-accent-foreground">
            <Icon name="logout" />
            Sign out
          </button>
        </form>
      }
    >
      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold">{title}</h1>
          {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
        </div>
        {actions}
      </div>
      {children}
    </ShellFrame>
  )
}
