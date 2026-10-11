import { createClient } from '@/lib/supabase/server'
import type { Json } from '@/types/database.types'

// Server-side read of the append-only audit log. Runs with the signed-in user's own session; RLS
// lets only the Admin read audit_logs (everyone else gets zero rows). There is no write function
// here on purpose: the log cannot be edited or deleted. Import from Server Components only.

export const AUDIT_PAGE_SIZE = 200

export type AuditAction = 'Insert' | 'Update' | 'Delete'

export type AuditEntry = {
  id: number
  /** Asia/Manila, formatted on the server so server and client output are identical. */
  when: string
  actor: string
  action: AuditAction
  /** Readable table name, e.g. "Clearance item". */
  table: string
  /** Raw table name, kept for search and CSV. */
  rawTable: string
  record: string
  details: string
}

export type AuditLogState =
  | { kind: 'ready'; entries: AuditEntry[]; total: number }
  | { kind: 'error' }

const TABLE_LABELS: Record<string, string> = {
  profiles: 'Profile',
  students: 'Student',
  department_staff: 'Department staff',
  clearances: 'Clearance',
  clearance_items: 'Clearance item',
  academic_holds: 'Hold',
  charges: 'Charge',
  payments: 'Payment',
  grades: 'Grade',
  enrollments: 'Enrollment',
  document_requests: 'Document request',
}

function tableLabel(raw: string): string {
  if (TABLE_LABELS[raw]) return TABLE_LABELS[raw]
  const spaced = raw.replace(/_/g, ' ').trim()
  return spaced.charAt(0).toUpperCase() + spaced.slice(1)
}

function actionLabel(raw: string): AuditAction {
  const a = raw.toUpperCase()
  return a === 'INSERT' ? 'Insert' : a === 'DELETE' ? 'Delete' : 'Update'
}

const manila = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Manila',
  year: 'numeric',
  month: 'short',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hourCycle: 'h23',
})

function formatWhen(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  const p = Object.fromEntries(manila.formatToParts(d).map((x) => [x.type, x.value]))
  return `${p.day} ${p.month} ${p.year}, ${p.hour}:${p.minute}:${p.second} PHT`
}

function isObject(v: Json | null | undefined): v is { [key: string]: Json | undefined } {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function show(v: Json | undefined): string {
  if (v === null || v === undefined) return 'empty'
  const s = typeof v === 'object' ? JSON.stringify(v) : String(v)
  return s.length > 60 ? `${s.slice(0, 57)}...` : s
}

const MAX_FIELDS = 6

function summarise(action: AuditAction, oldData: Json | null, newData: Json | null): string {
  const o = isObject(oldData) ? oldData : {}
  const n = isObject(newData) ? newData : {}
  if (action === 'Update') {
    const keys = Object.keys(n).filter((k) => JSON.stringify(o[k]) !== JSON.stringify(n[k]))
    if (keys.length === 0) return 'No field values changed'
    const parts = keys.slice(0, MAX_FIELDS).map((k) => `${k}: ${show(o[k])} -> ${show(n[k])}`)
    if (keys.length > MAX_FIELDS) parts.push(`and ${keys.length - MAX_FIELDS} more`)
    return parts.join('; ')
  }
  const src = action === 'Insert' ? n : o
  const keys = Object.keys(src).filter((k) => src[k] !== null && src[k] !== undefined)
  if (keys.length === 0) return action === 'Insert' ? 'New record' : 'Record removed'
  const parts = keys.slice(0, MAX_FIELDS).map((k) => `${k}: ${show(src[k])}`)
  if (keys.length > MAX_FIELDS) parts.push(`and ${keys.length - MAX_FIELDS} more`)
  return parts.join('; ')
}

export async function getAuditLogState(): Promise<AuditLogState> {
  try {
    const supabase = await createClient()
    const { data, error, count } = await supabase
      .from('audit_logs')
      .select('log_id, actor_id, action, table_name, record_id, old_data, new_data, created_at', {
        count: 'exact',
      })
      .order('created_at', { ascending: false })
      .order('log_id', { ascending: false })
      .limit(AUDIT_PAGE_SIZE)
    if (error) return { kind: 'error' }
    const rows = data ?? []

    const actorIds = [...new Set(rows.map((r) => r.actor_id).filter((id): id is string => id !== null))]
    const names = new Map<string, string>()
    if (actorIds.length > 0) {
      const { data: people, error: pErr } = await supabase
        .from('profiles')
        .select('profile_id, first_name, last_name')
        .in('profile_id', actorIds)
      if (pErr) return { kind: 'error' }
      for (const p of people ?? []) names.set(p.profile_id, `${p.first_name} ${p.last_name}`.trim())
    }

    const entries: AuditEntry[] = rows.map((r) => {
      const action = actionLabel(r.action)
      return {
        id: r.log_id,
        when: formatWhen(r.created_at),
        actor: r.actor_id === null ? 'System' : (names.get(r.actor_id) ?? `User ${r.actor_id.slice(0, 8)}`),
        action,
        table: tableLabel(r.table_name),
        rawTable: r.table_name,
        record: r.record_id,
        details: summarise(action, r.old_data, r.new_data),
      }
    })
    return { kind: 'ready', entries, total: count ?? entries.length }
  } catch {
    return { kind: 'error' }
  }
}
