import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/types/database.types'

// Server-side reads for the signed-in student's clearance. Every query runs with the user's own
// session (anon key + auth cookies), so Row Level Security does the isolation. No server-only key
// is used here. Import this file from Server Components and Server Actions only.

type Views = Database['public']['Views']
type ViewClearance = Views['v_clearances']['Row']
type ViewItem = Views['v_clearance_items']['Row']

export type CurrentTerm = { termId: number; schoolYear: string; semester: string }

export type ClearanceItem = {
  id: number
  departmentId: number | null
  name: string
  type: string
  status: 'Cleared' | 'Pending'
  clearedAt: string | null
  remarks: string | null
}

export type ActiveHold = { id: number; departmentId: number | null; reason: string | null }

export type StudentClearance = {
  clearanceId: number
  termId: number
  createdAt: string | null
  approvedAt: string | null
  approvedBy: string | null
  /** The Registrar has given the final approval. */
  approved: boolean
  totalItems: number
  clearedItems: number
  items: ClearanceItem[]
}

export type StudentClearanceState =
  | { kind: 'ready'; term: CurrentTerm; clearance: StudentClearance | null; holds: ActiveHold[] }
  | { kind: 'no-term' }
  | { kind: 'error' }

export async function getCurrentTerm(): Promise<CurrentTerm | null> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('terms')
    .select('term_id, school_year, semester')
    .eq('is_current', true)
    .order('term_id', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data ? { termId: data.term_id, schoolYear: data.school_year, semester: data.semester } : null
}

// Signing order: the Cashier's Office (Financial) first, then the academic departments.
function toItem(row: ViewItem): ClearanceItem | null {
  if (row.clearance_item_id === null) return null
  return {
    id: row.clearance_item_id,
    departmentId: row.department_id,
    name: row.department_name ?? 'Department',
    type: row.department_type ?? '-',
    status: row.status === 'Cleared' ? 'Cleared' : 'Pending',
    clearedAt: row.cleared_at,
    remarks: row.remarks,
  }
}

function toClearance(row: ViewClearance, items: ClearanceItem[]): StudentClearance | null {
  if (row.clearance_id === null || row.term_id === null) return null
  return {
    clearanceId: row.clearance_id,
    termId: row.term_id,
    createdAt: row.created_at,
    approvedAt: row.approved_at,
    approvedBy: row.approved_by,
    approved: row.approved_at !== null,
    totalItems: row.total_items ?? items.length,
    clearedItems: row.cleared_items ?? items.filter((i) => i.status === 'Cleared').length,
    items,
  }
}

// The current term plus the signed-in student's clearance for it (null when not requested yet), its
// items and the student's active holds. Never throws: failures come back as { kind: 'error' } so the
// page can show a calm message without internals.
export async function getStudentClearanceState(): Promise<StudentClearanceState> {
  try {
    const supabase = await createClient()
    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) return { kind: 'error' }

    const term = await getCurrentTerm()
    if (!term) return { kind: 'no-term' }

    const [clearanceRes, itemsRes, holdsRes] = await Promise.all([
      supabase
        .from('v_clearances')
        .select('clearance_id, student_id, term_id, created_at, approved_by, approved_at, total_items, cleared_items, status')
        .eq('student_id', user.id)
        .eq('term_id', term.termId)
        .limit(1)
        .maybeSingle(),
      supabase
        .from('v_clearance_items')
        .select(
          'clearance_item_id, clearance_id, student_id, term_id, department_id, department_name, department_type, cleared_at, cleared_by, remarks, status'
        )
        .eq('student_id', user.id)
        .eq('term_id', term.termId),
      supabase
        .from('v_active_holds')
        .select('hold_id, student_id, department_id, reason')
        .eq('student_id', user.id),
    ])
    if (clearanceRes.error || itemsRes.error || holdsRes.error) return { kind: 'error' }

    const items = (itemsRes.data ?? [])
      .map(toItem)
      .filter((i): i is ClearanceItem => i !== null)
      .sort((a, b) => Number(b.type === 'Financial') - Number(a.type === 'Financial') || a.id - b.id)
    const holds: ActiveHold[] = (holdsRes.data ?? []).flatMap((h) =>
      h.hold_id === null ? [] : [{ id: h.hold_id, departmentId: h.department_id, reason: h.reason }]
    )
    const clearance = clearanceRes.data ? toClearance(clearanceRes.data, items) : null

    return { kind: 'ready', term, clearance, holds }
  } catch {
    return { kind: 'error' }
  }
}

export type OfficeStep = {
  name: string
  status: 'Cleared' | 'Pending'
  /** Why the office has not cleared the student yet (empty when cleared). */
  reason: string
  /** What happens next (empty when cleared). */
  nextAction: string
}

// Maps live items to the steps the clearance chain and route draw. A pending office shows its remarks,
// or the reason of an active hold from that office, or "Awaiting review".
export function toOfficeSteps(items: readonly ClearanceItem[], holds: readonly ActiveHold[]): OfficeStep[] {
  return items.map((i) => {
    if (i.status === 'Cleared') return { name: i.name, status: 'Cleared', reason: '', nextAction: '' }
    const hold = holds.find((h) => h.departmentId !== null && h.departmentId === i.departmentId)
    return {
      name: i.name,
      status: 'Pending',
      reason: i.remarks ?? hold?.reason ?? 'Awaiting review',
      nextAction: `${i.name} is reviewing your clearance.`,
    }
  })
}
