import Link from 'next/link'
import DashboardShell from '@/components/layout/DashboardShell'
import PromoCard from '@/components/layout/PromoCard'
import { BarChart, LegendItem, LineChart } from '@/components/charts'
import { ClearanceChain } from '@/components/student/ClearanceChain'
import { NextLesson } from '@/components/student/NextLesson'
import {
  Card,
  CardHeader,
  EventCalendar,
  PhotoBanner,
  ScheduleList,
  StatusBadge,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { requireRole } from '@/lib/auth/session'
import { MOCK_STUDENT_ID, students, MOCK_CURRENT_TERM_ID, vClearanceItems, vActiveHolds } from '@/lib/mock-data'
import {
  CALENDAR_EVENTS,
  CALENDAR_VIEW,
  CURRENT_GRADES,
  DASHBOARD_UNITS_THIS_TERM,
  GWA_BY_TERM,
  GWA_Y_TICKS,
  NEXT_CLASS,
  SCHEDULE,
} from '@/lib/mock/student-dashboard'

const SEE_ALL = 'inline-flex items-center text-sm font-semibold max-lg:min-h-11 text-accent-foreground hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const TH = 'text-sm'
const ON_VEIL_LINK =
  'inline-flex h-10 items-center gap-2 rounded-md bg-on-veil px-4 text-sm font-bold text-(--veil-violet) shadow-elev-sm max-lg:h-11 transition-colors hover:bg-on-veil-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-on-veil'

// Greeting by the hour in the Philippines (the server may run in another time zone).
function greeting() {
  const hour = Number(
    new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone: 'Asia/Manila' }).format(new Date())
  )
  return hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening'
}

export default async function StudentDashboardPage() {
  const profile = await requireRole('Student')
  const student = students.find((s) => s.student_id === MOCK_STUDENT_ID)

  // One GWA series drives both charts. Lower is better: the latest term is highlighted on the bars and
  // the best (lowest) term is pinned on the line.
  const latest = GWA_BY_TERM[GWA_BY_TERM.length - 1]
  const bestIndex = GWA_BY_TERM.reduce((b, t, i) => (t.gwa < GWA_BY_TERM[b].gwa ? i : b), 0)
  const best = GWA_BY_TERM[bestIndex]
  const gwaSummary = GWA_BY_TERM.map((t) => `${t.full} ${t.gwa.toFixed(2)}`).join(', ')

  // A bar's height is its distance below 3.25, so the best GWA is the tallest bar.
  const bars = GWA_BY_TERM.map((t) => ({
    label: t.short,
    value: 3.25 - t.gwa,
    display: t.gwa.toFixed(2),
    highlight: t === latest,
  }))

  // Clearance: the same data as the Clearance page, so both screens tell one story. Signing order: the
  // Cashier's Office (Financial) first, then the academic departments.
  const offices = vClearanceItems
    .filter((i) => i.student_id === MOCK_STUDENT_ID && i.term_id === MOCK_CURRENT_TERM_ID)
    .sort((a, b) => Number(b.department_type === 'Financial') - Number(a.department_type === 'Financial'))
    .map((i) => {
      const name = i.department_name ?? 'Department'
      return i.status === 'Cleared'
        ? { name, status: 'Cleared' as const, reason: '', nextAction: '' }
        : { name, status: 'Pending' as const, reason: i.remarks ?? 'Awaiting review', nextAction: `Request clearance from ${name}.` }
    })
  const activeHolds = vActiveHolds.filter((h) => h.student_id === MOCK_STUDENT_ID).length

  return (
    <DashboardShell
      profile={profile}
      userMeta={student ? `ID ${student.student_number}` : undefined}
      promo={
        <PromoCard
          value={DASHBOARD_UNITS_THIS_TERM}
          label="Units this term"
          note="Keep it up!"
          image="graduation-cap-books"
        />
      }
    >
      <h1 className="sr-only">Student dashboard</h1>
      {/*
        One grid so the phone reading order is: banner, clearance, next class, then the rest. On xl the
        third column holds the calendar, schedule and next class; the 1fr last row soaks up the left
        column's extra height so the right column never pushes the left one down.
      */}
      <div className="grid gap-4 md:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)_304px] xl:grid-rows-[auto_auto_auto_auto_1fr]">
        <PhotoBanner
          className="md:col-span-2 xl:col-start-1 xl:row-start-1"
          image="study-desk"
          title={`${greeting()}, ${profile.firstName}`}
          subtitle="Here is your clearance, your grades and today's classes."
          aside={
            <Link href="/student/clearance" className={ON_VEIL_LINK}>
              Open clearance
            </Link>
          }
        />

        <ClearanceChain
          className="md:col-start-1 md:row-start-2"
          offices={offices}
          activeHolds={activeHolds}
        />

        <NextLesson
          className="md:col-span-2 md:row-start-3 xl:col-span-1 xl:col-start-3 xl:row-start-4 xl:self-start"
          seconds={NEXT_CLASS.seconds}
          title={NEXT_CLASS.title}
          code={NEXT_CLASS.code}
          startsAt={NEXT_CLASS.startsAt}
        />

        <Card className="flex flex-col gap-3 p-5 md:col-start-2 md:row-start-2">
          <CardHeader tinted title="GWA by term" icon="grades" hue="violet" />
          <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
            <p className="flex flex-col">
              <span className="text-3xl font-extrabold">{latest.gwa.toFixed(2)}</span>
              <span className="text-sm text-muted">GWA, {latest.full}</span>
            </p>
            <p className="text-sm font-semibold text-muted">Lower is better</p>
          </div>
          <p className="sr-only">GWA by term, oldest first: {gwaSummary}.</p>
          <div aria-hidden="true" className="mt-auto">
            <BarChart data={bars} max={1.5} hue="violet" ariaLabel="GWA by term" />
          </div>
        </Card>

        <div className="flex min-w-0 flex-col gap-4 md:col-span-2 xl:col-start-1 xl:row-start-3 xl:row-span-3">
          <Card className="flex flex-col gap-2 px-6 py-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex flex-wrap items-baseline gap-x-3">
                <h2 className="text-base font-bold leading-[22px]">Progress</h2>
                <p className="text-sm font-semibold text-muted">Lower is better</p>
              </div>
              <LegendItem color="var(--hue-violet-strong)">GWA</LegendItem>
            </div>
            <p className="sr-only">GWA by term, oldest first: {gwaSummary}. Best: {best.full}, {best.gwa.toFixed(2)}.</p>
            <div aria-hidden="true">
              <LineChart
                values={GWA_BY_TERM.map((t) => t.gwa)}
                yTicks={GWA_Y_TICKS}
                xLabels={GWA_BY_TERM.map((t) => t.short)}
                hue="violet"
                mark={{ index: bestIndex, label: `Best ${best.gwa.toFixed(2)}` }}
                ariaLabel="GWA progress"
              />
            </div>
            <p className="text-sm text-muted">Y1 S1 means Year 1, 1st semester.</p>
          </Card>

          <Card className="flex flex-col overflow-hidden">
            <CardHeader tinted
              title="Current grades"
              icon="grades"
              hue="violet"
              className="px-[18px] py-4"
              action={
                <Link href="/student/grades" aria-label="See all grades" className={SEE_ALL}>
                  See all
                </Link>
              }
            />
            <div className="overflow-x-auto">
              <table className="w-full min-w-[480px] text-left text-sm">
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead className={`${TH} w-[76px] px-3.5`}>Code</TableHead>
                    <TableHead className={TH}>Course</TableHead>
                    <TableHead className={`${TH} w-14`}>Units</TableHead>
                    <TableHead className={`${TH} w-[60px]`}>Grade</TableHead>
                    <TableHead className={`${TH} w-28`}>Remarks</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {CURRENT_GRADES.map((g) => (
                    <TableRow key={g.code}>
                      <TableCell>{g.code}</TableCell>
                      <TableCell>{g.course}</TableCell>
                      <TableCell>{g.units}</TableCell>
                      <TableCell className="font-bold">{g.grade}</TableCell>
                      <TableCell>
                        <StatusBadge status={g.remarks} className="text-sm" />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </table>
            </div>
          </Card>
        </div>

        <div className="flex flex-col gap-4 md:col-span-2 xl:col-span-1 xl:col-start-3 xl:row-start-1 xl:row-span-3 xl:self-start">
          <Card className="p-5">
            <CardHeader title="Event calendar" className="mb-3" />
            <EventCalendar
              year={CALENDAR_VIEW.year}
              month={CALENDAR_VIEW.month}
              today={CALENDAR_VIEW.today}
              events={CALENDAR_EVENTS}
            />
          </Card>

          <Card className="flex flex-col gap-3 p-5">
            <CardHeader tinted
              title="My schedule"
              icon="enrollment"
              hue="sky"
              action={
                <Link href="/student/enrollment" aria-label="See all classes" className={SEE_ALL}>
                  See all
                </Link>
              }
            />
            <ScheduleList items={SCHEDULE} />
          </Card>
        </div>
      </div>
    </DashboardShell>
  )
}
