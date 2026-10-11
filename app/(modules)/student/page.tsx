import Link from 'next/link'
import DashboardShell from '@/components/layout/DashboardShell'
import { LineChart } from '@/components/charts'
import { ClearanceRoute } from '@/components/student/ClearanceRoute'
import { NextLesson } from '@/components/student/NextLesson'
import {
  ScheduleList,
  Section,
  StatusBadge,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { MOCK_CURRENT_TERM_ID, MOCK_STUDENT_ID, documentRequests, documentTypes, programs, students, terms, vClearanceItems, vActiveHolds } from '@/lib/mock-data'
import {
  CALENDAR_EVENTS,
  CALENDAR_VIEW,
  CURRENT_GRADES,
  GWA_BY_TERM,
  GWA_Y_TICKS,
  NEXT_CLASS,
  SCHEDULE,
} from '@/lib/mock/student-dashboard'

const FOCUS = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const SEE_ALL = `inline-flex items-center text-sm font-semibold text-accent-foreground hover:underline max-lg:min-h-11 ${FOCUS}`
const PRIMARY_LINK = `inline-flex h-9 items-center justify-center rounded-md bg-primary px-3.5 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary-hover max-lg:h-11 max-lg:px-4 ${FOCUS}`
const SHEET = 'rounded-lg border border-edge bg-card'
// A ruled row that is one link: name on the left, a drawn chevron on the right.
const ROW_LINK = `group flex min-h-11 items-center justify-between gap-3 px-4 py-2.5 text-sm font-medium transition-colors hover:bg-hover-tint ${FOCUS} focus-visible:-outline-offset-2`

const QUICK_ACTIONS = [
  { href: '/student/documents', label: 'Request a document' },
  { href: '/student/grades', label: 'View grades' },
  { href: '/student/enrollment', label: 'Enrollment' },
] as const

// Greeting by the hour in the Philippines (the server may run in another time zone).
function greeting() {
  const hour = Number(
    new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone: 'Asia/Manila' }).format(new Date())
  )
  return hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening'
}

// Calendar dates are plain YYYY-MM-DD; read them as Philippine dates so server and browser agree.
const EVENT_DAY = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: 'Asia/Manila' })
const EVENT_DATE = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', timeZone: 'Asia/Manila' })
const asManilaDate = (ymd: string) => new Date(`${ymd}T12:00:00+08:00`)

function Chevron() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 16 16"
      fill="none"
      className="size-4 shrink-0 text-muted transition-colors group-hover:text-foreground"
    >
      <path d="m6 3.5 4.5 4.5L6 12.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export default async function StudentDashboardPage() {
  const profile = await requireRole('Student')
  const student = students.find((s) => s.student_id === MOCK_STUDENT_ID)
  const term = terms.find((t) => t.term_id === MOCK_CURRENT_TERM_ID)
  const program = programs.find((p) => p.program_id === student?.program_id)
  const context = [term ? `${term.semester} ${term.school_year}` : null, program?.code, student ? `ID ${student.student_number}` : null]
    .filter(Boolean)
    .join(' · ')

  // Clearance: the same data as the Clearance page, so both screens tell one story. Signing order: the
  // Cashier's Office (Financial) first, then the academic departments.
  const offices = vClearanceItems
    .filter((i) => i.student_id === MOCK_STUDENT_ID && i.term_id === MOCK_CURRENT_TERM_ID)
    .sort((a, b) => Number(b.department_type === 'Financial') - Number(a.department_type === 'Financial'))
    .map((i) => {
      const name = i.department_name ?? 'Department'
      return i.status === 'Cleared'
        ? { name, status: 'Cleared' as const, reason: '', nextAction: '' }
        : {
            name,
            status: 'Pending' as const,
            reason: i.remarks ?? 'Awaiting review',
            nextAction: `Request clearance from ${name}.`,
          }
    })
  const activeHolds = vActiveHolds.filter((h) => h.student_id === MOCK_STUDENT_ID).length

  // Pending items: the student's document requests that are not released yet.
  const openRequests = documentRequests
    .filter((r) => r.student_id === MOCK_STUDENT_ID && (r.status === 'Pending' || r.status === 'Processing'))
    .map((r) => ({
      id: r.request_id,
      ticket: r.ticket_number,
      status: r.status,
      title: documentTypes.find((d) => d.document_type_id === r.document_type_id)?.name ?? 'Document request',
      copies: r.copies,
    }))

  // Coming up: every calendar date from today on, in date order.
  const upcoming = CALENDAR_EVENTS.flatMap((e) => e.dates.map((date) => ({ id: `${e.id}-${date}`, date, title: e.title })))
    .filter((e) => e.date >= CALENDAR_VIEW.today)
    .sort((a, b) => a.date.localeCompare(b.date))

  // One GWA series. Lower is better; the best (lowest) term is pinned on the line.
  const latest = GWA_BY_TERM[GWA_BY_TERM.length - 1]
  const bestIndex = GWA_BY_TERM.reduce((b, t, i) => (t.gwa < GWA_BY_TERM[b].gwa ? i : b), 0)
  const best = GWA_BY_TERM[bestIndex]
  const gwaSummary = GWA_BY_TERM.map((t) => `${t.full} ${t.gwa.toFixed(2)}`).join(', ')

  return (
    <DashboardShell profile={profile} userMeta={student ? `ID ${student.student_number}` : undefined}>
      <div className="flex flex-col gap-8 lg:gap-10">
        <div className="flex flex-col gap-4">
          <header>
            <h1 className="text-xl font-semibold">
              {greeting()}, {profile.firstName}
            </h1>
            {context && <p className="mt-0.5 text-sm text-muted">{context}</p>}
          </header>

          <ClearanceRoute
            offices={offices}
            activeHolds={activeHolds}
            action={
              <Link href="/student/clearance" className={PRIMARY_LINK}>
                Open clearance
              </Link>
            }
          />
        </div>

        <div className="grid gap-8 lg:grid-cols-2 lg:gap-6">
          <Section
            title="Classes"
            action={
              <Link href="/student/enrollment" aria-label="See all classes" className={SEE_ALL}>
                See all
              </Link>
            }
          >
            <div className={SHEET}>
              <NextLesson
                className="px-4 py-3.5"
                title={NEXT_CLASS.title}
                code={NEXT_CLASS.code}
                startsAt={NEXT_CLASS.startsAt}
              />
              <div className="border-t border-border-subtle px-4 py-3.5">
                <h3 className="mb-3 text-sm font-semibold">Weekly schedule</h3>
                <ScheduleList items={SCHEDULE} />
              </div>
            </div>
          </Section>

          <div className="flex flex-col gap-8">
            <Section title="Tasks">
              <div className={SHEET}>
                {openRequests.length === 0 ? (
                  <p className="px-4 py-3.5 text-sm text-muted">Nothing waiting on you right now.</p>
                ) : (
                  <ul className="divide-y divide-border-subtle">
                    {openRequests.map((r) => (
                      <li key={r.id}>
                        <Link href="/student/documents" className={ROW_LINK}>
                          <span className="flex min-w-0 flex-col">
                            <span className="truncate font-semibold">{r.title}</span>
                            <span className="text-muted">
                              {r.ticket} · {r.copies} {r.copies === 1 ? 'copy' : 'copies'}
                            </span>
                          </span>
                          <span className="flex shrink-0 items-center gap-2">
                            <StatusBadge status={r.status} />
                            <Chevron />
                          </span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                )}
                <ul aria-label="Quick actions" className="divide-y divide-border-subtle border-t border-border-subtle">
                  {QUICK_ACTIONS.map((a) => (
                    <li key={a.href}>
                      <Link href={a.href} className={`${ROW_LINK} text-accent-foreground`}>
                        {a.label}
                        <Chevron />
                      </Link>
                    </li>
                  ))}
                </ul>
              </div>
            </Section>

            <Section title="Coming up">
              {upcoming.length === 0 ? (
                <p className="text-sm text-muted">No dates on the calendar.</p>
              ) : (
                <ol className={`${SHEET} divide-y divide-border-subtle`}>
                  {upcoming.map((e) => {
                    const d = asManilaDate(e.date)
                    return (
                      <li key={e.id} className="flex items-baseline gap-4 px-4 py-2.5 text-sm">
                        <time dateTime={e.date} className="w-24 shrink-0 tabular-nums text-muted">
                          {EVENT_DAY.format(d)}, {EVENT_DATE.format(d)}
                        </time>
                        <span className="min-w-0 font-medium">{e.title}</span>
                      </li>
                    )
                  })}
                </ol>
              )}
            </Section>
          </div>
        </div>

        <Section
          title="Current grades"
          description={`Latest term with grades: ${latest.full}`}
          action={
            <Link href="/student/grades" aria-label="See all grades" className={SEE_ALL}>
              See all
            </Link>
          }
        >
          <p className="text-sm">
            GWA <span className="text-base font-semibold tabular-nums">{latest.gwa.toFixed(2)}</span>
            <span className="text-muted">. Lower is better; 1.00 is the highest grade.</span>
          </p>
          <div className="grid gap-6 lg:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)]">
            <Table className="min-w-[320px]">
              <caption className="sr-only">Current grades, {latest.full}</caption>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead scope="col" className="max-sm:px-3">Course</TableHead>
                  <TableHead scope="col" className="w-14 max-sm:px-2">Units</TableHead>
                  <TableHead scope="col" className="w-16 max-sm:px-2">Grade</TableHead>
                  <TableHead scope="col" className="w-24 max-sm:px-3">Remarks</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {CURRENT_GRADES.map((g) => (
                  <TableRow key={g.code}>
                    <TableCell className="max-sm:px-3">
                      <span className="flex flex-col">
                        <span className="font-medium">{g.course}</span>
                        <span className="text-xs text-muted">{g.code}</span>
                      </span>
                    </TableCell>
                    <TableCell className="max-sm:px-2">{g.units}</TableCell>
                    <TableCell className="font-semibold max-sm:px-2">{g.grade}</TableCell>
                    <TableCell className="max-sm:px-3">
                      <StatusBadge status={g.remarks} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>

            <figure className={`${SHEET} flex flex-col gap-3 p-4`}>
              <figcaption className="flex flex-col">
                <span className="text-sm font-semibold">GWA by term</span>
                <span className="text-xs text-muted">
                  Oldest term first. The scale is flipped so a better (lower) GWA sits higher.
                </span>
              </figcaption>
              <p className="sr-only">
                GWA by term, oldest first: {gwaSummary}. Best: {best.full}, {best.gwa.toFixed(2)}.
              </p>
              <div aria-hidden="true">
                <LineChart
                  values={GWA_BY_TERM.map((t) => t.gwa)}
                  yTicks={GWA_Y_TICKS}
                  xLabels={GWA_BY_TERM.map((t) => t.short)}
                  hue="violet"
                  mark={{ index: bestIndex, label: `Best ${best.gwa.toFixed(2)}` }}
                  ariaLabel="GWA by term"
                />
              </div>
              <p className="text-xs text-muted">Y1 S1 means Year 1, 1st semester.</p>
            </figure>
          </div>
        </Section>
      </div>
    </DashboardShell>
  )
}
