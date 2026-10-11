'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

export type IssueClearanceState = { status: 'idle' | 'success' | 'error'; message: string }

// Gives final approval: sets approved_by (the signed-in Registrar) and approved_at (server time)
// together, as the table requires. The database refuses it while an office is still pending.
export async function issueFinalClearance(
  _prev: IssueClearanceState,
  formData: FormData
): Promise<IssueClearanceState> {
  const generic: IssueClearanceState = {
    status: 'error',
    message: 'We could not issue the final clearance. Please try again in a few minutes.',
  }
  const raw = formData.get('clearanceId')
  const clearanceId = typeof raw === 'string' ? Number(raw) : NaN
  if (!Number.isInteger(clearanceId) || clearanceId <= 0) {
    return { status: 'error', message: 'Select a clearance request first.' }
  }

  try {
    const supabase = await createClient()
    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) return { status: 'error', message: 'Your session has ended. Please sign in again.' }

    const { data, error } = await supabase
      .from('clearances')
      .update({ approved_by: user.id, approved_at: new Date().toISOString() })
      .eq('clearance_id', clearanceId)
      .is('approved_at', null)
      .select('clearance_id')

    if (error) {
      if (error.code === 'P0001' && error.message.startsWith('pending items:')) {
        return {
          status: 'error',
          message: 'An office has not cleared this student yet, so final clearance cannot be issued. Reload to see the latest status.',
        }
      }
      return generic
    }
    if (!data || data.length === 0) {
      revalidatePath('/registrar', 'layout')
      return {
        status: 'error',
        message: 'This clearance was already approved or is no longer available. The list has been refreshed.',
      }
    }
  } catch {
    return generic
  }

  revalidatePath('/registrar', 'layout')
  return { status: 'success', message: 'Final clearance issued.' }
}
