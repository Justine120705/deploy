'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getCurrentProfile } from '@/lib/auth/session'
import { ROLE_HOME } from '@/lib/auth/roles'

export type LoginState = { error: string | null }

export async function login(_prev: LoginState, formData: FormData): Promise<LoginState> {
  const email = String(formData.get('email') ?? '').trim()
  const password = String(formData.get('password') ?? '')

  if (!email || !password) return { error: 'Enter your email and password.' }

  // TODO (SEC-03, Backend team): before this call, check public.login_attempts for
  // lockout / backoff, and record the attempt afterwards (needs the service_role
  // key, server-side only).

  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({ email, password })

  // Same message for every failure, so it does not reveal which emails exist.
  if (error) return { error: 'Invalid email or password.' }

  const profile = await getCurrentProfile()
  if (!profile) {
    await supabase.auth.signOut()
    return { error: 'This account is not active in the portal. Contact the Admin.' }
  }

  redirect(ROLE_HOME[profile.role])
}

export async function logout() {
  const supabase = await createClient()
  await supabase.auth.signOut()
  redirect('/login')
}
