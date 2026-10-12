'use server'

import { redirect } from 'next/navigation'
import { headers } from 'next/headers'
import { createClient } from '@/lib/supabase/server'
import { getCurrentProfile } from '@/lib/auth/session'
import { ROLE_HOME } from '@/lib/auth/roles'
import { looksLikeStudentId, studentIdToEmail } from '@/lib/auth/student-id'

export type LoginState = { error: string | null }

export async function login(_prev: LoginState, formData: FormData): Promise<LoginState> {
  const typed = String(formData.get('email') ?? '').trim()
  const password = String(formData.get('password') ?? '')

  if (!typed || !password) return { error: 'Enter your student ID or email, and your password.' }

  // A student ID (for example 2026-0001) is turned into its internal sign-in email BEFORE the lockout
  // check, so the lockout and the rate limit key on that email string. Anything else without an @
  // is not a valid sign-in name: same generic error, no database call.
  let email = typed
  if (!typed.includes('@')) {
    if (!looksLikeStudentId(typed)) return { error: 'Invalid email or password.' }
    email = studentIdToEmail(typed)
  }

  const supabase = await createClient()

  // SEC-03: the lockout is checked BEFORE the password is verified. The check and the
  // recording go through SECURITY DEFINER database functions (docs/database/
  // login_lockout.sql), so no server-only key is needed here.
  const { data: lock, error: lockError } = await supabase.rpc('check_login_lockout', {
    p_email: email,
  })
  // Fail closed: if the check cannot run, do not let the attempt through unchecked.
  if (lockError) return { error: 'Sign-in is temporarily unavailable. Try again shortly.' }
  const state = Array.isArray(lock) ? lock[0] : lock
  if (state?.locked) {
    const minutes = Math.max(1, Math.ceil((state.seconds_remaining ?? 60) / 60))
    return {
      error: `Too many failed sign-in attempts. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`,
    }
  }

  const forwarded = (await headers()).get('x-forwarded-for')?.split(',')[0]?.trim() || null

  const { error } = await supabase.auth.signInWithPassword({ email, password })

  // Same message for every failure, so it does not reveal which emails exist.
  if (error) {
    await supabase.rpc('record_login_attempt', { p_email: email, p_success: false, p_ip: forwarded })
    return { error: 'Invalid email or password.' }
  }

  // Now signed in: the database only accepts a success for the signed-in user's own email.
  await supabase.rpc('record_login_attempt', { p_email: email, p_success: true, p_ip: forwarded })

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
