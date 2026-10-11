// Derived, display-ready mock data for the Admin screens. Reads the shared mock arrays and never
// changes them. Dates are formatted by hand from the ISO text (no Date, no locale), so the server
// and the browser always print the same thing.
import {
  auditLogs,
  departmentStaff,
  departments,
  getRoleName,
  profiles,
  programs,
  roles,
  sections,
  students,
  subjects,
  terms,
} from '@/lib/mock-data'

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/** "2026-08-01..." to "Aug 1, 2026". */
export function formatDay(iso: string): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  return `${MONTHS[m - 1]} ${d}, ${y}`
}

/** "2026-08-01T14:05..." to "Aug 1, 2:05 PM" (wall-clock time as written in the data). */
export function formatWhen(iso: string): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  const [hh, mm] = iso.slice(11, 16).split(':').map(Number)
  const hour = hh % 12 === 0 ? 12 : hh % 12
  return `${MONTHS[m - 1]} ${d}, ${y}, ${hour}:${String(mm).padStart(2, '0')} ${hh < 12 ? 'AM' : 'PM'}`
}

export type AdminUserRow = {
  id: string
  name: string
  email: string
  role: string
  department: string
  active: boolean
  created: string
}

export function getAdminUsers(): AdminUserRow[] {
  return profiles.map((p) => {
    const staff = departmentStaff.find((s) => s.profile_id === p.profile_id)
    const student = students.find((s) => s.student_id === p.profile_id)
    const department = staff
      ? departments.find((d) => d.department_id === staff.department_id)?.name
      : programs.find((pr) => pr.program_id === student?.program_id)?.code
    return {
      id: p.profile_id,
      name: `${p.first_name} ${p.last_name}`,
      email: p.email,
      role: getRoleName(p.role_id) ?? 'Unknown',
      department: department ?? 'None',
      active: p.is_active,
      created: formatDay(p.created_at),
    }
  })
}

export const ROLE_NAMES = roles.map((r) => r.role_name)

export function getRoleCounts() {
  return roles.map((r) => {
    const all = profiles.filter((p) => p.role_id === r.role_id)
    const active = all.filter((p) => p.is_active).length
    return { role: r.role_name, users: all.length, active, inactive: all.length - active }
  })
}

export type AuditAction = 'Insert' | 'Update' | 'Delete'

export type AuditRow = {
  id: number
  when: string
  sortKey: string
  actor: string
  action: AuditAction
  table: string
  record: string
  details: string
}

function actionLabel(raw: string): AuditAction {
  const a = raw.toUpperCase()
  return a === 'INSERT' ? 'Insert' : a === 'DELETE' ? 'Delete' : 'Update'
}

function detailsFor(
  action: AuditAction,
  oldData: unknown,
  newData: unknown
): string {
  const o = (oldData ?? {}) as Record<string, unknown>
  const n = (newData ?? {}) as Record<string, unknown>
  if (action === 'Update') {
    const key = Object.keys(n).find((k) => k in o && o[k] !== n[k])
    return key ? `${String(o[key])} to ${String(n[key])}` : 'Fields changed'
  }
  if (action === 'Insert') {
    if (typeof n.reason === 'string') return n.reason
    if (typeof n.status === 'string') return `Created as ${n.status}`
    return 'New record'
  }
  return 'Record removed'
}

/** Newest first. The log is append-only: nothing here is editable. */
export function getAuditRows(): AuditRow[] {
  return [...auditLogs]
    .sort((a, b) => b.created_at.localeCompare(a.created_at))
    .map((log) => {
      const actor = profiles.find((p) => p.profile_id === log.actor_id)
      const action = actionLabel(log.action)
      return {
        id: log.log_id,
        when: formatWhen(log.created_at),
        sortKey: log.created_at,
        actor: actor ? `${actor.first_name} ${actor.last_name}` : 'System',
        action,
        table: log.table_name,
        record: log.record_id ?? '-',
        details: detailsFor(action, log.old_data, log.new_data),
      }
    })
}

export function getAcademicSetup() {
  const current = terms.find((t) => t.is_current)
  const deptName = (id: number) => departments.find((d) => d.department_id === id)?.name ?? 'None'
  return {
    currentLabel: current ? current.semester : 'none',
    termRows: terms.map((t) => ({
      id: t.term_id,
      schoolYear: t.school_year,
      semester: t.semester,
      start: formatDay(t.start_date),
      end: formatDay(t.end_date),
      status: t.is_current ? 'Active' : 'Past',
    })),
    programRows: programs.map((p) => ({
      id: p.program_id,
      code: p.code,
      name: p.name,
      department: deptName(p.department_id),
      students: students.filter((s) => s.program_id === p.program_id).length,
    })),
    departmentRows: departments.map((d) => ({
      id: d.department_id,
      code: d.code,
      name: d.name,
      type: d.department_type,
    })),
    subjectRows: subjects.map((s) => ({
      id: s.subject_id,
      code: s.code,
      title: s.title,
      units: s.units,
      department: deptName(s.department_id),
    })),
    sectionRows: sections.map((s) => {
      const subject = subjects.find((x) => x.subject_id === s.subject_id)
      const term = terms.find((t) => t.term_id === s.term_id)
      return {
        id: s.section_id,
        code: s.section_code,
        subject: subject ? `${subject.code} ${subject.title}` : 'None',
        term: term ? `${term.semester}, ${term.school_year}` : 'None',
        schedule: s.schedule ?? 'To be announced',
        capacity: s.capacity,
      }
    }),
    programCount: programs.length,
    subjectCount: subjects.length,
    sectionCount: sections.length,
    termCount: terms.length,
  }
}
