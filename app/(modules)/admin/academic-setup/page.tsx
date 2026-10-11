import DashboardShell from '@/components/layout/DashboardShell'
import TableCard from '@/components/admin/TableCard'
import { requireRole } from '@/lib/auth/session'
import {
  Button,
  SummaryStrip,
  StatusBadge,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import { getAcademicSetup } from '@/lib/mock/admin-data'

const MUTED = 'font-normal text-muted'

function Head({ cols }: { cols: string[] }) {
  return (
    <TableHeader>
      <TableRow className="hover:bg-transparent">
        {cols.map((c) => (
          <TableHead key={c} scope="col">
            {c}
          </TableHead>
        ))}
      </TableRow>
    </TableHeader>
  )
}

export default async function AdminAcademicSetupPage() {
  const profile = await requireRole('Admin')
  const setup = getAcademicSetup()

  // Adding records needs the database; until then the buttons are off and the reason is on screen.
  const addButton = (label: string) => (
    <Button variant="outline" disabled aria-describedby="setup-reason">
      {label}
    </Button>
  )

  return (
    <DashboardShell profile={profile} title="Academic Setup" subtitle="Terms, programs, departments, subjects and sections">
      <div className="flex flex-col gap-6">
        <SummaryStrip
          items={[
            { label: 'Terms', value: setup.termCount, hint: `current: ${setup.currentLabel}` },
            { label: 'Programs', value: setup.programCount, hint: setup.programRows.map((p) => p.code).join(', ') },
            { label: 'Subjects', value: setup.subjectCount, hint: 'this term' },
            { label: 'Sections', value: setup.sectionCount, hint: 'open' },
          ]}
        />

        <p id="setup-reason" className="text-sm text-muted">
          Adding terms and programs is turned off until the database is connected.
        </p>

        <TableCard title="Terms" action={addButton('Add term')} minWidth="min-w-[560px]">
          <Head cols={['School year', 'Semester', 'Start', 'End', 'Status']} />
          <TableBody>
            {setup.termRows.map((t) => (
              <TableRow key={t.id}>
                <TableCell>{t.schoolYear}</TableCell>
                <TableCell className={MUTED}>{t.semester}</TableCell>
                <TableCell className={`whitespace-nowrap ${MUTED}`}>{t.start}</TableCell>
                <TableCell className={`whitespace-nowrap ${MUTED}`}>{t.end}</TableCell>
                <TableCell>
                  <StatusBadge status={t.status} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>

        <TableCard title="Programs" action={addButton('Add program')} minWidth="min-w-[600px]">
          <Head cols={['Code', 'Program', 'Department', 'Students']} />
          <TableBody>
            {setup.programRows.map((p) => (
              <TableRow key={p.id}>
                <TableCell>{p.code}</TableCell>
                <TableCell className={MUTED}>{p.name}</TableCell>
                <TableCell className={MUTED}>{p.department}</TableCell>
                <TableCell className={MUTED}>{p.students}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>

        <TableCard title="Departments" minWidth="min-w-[480px]">
          <Head cols={['Code', 'Name', 'Type']} />
          <TableBody>
            {setup.departmentRows.map((d) => (
              <TableRow key={d.id}>
                <TableCell>{d.code}</TableCell>
                <TableCell className={MUTED}>{d.name}</TableCell>
                <TableCell className={MUTED}>{d.type}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>

        <TableCard title="Subjects" minWidth="min-w-[600px]">
          <Head cols={['Code', 'Title', 'Units', 'Department']} />
          <TableBody>
            {setup.subjectRows.map((s) => (
              <TableRow key={s.id}>
                <TableCell>{s.code}</TableCell>
                <TableCell className={MUTED}>{s.title}</TableCell>
                <TableCell className={MUTED}>{s.units}</TableCell>
                <TableCell className={MUTED}>{s.department}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>

        <TableCard title="Sections" minWidth="min-w-[760px]">
          <Head cols={['Section', 'Subject', 'Term', 'Schedule', 'Capacity']} />
          <TableBody>
            {setup.sectionRows.map((s) => (
              <TableRow key={s.id}>
                <TableCell>{s.code}</TableCell>
                <TableCell className={MUTED}>{s.subject}</TableCell>
                <TableCell className={MUTED}>{s.term}</TableCell>
                <TableCell className={`whitespace-nowrap ${MUTED}`}>{s.schedule}</TableCell>
                <TableCell className={MUTED}>{s.capacity}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>
      </div>
    </DashboardShell>
  )
}
