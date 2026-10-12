import 'server-only'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { getCurrentProfile, type CurrentProfile } from '@/lib/auth/session'
import type { RoleName } from '@/lib/auth/roles'

// The ONLY module that reads the server-side admin key (env SUPABASE_ADMIN_KEY). That key bypasses
// Row Level Security, so:
//   - `import 'server-only'` makes the build fail if a Client Component ever imports this file;
//   - the key is never logged, returned, put in an error message, or given a NEXT_PUBLIC_ name;
//   - the client is only handed out AFTER the caller's own session proves the required role
//     (signed in, active profile, that role). Callers never build it themselves.
// Use from Server Actions only, and only for the steps the signed-in user's session cannot do.

export type AdminContext = { admin: SupabaseClient; profile: CurrentProfile }

// Returns the admin client together with the caller's profile, or null when the caller is not a
// signed-in, active user with `role`. Throws a plain Error (no key, no URL) when the server is not
// configured, so the caller can show a generic message.
export async function getAdminClientFor(role: RoleName): Promise<AdminContext | null> {
  const profile = await getCurrentProfile()
  if (!profile || profile.role !== role) return null

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_ADMIN_KEY
  if (!url || !key) throw new Error('The admin client is not configured on the server.')

  const admin = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  })
  return { admin, profile }
}
