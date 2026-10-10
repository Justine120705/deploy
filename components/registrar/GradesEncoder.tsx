'use client'

import { createContext, useContext, useMemo, useState } from 'react'
import { Badge, Button, Card, EmptyRow, Input, Select, Table, TableBody, TableCell, TableHead, TableHeader, TableRow, type BadgeTone } from '@/components/ui'
import { Icon } from '@/components/layout/Icon'
import { cn } from '@/lib/utils'
import { GRADE_SCALE, GRADE_SEEDS, type GradeSeed } from '@/lib/mock/registrar-data'
import StatGrid from './StatGrid'

const PAGE_SIZE = 8

type RowStatus = 'Saved' | 'Unsaved' | 'Not encoded' | 'Invalid grade'
const TONE: Record<RowStatus, BadgeTone> = {
  Saved: 'success',
  Unsaved: 'warning',
  'Not encoded': 'neutral',
  'Invalid grade': 'danger',
}

// "1.5" and "1.50" are the same grade; anything outside the scale gives null.
function normalize(value: string): string | null {
  const n = Number(value.trim())
  if (!value.trim() || Number.isNaN(n)) return null
  const key = n.toFixed(2)
  return key in GRADE_SCALE ? key : null
}

function statusOf(r: GradeSeed): RowStatus {
  const g = r.grade.trim()
  if (!g) return r.saved ? 'Unsaved' : 'Not encoded'
  const key = normalize(g)
  if (!key) return 'Invalid grade'
  return key === r.saved ? 'Saved' : 'Unsaved'
}

type Ctx = {
  rows: GradeSeed[]
  setGrade: (no: string, grade: string) => void
  submit: () => void
  canSubmit: boolean
  note: string
}

const Context = createContext<Ctx | null>(null)

function useGrades() {
  const ctx = useContext(Context)
  if (!ctx) throw new Error('GradesEncoder parts must be inside GradesProvider')
  return ctx
}

export function GradesProvider({ children }: { children: React.ReactNode }) {
  const [rows, setRows] = useState(GRADE_SEEDS)
  const [note, setNote] = useState('')

  const canSubmit = rows.some((r) => statusOf(r) === 'Unsaved' && r.grade.trim() !== '')

  function setGrade(no: string, grade: string) {
    setNote('')
    setRows((rs) => rs.map((r) => (r.no === no ? { ...r, grade } : r)))
  }

  function submit() {
    let saved = 0
    const next = rows.map((r) => {
      const key = normalize(r.grade)
      if (statusOf(r) === 'Unsaved' && key) {
        saved += 1
        return { ...r, grade: key, saved: key }
      }
      return r
    })
    const invalid = next.filter((r) => statusOf(r) === 'Invalid grade').length
    setRows(next)
    setNote(
      `${saved} ${saved === 1 ? 'grade' : 'grades'} submitted.` +
        (invalid ? ` ${invalid} ${invalid === 1 ? 'row needs' : 'rows need'} a valid grade first.` : '') +
        ' This is a preview and is not saved.',
    )
  }

  return <Context.Provider value={{ rows, setGrade, submit, canSubmit, note }}>{children}</Context.Provider>
}

export function GradesActions() {
  const { submit, canSubmit } = useGrades()
  return (
    <div className="flex flex-wrap items-center gap-2 max-sm:w-full">
      <Button variant="outline" disabled className="max-lg:h-11 max-sm:flex-1" aria-describedby="csv-reason">
        Import CSV
      </Button>
      <Button disabled={!canSubmit} onClick={submit} className="gap-2 max-lg:h-11 max-sm:flex-1">
        <Icon name="check" className="size-4" />
        Submit grades
      </Button>
    </div>
  )
}

export function GradesBody() {
  const { rows, setGrade, note } = useGrades()
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(1)

  const statuses = useMemo(() => rows.map(statusOf), [rows])
  const encoded = statuses.filter((s) => s === 'Saved' || s === 'Unsaved').length
  const unsaved = statuses.filter((s) => s === 'Unsaved').length
  const errors = statuses.filter((s) => s === 'Invalid grade').length

  const q = query.trim().toLowerCase()
  const visible = rows
    .map((r, i) => ({ r, status: statuses[i] }))
    .filter(({ r }) => !q || r.name.toLowerCase().includes(q) || r.no.includes(q))
  const pages = Math.max(1, Math.ceil(visible.length / PAGE_SIZE))
  const current = Math.min(page, pages)
  const slice = visible.slice((current - 1) * PAGE_SIZE, current * PAGE_SIZE)
  const from = visible.length ? (current - 1) * PAGE_SIZE + 1 : 0
  const to = (current - 1) * PAGE_SIZE + slice.length

  return (
    <div className="flex flex-col gap-4">
      <StatGrid
        items={[
          { label: 'Students', value: rows.length, hint: 'in this section' },
          { label: 'Encoded', value: encoded, hint: `of ${rows.length}` },
          { label: 'Unsaved', value: unsaved, hint: 'changes pending', hue: unsaved ? 'amber' : undefined },
          { label: 'Errors', value: errors, hint: 'needs attention', hue: errors ? 'rose' : undefined },
        ]}
      />

      <Card className="p-5">
        <div className="grid gap-4 sm:grid-cols-3 lg:grid-cols-[1.4fr_1fr_1fr_2fr]">
          <Select label="Course / Section" id="grades-course" disabled defaultValue="cs101">
            <option value="cs101">CS101 · Intro to Computing</option>
          </Select>
          <Select label="School year" id="grades-year" disabled defaultValue="2026-2027">
            <option>2026-2027</option>
          </Select>
          <Select label="Semester" id="grades-sem" disabled defaultValue="1st">
            <option value="1st">1st Semester</option>
          </Select>
          <div className="sm:col-span-3 lg:col-span-1">
            <Input
              label="Search student"
              id="grades-search"
              type="search"
              placeholder="Name or student number"
              value={query}
              onChange={(e) => {
                setQuery(e.target.value)
                setPage(1)
              }}
            />
          </div>
        </div>
        <p className="mt-3 text-sm text-muted">Only CS101 has sample data, so the section, year and semester are fixed.</p>
      </Card>

      <p aria-live="polite" className="px-1 text-sm text-muted">
        {note || 'Type a grade from the scale (1.00 to 3.00, or 5.00) and press Submit grades to save.'}
      </p>
      <p id="csv-reason" className="-mt-2 px-1 text-sm text-muted">
        Import CSV is not available yet.
      </p>

      <div>
        <Table className="min-w-[820px]">
          <TableHeader>
            <tr>
              <TableHead>Student no.</TableHead>
              <TableHead>Student name</TableHead>
              <TableHead>Grade</TableHead>
              <TableHead>Description</TableHead>
              <TableHead>Result</TableHead>
              <TableHead>Status</TableHead>
            </tr>
          </TableHeader>
          <TableBody>
            {slice.length === 0 && <EmptyRow colSpan={6}>No students match that search.</EmptyRow>}
            {slice.map(({ r, status }) => {
              const key = normalize(r.grade)
              const result = key ? (key === '5.00' ? 'Failed' : 'Passed') : '-'
              return (
                <TableRow
                  key={r.no}
                  className={cn(status === 'Unsaved' && 'bg-warning-soft/40', status === 'Invalid grade' && 'bg-danger-soft/40')}
                >
                  <TableCell className="font-normal text-muted">{r.no}</TableCell>
                  <TableCell className="font-semibold">{r.name}</TableCell>
                  <TableCell>
                    <Input
                      aria-label={`Grade for ${r.name}`}
                      inputMode="decimal"
                      autoComplete="off"
                      value={r.grade}
                      placeholder="-"
                      onChange={(e) => setGrade(r.no, e.target.value)}
                      className={cn('w-24 text-center', status === 'Invalid grade' && 'border-danger')}
                      aria-invalid={status === 'Invalid grade' ? true : undefined}
                    />
                  </TableCell>
                  <TableCell className="font-normal">{key ? GRADE_SCALE[key] : '-'}</TableCell>
                  <TableCell className="font-bold">{result}</TableCell>
                  <TableCell>
                    <Badge tone={TONE[status]}>{status}</Badge>
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>

        <div className="flex flex-wrap items-center justify-between gap-3 px-1 pt-3">
          <p className="text-sm text-muted">
            Showing {from}-{to} of {visible.length} students
          </p>
          <nav aria-label="Pages" className="flex items-center gap-1.5">
            <Button
              variant="outline"
              aria-label="Previous page"
              disabled={current === 1}
              onClick={() => setPage(current - 1)}
              className="size-11 px-0 lg:size-10"
            >
              ‹
            </Button>
            {Array.from({ length: pages }, (_, i) => i + 1).map((p) => (
              <Button
                key={p}
                variant={p === current ? 'primary' : 'outline'}
                aria-label={`Page ${p}`}
                aria-current={p === current ? 'page' : undefined}
                onClick={() => setPage(p)}
                className="size-11 px-0 lg:size-10"
              >
                {p}
              </Button>
            ))}
            <Button
              variant="outline"
              aria-label="Next page"
              disabled={current === pages}
              onClick={() => setPage(current + 1)}
              className="size-11 px-0 lg:size-10"
            >
              ›
            </Button>
          </nav>
        </div>
      </div>
    </div>
  )
}
