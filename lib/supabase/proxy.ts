import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { isRoleName, ROLE_HOME, roleForPath } from '@/lib/auth/roles'

// Runs on every page request (see proxy.ts):
//  1. refreshes the Supabase session cookie,
//  2. sends signed-out visitors to /login,
//  3. sends signed-in users to their own module, never another role's.
// The database (RLS) is still the real gatekeeper; this only guides navigation.
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options))
        },
      },
    }
  )

  // getUser() asks Supabase Auth to validate the token (do not use getSession() here)
  const { data } = await supabase.auth.getUser()
  const user = data.user
  const { pathname } = request.nextUrl

  const redirectTo = (path: string) => {
    const url = request.nextUrl.clone()
    url.pathname = path
    url.search = ''
    const redirect = NextResponse.redirect(url)
    // keep any refreshed auth cookies on the redirect response
    response.cookies.getAll().forEach((c) => redirect.cookies.set(c))
    return redirect
  }

  if (!user) {
    return pathname === '/login' ? response : redirectTo('/login')
  }

  // Signed in: find the role (RLS lets a user read their own profile)
  const { data: profile } = await supabase
    .from('profiles')
    .select('is_active, roles(role_name)')
    .eq('profile_id', user.id)
    .single()
  const roleRow = Array.isArray(profile?.roles) ? profile?.roles[0] : profile?.roles
  const role = roleRow?.role_name

  if (!profile || !profile.is_active || !isRoleName(role)) {
    // Signed in to Auth but not an active portal user: end the session.
    await supabase.auth.signOut()
    return pathname === '/login' ? response : redirectTo('/login')
  }

  const home = ROLE_HOME[role]
  if (pathname === '/' || pathname === '/login') return redirectTo(home)

  const moduleRole = roleForPath(pathname)
  if (moduleRole && moduleRole !== role) return redirectTo(home)

  return response
}
