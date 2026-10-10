import Link from 'next/link'
import DashboardShell from '@/components/layout/DashboardShell'
import { Icon } from '@/components/layout/Icon'
import PromoCard from '@/components/layout/PromoCard'
import { BarChart, GaugeChart, LegendItem, LineChart } from '@/components/charts'
import { ClearanceOfficesList } from '@/components/student/ClearanceOfficesList'
import { NextLesson } from '@/components/student/NextLesson'
import {
  Card,
  CardHeader,
  CardMenuButton,
  EventCalendar,
  ScheduleList,
  StatusBadge,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { cn } from '@/lib/utils'
import { requireRole } from '@/lib/auth/session'
import { MOCK_STUDENT_ID, students } from '@/lib/mock-data'
import {
  CALENDAR_EVENTS,
  CALENDAR_VIEW,
  CLEARANCE_OFFICES,
  CLEARANCE_SUMMARY,
  CURRENT_GRADES,
  CURRENT_GWA_TERM,
  DASHBOARD_UNITS_THIS_TERM,
  GWA_BY_TERM,
  GWA_PROGRESS,
  GWA_PROGRESS_X_LABELS,
  GWA_PROGRESS_Y_TICKS,
  NEXT_LESSON,
  PENDING_ITEMS,
  SCHEDULE,
} from '@/lib/mock/student-dashboard'

const SEE_ALL = 'text-sm font-semibold text-accent-foreground hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const TH = 'text-sm'

export default async function StudentDashboardPage() {
  const profile = await requireRole('Student')
  const student = students.find((s) => s.student_id === MOCK_STUDENT_ID)
  const clearedPercent = Math.round((CLEARANCE_SUMMARY.cleared / CLEARANCE_SUMMARY.total) * 100)

  // Lower GWA is better, so the bar height is the distance below 3.25 (T5, 1.75, is the tallest).
  // Best (lowest) point of the progress line, pinned on the chart.
  const best = GWA_PROGRESS.indexOf(Math.min(...GWA_PROGRESS))

  const bars = GWA_BY_TERM.map((t) => ({
    label: t.term,
    value: 3.25 - t.gwa,
    display: t.gwa.toFixed(2),
    highlight: t.term === CURRENT_GWA_TERM,
  }))

  return (
    <DashboardShell
      profile={profile}
      userMeta={student ? `ID ${student.student_number}` : undefined}
      promo={<PromoCard value={DASHBOARD_UNITS_THIS_TERM} label="Units this term" note="Keep it up!" />}
    >
      <h1 className="sr-only">Student dashboard</h1>
      <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_304px]">
        <div className="flex min-w-0 flex-col gap-4">
          <div className="grid gap-4 md:grid-cols-3">
            <Card className="flex min-h-[214px] flex-col gap-3 p-5">
              <CardHeader title="Clearance" icon="clearance" hue="teal" action={<CardMenuButton />} />
              <div className="flex h-28 items-center justify-center">
                <GaugeChart
                  value={clearedPercent}
                  color="var(--hue-teal-solid)"
                  trackColor="var(--hue-amber-solid)"
                  ariaLabel={`Clearance ${clearedPercent} percent complete, ${CLEARANCE_SUMMARY.cleared} of ${CLEARANCE_SUMMARY.total} offices cleared`}
                />
              </div>
              <div className="flex justify-center gap-4">
                <LegendItem color="var(--hue-teal-solid)">Cleared</LegendItem>
                <LegendItem color="var(--hue-amber-solid)">Pending</LegendItem>
              </div>
            </Card>

            <Card className="flex min-h-[214px] flex-col gap-3 p-5">
              <CardHeader title="GWA by term" icon="grades" hue="violet" action={<CardMenuButton />} />
              <BarChart data={bars} max={1.5} hue="violet" ariaLabel="GWA by term" />
            </Card>

            <Card className="flex min-h-[214px] flex-col gap-3 p-5">
              <CardHeader title="Pending items" icon="clock" hue="amber" action={<CardMenuButton />} />
              {PENDING_ITEMS.map((p) => (
                <div key={p.title} className="flex flex-col gap-1.5 text-sm">
                  <div className="flex items-center justify-between gap-2">
                    <p className="font-bold">{p.title}</p>
                    {/* The value word itself says the state; the hue only repeats it. */}
                    <p className={cn('font-semibold', p.attention ? 'text-hue-amber-strong' : 'text-hue-teal-strong')}>
                      {p.value}
                    </p>
                  </div>
                  <p className="text-muted">{p.note}</p>
                </div>
              ))}
            </Card>
          </div>

          <Card className="flex flex-col gap-2 px-6 py-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-base font-bold leading-[22px]">Progress</h2>
              <div className="flex items-center gap-3">
                <LegendItem color="var(--hue-violet-strong)">GWA</LegendItem>
                <div className="relative">
                  <select
                    aria-label="Term range"
                    defaultValue="all"
                    className="appearance-none rounded-lg border border-border-subtle bg-lilac-soft py-1.5 pl-3 pr-8 text-sm font-medium text-neutral focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                  >
                    <option value="all">All terms</option>
                  </select>
                  <Icon
                    name="chevron-down"
                    className="pointer-events-none absolute right-3 top-1/2 size-3.5 -translate-y-1/2 text-neutral"
                  />
                </div>
              </div>
            </div>
            <LineChart
              values={GWA_PROGRESS}
              yTicks={GWA_PROGRESS_Y_TICKS}
              xLabels={GWA_PROGRESS_X_LABELS}
              hue="violet"
              mark={{ index: best, label: `Best ${GWA_PROGRESS[best].toFixed(2)}` }}
              ariaLabel="GWA progress across all terms"
            />
          </Card>

          <div className="grid items-stretch gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
            <Card className="flex flex-col overflow-hidden">
              <CardHeader
                title="Current grades"
                icon="grades"
                hue="violet"
                className="px-[18px] py-4"
                action={
                  <Link href="/student/grades" className={SEE_ALL}>
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

            <Card className="flex flex-col pb-2">
              <CardHeader
                title="Clearance offices"
                icon="clearance"
                hue="teal"
                className="px-[18px] py-4"
                action={
                  <Link href="/student/clearance" className={SEE_ALL}>
                    See all
                  </Link>
                }
              />
              <ClearanceOfficesList offices={CLEARANCE_OFFICES} />
            </Card>
          </div>
        </div>

        <div className="flex flex-col gap-4 xl:self-start">
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
            <CardHeader
              title="My schedule"
              icon="enrollment"
              hue="sky"
              action={
                <Link href="/student/enrollment" className={SEE_ALL}>
                  See all
                </Link>
              }
            />
            <ScheduleList items={SCHEDULE} />
            <NextLesson seconds={NEXT_LESSON.seconds} title={NEXT_LESSON.title} />
          </Card>
        </div>
      </div>
    </DashboardShell>
  )
}
