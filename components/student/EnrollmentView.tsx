'use client'

import { useState } from 'react'
import { Button, Card, CardHeader, Input, Select, StatusBadge } from '@/components/ui'

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

  return (
    <div className="flex flex-col gap-6">
      <Card className="p-5">
        <CardHeader title="New enrollment" />
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
                  className="flex cursor-pointer items-start gap-3 rounded-xl border border-border bg-card p-3 text-sm hover:bg-accent"
                >
                  <Input
                    type="checkbox"
                    className="mt-0.5 size-4 shrink-0 accent-primary"
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

          <div className="flex items-center gap-3">
            <Button type="submit">Submit enrollment</Button>
            <span className="text-sm text-muted">New enrollments start as Pending.</span>
          </div>
        </form>
      </Card>

      <div className="flex flex-col gap-3">
        <h2 className="text-base font-bold">Your enrollments</h2>
        {enrollments.length === 0 && <p className="text-sm text-muted">No enrollments yet.</p>}
        {enrollments.map((en) => (
          <Card key={en.id} className="p-5">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="font-semibold">{termLabel(en.term_id)}</p>
                <p className="text-sm text-muted">
                  Year {en.year_level} · Submitted {en.submitted_at.slice(0, 10)}
                </p>
              </div>
              <StatusBadge status={en.status} />
            </div>
            <ul className="mt-3 divide-y divide-border text-sm">
              {en.section_ids.map((id) => {
                const s = sectionById.get(id)
                if (!s) return null
                return (
                  <li key={id} className="flex flex-wrap justify-between gap-x-4 py-2">
                    <span>
                      <span className="font-semibold">{s.subject_code}</span> {s.subject_title}
                      <span className="text-muted"> ({s.section_code})</span>
                    </span>
                    <span className="text-muted">
                      {s.units} units · {s.schedule ?? 'TBA'}
                    </span>
                  </li>
                )
              })}
            </ul>
          </Card>
        ))}
      </div>
    </div>
  )
}
