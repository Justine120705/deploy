'use client'

import { useState } from 'react'
import { Button, Input, Section, Select, StatusBadge, type Hue } from '@/components/ui'
import { formatShortDate } from './format'
import { ResponsiveTable, type Column } from './ResponsiveTable'
import { StatGrid } from './StatGrid'

export type SectionOption = {
  section_id: number
  term_id: number
  section_code: string
  subject_code: string
  subject_title: string
  units: number
  schedule: string | null
  capacity: number
}

export type TermOption = { term_id: number; label: string }

export type EnrollmentRecord = {
  id: number
  term_id: number
  year_level: number
  status: string
  submitted_at: string
  section_ids: number[]
}

// UI only for now: submitting adds a Pending enrollment to local state, no backend call.
export default function EnrollmentView({
  terms,
  sections,
  initialEnrollments,
  defaultTermId,
}: {
  terms: TermOption[]
  sections: SectionOption[]
  initialEnrollments: EnrollmentRecord[]
  defaultTermId: number
}) {
  const [enrollments, setEnrollments] = useState(initialEnrollments)
  const [termId, setTermId] = useState(defaultTermId)
  const [yearLevel, setYearLevel] = useState(1)
  const [selected, setSelected] = useState<number[]>([])
  const [error, setError] = useState('')

  const termSections = sections.filter((s) => s.term_id === termId)
  const sectionById = new Map(sections.map((s) => [s.section_id, s]))
  const termLabel = (id: number) => terms.find((t) => t.term_id === id)?.label ?? ''

  function toggle(sectionId: number) {
    setError('')
    setSelected((prev) =>
      prev.includes(sectionId) ? prev.filter((id) => id !== sectionId) : [...prev, sectionId]
    )
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (selected.length === 0) {
      setError('Choose at least one subject section.')
      return
    }
    setEnrollments((prev) => [
      {
        id: Math.max(0, ...prev.map((en) => en.id)) + 1,
        term_id: termId,
        year_level: yearLevel,
        status: 'Pending',
        submitted_at: new Date().toISOString(),
        section_ids: selected,
      },
      ...prev,
    ])
    setSelected([])
    setError('')
  }

  // The current enrollment is the newest one for the default term.
  const current = [...enrollments]
    .filter((en) => en.term_id === defaultTermId)
    .sort((a, b) => b.submitted_at.localeCompare(a.submitted_at))[0]
  const currentSections = (current?.section_ids ?? []).flatMap((id) => {
    const s = sectionById.get(id)
    return s ? [s] : []
  })
  const currentUnits = currentSections.reduce((sum, s) => sum + s.units, 0)
  const statusHue: Record<string, Hue> = { Approved: 'teal', Pending: 'amber', Rejected: 'rose' }
  const statusHint: Record<string, string> = {
    Approved: 'by the Registrar',
    Pending: 'waiting for the Registrar',
    Rejected: 'see the Registrar',
  }

  const columns: Column<SectionOption>[] = [
    { key: 'code', header: 'Code', primary: true, cell: (s) => s.subject_code },
    { key: 'subject', header: 'Subject', cell: (s) => s.subject_title },
    { key: 'units', header: 'Units', className: 'w-20', cell: (s) => s.units },
    { key: 'section', header: 'Section', cell: (s) => s.section_code },
    { key: 'schedule', header: 'Schedule', cell: (s) => s.schedule ?? 'To be announced' },
  ]

  return (
    <div className="flex flex-col gap-8">
      <StatGrid
        stats={[
          {
            label: 'Status',
            value: current?.status ?? 'None',
            hint: current ? (statusHint[current.status] ?? 'this term') : 'not enrolled yet',
            hue: current ? statusHue[current.status] : undefined,
          },
          { label: 'Subjects', value: currentSections.length, hint: 'this term' },
          { label: 'Units', value: currentUnits, hint: 'total units' },
          {
            label: 'Submitted',
            value: current ? formatShortDate(current.submitted_at).replace(/, \d{4}$/, '') : '-',
            hint: current ? formatShortDate(current.submitted_at).slice(-4) : 'nothing submitted',
          },
        ]}
      />

      <Section title="Enrolled subjects" description={termLabel(defaultTermId)}>
        <ResponsiveTable
          columns={columns}
          rows={currentSections}
          rowKey={(s) => s.section_id}
          caption={`Enrolled subjects, ${termLabel(defaultTermId)}`}
          empty="You are not enrolled for this term yet. Use the form below."
        />
      </Section>

      <Section
        title="New enrollment"
        description="New enrollments start as Pending until the Registrar reviews them."
      >
        <form
          id="new-enrollment"
          onSubmit={handleSubmit}
          noValidate
          className="flex flex-col gap-5 rounded-lg border border-edge bg-card p-4 lg:p-5"
        >
          <div className="grid gap-4 sm:grid-cols-2">
            <Select
              id="enroll-term"
              label="Term"
              value={termId}
              onChange={(e) => {
                setTermId(Number(e.target.value))
                setSelected([])
                setError('')
              }}
            >
              {terms.map((t) => (
                <option key={t.term_id} value={t.term_id}>
                  {t.label}
                </option>
              ))}
            </Select>
            <Select
              id="enroll-year"
              label="Year level"
              value={yearLevel}
              onChange={(e) => setYearLevel(Number(e.target.value))}
            >
              {[1, 2, 3, 4].map((y) => (
                <option key={y} value={y}>
                  Year {y}
                </option>
              ))}
            </Select>
          </div>

          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-[13px] leading-5 font-medium">
              Subject sections{selected.length > 0 ? `, ${selected.length} selected` : ''}
            </legend>
            {termSections.length === 0 ? (
              <p className="text-sm text-muted">No sections are open for this term.</p>
            ) : (
              <div className="divide-y divide-border-subtle overflow-hidden rounded-md border border-field-border">
                {termSections.map((s) => (
                  <label
                    key={s.section_id}
                    className="flex min-h-11 cursor-pointer items-start gap-3 bg-card px-3 py-2.5 text-sm hover:bg-hover-tint has-focus-visible:outline-2 has-focus-visible:-outline-offset-2 has-focus-visible:outline-ring"
                  >
                    <Input
                      type="checkbox"
                      className="mt-0.5 size-5 shrink-0 accent-primary"
                      checked={selected.includes(s.section_id)}
                      onChange={() => toggle(s.section_id)}
                    />
                    <span className="flex min-w-0 flex-col gap-0.5">
                      <span>
                        <span className="font-semibold">{s.subject_code}</span> {s.subject_title}
                      </span>
                      <span className="text-muted">
                        Section {s.section_code} · {s.units} units · {s.schedule ?? 'Schedule to be announced'} ·
                        Capacity {s.capacity}
                      </span>
                    </span>
                  </label>
                ))}
              </div>
            )}
            {error && (
              <p role="alert" className="text-[13px] leading-5 text-danger">
                {error}
              </p>
            )}
          </fieldset>

          <div>
            <Button type="submit">Submit enrollment</Button>
          </div>
        </form>
      </Section>

      {enrollments.length > 0 && (
        <Section title="Enrollment history">
          <ul className="divide-y divide-border-subtle overflow-hidden rounded-lg border border-edge bg-card text-sm">
            {enrollments.map((en) => (
              <li key={en.id} className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-3">
                <span className="flex flex-col">
                  <span className="font-semibold">{termLabel(en.term_id)}</span>
                  <span className="text-muted">
                    Year {en.year_level} · Submitted {formatShortDate(en.submitted_at)} · {en.section_ids.length}{' '}
                    subjects
                  </span>
                </span>
                <StatusBadge status={en.status} />
              </li>
            ))}
          </ul>
        </Section>
      )}
    </div>
  )
}
