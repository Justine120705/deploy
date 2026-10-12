'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getCurrentProfile } from '@/lib/auth/session'

// Server Action for the Registrar's enrollment decision. It runs with the signed-in user's own session:
// the database (RLS, column grants, enrollment rules trigger) is the final gate; the checks here only
// give friendly messages. Only status (and remarks, when typed) is sent: reviewed_by and reviewed_at
// are set by the database, never by this code.

export type DecideEnrollmentState = { status: 'idle' | 'success' | 'error'; message: string }

const SESSION_ENDED = 'Your session has ended. Please sign in again.'
const NOT_ALLOWED = 'Your account is not allowed to do this.'
const GENERIC = 'We could not save the decision. Please try again in a few minutes.'
const MAX_REMARKS = 300

function friendlyError(code: string | undefined, message: string | undefined, details: string | null | undefined): string {
  if (code === 'P0001' && message) {
    if (message.startsWith('section full:')) {
      const list = details?.replace(/^full sections:\s*/, '').slice(0, 400)
      return list
        ? `This enrollment cannot be approved because a section has no seat left. Full sections: ${list}. Ask the student to pick another section, or reject the enrollment.`
        : 'This enrollment cannot be approved because a section has no seat left.'
    }
    if (message.startsWith('no items:')) {
      return 'This enrollment has no sections, so it cannot be approved. Reject it, or wait until the student adds sections.'
    }
    if (message.startsWith('wrong term:')) {
      return 'A section in this enrollment belongs to another term, so it cannot be approved. Reject it so the student can be told.'
    }
    if (message.startsWith('enrollment locked:')) {
      return 'This enrollment was already decided and cannot be changed. Reload the page.'
    }
  }
  if (code === '42501') return NOT_ALLOWED
  return GENERIC
}

// Approves or rejects one Pending enrollment. The update is limited to the status the Registrar saw
// (`from`, always Pending), so an enrollment someone else decided meanwhile is reported, not overwritten.
export async function decideEnrollment(_prev: DecideEnrollmentState, formData: FormData): Promise<DecideEnrollmentState> {
  void _prev
  const idRaw = String(formData.get('enrollmentId') ?? '')
  const fromRaw = String(formData.get('from') ?? '')
  const target = String(formData.get('status') ?? '')
  const remarks = String(formData.get('remarks') ?? '').trim()
  const enrollmentId = /^\d+$/.test(idRaw) ? Number(idRaw) : NaN

  if (!Number.isSafeInteger(enrollmentId) || fromRaw !== 'Pending' || (target !== 'Approved' && target !== 'Rejected')) {
    return { status: 'error', message: 'That decision is not allowed. Only Pending enrollments can be decided. Reload the page.' }
  }
  if (remarks.length > MAX_REMARKS) {
    return { status: 'error', message: `The remarks are too long (${MAX_REMARKS} characters at most).` }
  }
  if (target === 'Rejected' && !remarks) {
    return { status: 'error', message: 'Add a remark that tells the student why the enrollment is rejected.' }
  }

  try {
    const profile = await getCurrentProfile()
    if (!profile || profile.role !== 'Registrar') return { status: 'error', message: SESSION_ENDED }
    const supabase = await createClient()

    const patch: { status: string; remarks?: string } = { status: target }
    if (remarks) patch.remarks = remarks

    // .select() returns the updated rows, so a change that RLS or the status filter skipped shows up as no rows.
    const { data: updated, error } = await supabase
      .from('enrollments')
      .update(patch)
      .eq('enrollment_id', enrollmentId)
      .eq('status', 'Pending')
      .select('enrollment_id')
    if (error) return { status: 'error', message: friendlyError(error.code, error.message, error.details) }
    if (!updated || updated.length === 0) {
      return { status: 'error', message: 'This enrollment was not changed. Someone may have decided it already. Reload the page.' }
    }
  } catch {
    return { status: 'error', message: GENERIC }
  }

  revalidatePath('/registrar', 'layout')
  revalidatePath('/student', 'layout')
  return { status: 'success', message: `Enrollment ${target.toLowerCase()}.` }
}
