import { logout } from '@/app/(auth)/login/actions'
import type { CurrentProfile } from '@/lib/auth/session'

// Shared frame for every module page: header with the user's name, role and sign-out.
// Frontend team: build each module's real UI inside {children}.
export default function DashboardShell({
  profile,
  title,
  children,
}: {
  profile: CurrentProfile
  title: string
  children: React.ReactNode
}) {
  return (
    <div className="flex min-h-screen flex-1 flex-col bg-zinc-50">
      <header className="flex items-center justify-between border-b border-zinc-200 bg-white px-6 py-4">
        <div>
          <p className="text-xs uppercase tracking-wide text-zinc-500">{profile.role}</p>
          <h1 className="text-lg font-semibold text-zinc-900">{title}</h1>
        </div>
        <div className="flex items-center gap-4">
          <span className="text-sm text-zinc-700">
            {profile.firstName} {profile.lastName}
          </span>
          <form action={logout}>
            <button className="rounded-md border border-zinc-300 px-3 py-1.5 text-sm text-zinc-800 hover:bg-zinc-100">
              Sign out
            </button>
          </form>
        </div>
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 p-6">{children}</main>
    </div>
  )
}
