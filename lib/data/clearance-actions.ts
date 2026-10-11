'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getCurrentTerm } from '@/lib/data/clearance'

export type RequestClearanceState = { status: 'idle' | 'success' | 'error'; message: string }

// Creates the signed-in student's clearance for the current term. Only student_id and term_id are
// sent; the database checks student_id = auth.uid() (RLS) and creates one item per department.
// On success, and when the clearance already exists, the student is sent back to the clearance page with
// a notice: the page re-renders to the clearance view, so a message kept in the button would disappear.
export async function requestClearance(
  _prev: RequestClearanceState,
  _formData: FormData
): Promise<RequestClearanceState> {
  void _formData
  const generic: RequestClearanceState = {
    status: 'error',
    message: 'We could not send your clearance request. Please try again in a few minutes.',
  }
  let outcome: 'requested' | 'already-requested'
  try {
    const supabase = await createClient()
    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) return { status: 'error', message: 'Your session has ended. Please sign in again.' }

    const term = await getCurrentTerm()
    if (!term) return { status: 'error', message: 'There is no open term to request clearance for yet.' }

    const { error } = await supabase.from('clearances').insert({ student_id: user.id, term_id: term.termId })
    if (error && error.code !== '23505') return generic
    // 23505 = unique violation: one clearance per student per term, so it was requested already.
    outcome = error ? 'already-requested' : 'requested'
  } catch {
    return generic
  }

  revalidatePath('/student', 'layout')
  redirect(`/student/clearance?notice=${outcome}`)
}
