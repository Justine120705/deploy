'use client'

import { useActionState } from 'react'
import { Button, Select } from '@/components/ui'
import { addEnrollmentSection, type EnrollmentActionState } from '@/lib/data/enrollment-actions'
import type { EnrollmentSectionInfo } from '@/lib/data/enrollment'

const INITIAL: EnrollmentActionState = { status: 'idle', message: '' }

// Section picker for a Pending enrollment (server action). Capacity is the section size; seats left
// are not shown because the student cannot see other students' enrollments.
export default function EnrollmentAddSectionForm({
  enrollmentId,
  sections,
}: {
  enrollmentId: number
  sections: EnrollmentSectionInfo[]
}) {
  const [state, formAction, pending] = useActionState(addEnrollmentSection, INITIAL)

  return (
    <form
      id="add-section"
      action={formAction}
      className="flex scroll-mt-4 flex-col gap-4 rounded-lg border border-edge bg-card p-4 lg:p-5"
    >
      <input type="hidden" name="enrollmentId" value={enrollmentId} />
      <Select id="add-section-select" name="sectionId" label="Subject section" required error={state.fieldErrors?.section}>
        {sections.map((s) => (
          <option key={s.sectionId} value={s.sectionId}>
            {`${s.subjectCode} ${s.subjectTitle} - Section ${s.sectionCode}, ${s.units} units, ${s.schedule ?? 'schedule to be announced'}, capacity ${s.capacity}`}
          </option>
        ))}
      </Select>
      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={pending} aria-disabled={pending}>
          {pending ? 'Adding...' : 'Add section'}
        </Button>
        <p
          role="status"
          aria-live="polite"
          className={state.status === 'error' ? 'max-w-[48ch] text-sm font-medium text-danger' : 'max-w-[48ch] text-sm text-muted'}
        >
          {state.message}
        </p>
      </div>
    </form>
  )
}
