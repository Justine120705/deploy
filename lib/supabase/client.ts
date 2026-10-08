import { createBrowserClient } from '@supabase/ssr'
import type { Database } from '@/types/database.types'
// Use in Client Components ("use client"). Keeps the session in cookies so the
// server (proxy and Server Components) sees the same logged-in user.
export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
