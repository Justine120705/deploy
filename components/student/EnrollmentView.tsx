'use client'

import { useState } from 'react'
import { Button, Card, CardHeader, Input, Select, StatusBadge, type Hue } from '@/components/ui'
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
    {
      key: 'status',
      header: 'Status',
      badge: true,
      cell: () => <StatusBadge status={current?.status ?? 'Pending'} className="text-sm" />,
    },
  ]

  return (
    <div className="flex flex-col gap-4">
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

      <ResponsiveTable
        columns={columns}
        rows={currentSections}
        rowKey={(s) => s.section_id}
        caption={`Enrolled subjects, ${termLabel(defaultTermId)}`}
        empty="You are not enrolled for this term yet. Use the form below."
        footer={`Showing ${currentSections.length} of ${currentSections.length} subjects`}
      />

      <Card className="p-5" id="new-enrollment">
        <CardHeader title="New enrollment" icon="enrollment" hue="sky" />
        <form onSubmit={handleSubmit} noValidate className="mt-4 flex flex-col gap-5">
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
            <legend className="mb-1 text-sm font-semibold">Subject sections</legend>
            {termSections.length === 0 ? (
              <p className="text-sm text-muted">No sections are open for this term.</p>
            ) : (
              termSections.map((s) => (
                <label
                  key={s.section_id}
                  className="flex min-h-11 cursor-pointer items-start gap-3 rounded-xl border border-border bg-card p-3 text-sm hover:bg-accent has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-ring"
                >
                  <Input
                    type="checkbox"
                    className="mt-0.5 size-5 shrink-0 accent-primary"
                    checked={selected.includes(s.section_id)}
                    onChange={() => toggle(s.section_id)}
                  />
                  <span className="flex flex-col gap-0.5">
                    <span>
                      <span className="font-semibold">{s.section_code}</span>
                      <span className="text-muted"> · </span>
                      <span className="font-semibold">{s.subject_code}</span> {s.subject_title}
                    </span>
                    <span className="text-muted">
                      {s.units} units · {s.schedule ?? 'Schedule to be announced'} · Capacity{' '}
                      {s.capacity}
                    </span>
                  </span>
                </label>
              ))
            )}
            {error && (
              <p role="alert" className="text-sm text-danger">
                {error}
              </p>
            )}
          </fieldset>

          <div className="flex flex-wrap items-center gap-3">
            <Button type="submit" className="max-lg:h-11">
              Submit enrollment
            </Button>
            <span className="text-sm text-muted">New enrollments start as Pending.</span>
          </div>
        </form>
      </Card>

      {enrollments.length > 0 && (
        <Card className="p-5">
          <CardHeader title="Enrollment history" />
          <ul className="mt-3 divide-y divide-border-subtle text-sm">
            {enrollments.map((en) => (
              <li key={en.id} className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 py-3">
                <span className="flex flex-col">
                  <span className="font-semibold">{termLabel(en.term_id)}</span>
                  <span className="text-muted">
                    Year {en.year_level} · Submitted {formatShortDate(en.submitted_at)} ·{' '}
                    {en.section_ids.length} subjects
                  </span>
                </span>
                <StatusBadge status={en.status} className="text-sm" />
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  )
}
