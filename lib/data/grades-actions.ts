'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

export type EncodeGradeState = { status: 'idle' | 'success' | 'error'; message: string }

const NOT_APPROVED =
  "This grade cannot be saved because the student's enrollment is not approved. Approve the enrollment first, then encode the grade."

function mapError(error: { code?: string; message: string }): string {
  if (error.code === 'P0001' && error.message.startsWith('not approved:')) return NOT_APPROVED
  if (error.code === '23503') return 'That grade is not on the grade scale. Pick a grade from the list.'
  return 'We could not save the grade. Please try again in a few minutes.'
}

// Encodes or corrects one grade. Sends only { enrollment_item_id, grade_code, encoded_by } on insert
// and { grade_code, encoded_by } on update; encoded_at is stamped by the database. Inserts when the
// item has no grade yet, otherwise updates the existing row. No delete exists.
export async function encodeGrade(_prev: EncodeGradeState, formData: FormData): Promise<EncodeGradeState> {
  const rawItem = formData.get('enrollmentItemId')
  const rawCode = formData.get('gradeCode')
  const itemId = typeof rawItem === 'string' ? Number(rawItem) : NaN
  const gradeCode = typeof rawCode === 'string' ? rawCode.trim() : ''
  if (!Number.isInteger(itemId) || itemId <= 0) return { status: 'error', message: 'Select a student and subject first.' }
  if (!gradeCode) return { status: 'error', message: 'Pick a grade from the list first.' }

  try {
    const supabase = await createClient()
    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) return { status: 'error', message: 'Your session has ended. Please sign in again.' }

    const update = async () => {
      const { data, error } = await supabase
        .from('grades')
        .update({ grade_code: gradeCode, encoded_by: user.id })
        .eq('enrollment_item_id', itemId)
        .select('grade_id')
      return { error, found: (data ?? []).length > 0 }
    }

    const existing = await supabase.from('grades').select('grade_id').eq('enrollment_item_id', itemId).limit(1).maybeSingle()
    if (existing.error) return { status: 'error', message: mapError(existing.error) }

    if (existing.data) {
      const res = await update()
      if (res.error) return { status: 'error', message: mapError(res.error) }
      if (!res.found) return { status: 'error', message: 'This grade is no longer available. Reload the page.' }
    } else {
      const { error } = await supabase
        .from('grades')
        .insert({ enrollment_item_id: itemId, grade_code: gradeCode, encoded_by: user.id })
      if (error) {
        if (error.code !== '23505') return { status: 'error', message: mapError(error) }
        // Someone encoded it a moment ago (one grade per item): correct that one instead.
        const res = await update()
        if (res.error) return { status: 'error', message: mapError(res.error) }
      }
    }
  } catch {
    return { status: 'error', message: 'We could not save the grade. Please try again in a few minutes.' }
  }

  revalidatePath('/registrar/grades')
  revalidatePath('/student/grades')
  return { status: 'success', message: `Saved ${gradeCode}.` }
}
