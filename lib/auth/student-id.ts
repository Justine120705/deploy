// Students sign in with their student ID (for example 2026-0001). Supabase Auth needs an email, so the
// ID is mapped to a fixed internal address. The domain is not a real mailbox; nothing is sent to it.
export const STUDENT_EMAIL_DOMAIN = 'students.pnc.test'

export function studentIdToEmail(id: string): string {
  return `${id.trim().toLowerCase()}@${STUDENT_EMAIL_DOMAIN}`
}

export function looksLikeStudentId(input: string): boolean {
  return /^\d{4}-\d{4,6}$/.test(input.trim())
}
