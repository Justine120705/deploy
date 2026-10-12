// Single source of truth for roles and where each role lands after login.
// Role names match public.roles.role_name in the database.
export const ROLES = ['Student', 'Registrar', 'Cashier', 'Department', 'Admin'] as const
export type RoleName = (typeof ROLES)[number]

export const ROLE_HOME: Record<RoleName, string> = {
  Student: '/student',
  Registrar: '/registrar',
  Cashier: '/cashier',
  Department: '/department',
  Admin: '/admin',
}

export function isRoleName(value: unknown): value is RoleName {
  return typeof value === 'string' && (ROLES as readonly string[]).includes(value)
}

// Pages anyone can open without signing in (the proxy lets them through).
// /apply: the enrollment site for new applicants. /auth/confirm: the set-password link
// from the acceptance email (it creates the session). /login is handled by the proxy.
export const PUBLIC_PATHS = ['/apply', '/auth/confirm'] as const

export function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + '/'))
}

// Which module a URL belongs to, e.g. "/cashier/payments" -> "Cashier"
export function roleForPath(pathname: string): RoleName | null {
  for (const role of ROLES) {
    const home = ROLE_HOME[role]
    if (pathname === home || pathname.startsWith(home + '/')) return role
  }
  return null
}
