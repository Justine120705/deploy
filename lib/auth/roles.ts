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

// Which module a URL belongs to, e.g. "/cashier/payments" -> "Cashier"
export function roleForPath(pathname: string): RoleName | null {
  for (const role of ROLES) {
    const home = ROLE_HOME[role]
    if (pathname === home || pathname.startsWith(home + '/')) return role
  }
  return null
}
