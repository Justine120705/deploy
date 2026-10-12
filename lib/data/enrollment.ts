import { createClient } from '@/lib/supabase/server'
import { getCurrentTerm, type CurrentTerm } from '@/lib/data/clearance'

// Server-side reads for the student enrollment screen. Every query runs with the signed-in user's own
// session (anon key + auth cookies), so Row Level Security does the isolation: a student reads only
// their own enrollment and its sections. No server-only key is used here. Import from Server
// Components and Server Actions only.

export type EnrollmentStatus = 'Pending' | 'Approved' | 'Rejected'

export type StudentEnrollment = {
  id: number
  yearLevel: number
  status: EnrollmentStatus
  submittedAt: string
  reviewedAt: string | null
  remarks: string | null
}

export type EnrollmentSectionInfo = {
  sectionId: number
  sectionCode: string
  subjectCode: string
  subjectTitle: string
  units: number
  schedule: string | null
  capacity: number
}

/** A section the student has put in the enrollment (itemId is what removing it needs). */
export type ChosenSection = EnrollmentSectionInfo & { itemId: number }

export type StudentEnrollmentState =
  | {
      kind: 'ready'
      term: CurrentTerm
      /** The student's enrollment for the current term; null until they submit one. */
      enrollment: StudentEnrollment | null
      chosen: ChosenSection[]
      /** Sections of the current term not chosen yet (the picker). */
      available: EnrollmentSectionInfo[]
    }
  | { kind: 'no-term' }
  | { kind: 'error' }

const toStatus = (s: string): EnrollmentStatus => (s === 'Approved' || s === 'Rejected' ? s : 'Pending')

// The current term, the signed-in student's enrollment for it (if any) with its sections, and the
// sections still open to pick. Never throws: failures come back as { kind: 'error' }.
export async function getStudentEnrollmentState(): Promise<StudentEnrollmentState> {
  try {
    const supabase = await createClient()
    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) return { kind: 'error' }

    const term = await getCurrentTerm()
    if (!term) return { kind: 'no-term' }

    const [enrRes, secRes] = await Promise.all([
      supabase
        .from('enrollments')
        .select('enrollment_id, year_level, status, submitted_at, reviewed_at, remarks')
        .eq('student_id', user.id)
        .eq('term_id', term.termId)
        .limit(1)
        .maybeSingle(),
      supabase
        .from('sections')
        .select('section_id, subject_id, section_code, schedule, capacity')
        .eq('term_id', term.termId),
    ])
    if (enrRes.error || secRes.error) return { kind: 'error' }

    const enrRow = enrRes.data
    const enrollment: StudentEnrollment | null = enrRow
      ? {
          id: enrRow.enrollment_id,
          yearLevel: enrRow.year_level,
          status: toStatus(enrRow.status),
          submittedAt: enrRow.submitted_at,
          reviewedAt: enrRow.reviewed_at,
          remarks: enrRow.remarks,
        }
      : null

    const itemsRes = enrRow
      ? await supabase.from('enrollment_items').select('enrollment_item_id, section_id').eq('enrollment_id', enrRow.enrollment_id)
      : { data: [], error: null }
    if (itemsRes.error) return { kind: 'error' }

    const sectionRows = secRes.data ?? []
    const subjectIds = [...new Set(sectionRows.map((s) => s.subject_id))]
    const subRes = subjectIds.length
      ? await supabase.from('subjects').select('subject_id, code, title, units').in('subject_id', subjectIds)
      : { data: [], error: null }
    if (subRes.error) return { kind: 'error' }
    const subjects = new Map((subRes.data ?? []).map((s) => [s.subject_id, s]))

    const infos = new Map<number, EnrollmentSectionInfo>(
      sectionRows.map((s) => {
        const sub = subjects.get(s.subject_id)
        return [
          s.section_id,
          {
            sectionId: s.section_id,
            sectionCode: s.section_code,
            subjectCode: sub?.code ?? '-',
            subjectTitle: sub?.title ?? '-',
            units: sub?.units ?? 0,
            schedule: s.schedule,
            capacity: s.capacity,
          },
        ]
      })
    )

    const chosen: ChosenSection[] = (itemsRes.data ?? []).flatMap((i) => {
      const info = infos.get(i.section_id)
      return info ? [{ ...info, itemId: i.enrollment_item_id }] : []
    })
    chosen.sort((a, b) => a.subjectCode.localeCompare(b.subjectCode) || a.sectionCode.localeCompare(b.sectionCode))

    const chosenIds = new Set(chosen.map((c) => c.sectionId))
    const available = [...infos.values()]
      .filter((s) => !chosenIds.has(s.sectionId))
      .sort((a, b) => a.subjectCode.localeCompare(b.subjectCode) || a.sectionCode.localeCompare(b.sectionCode))

    return { kind: 'ready', term, enrollment, chosen, available }
  } catch {
    return { kind: 'error' }
  }
}
