'use client'

import { useId, useState } from 'react'
import { Button, Card, CardHeader, EmptyRow, Input, Select, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats } from '@/components/department/DeptStats'
import { HoldStatusBadge } from '@/components/department/DeptBadges'
import { RecordList, type RecordItem } from '@/components/department/RecordList'
import { DEPT_HOLDS, DEPT_STUDENTS, DEPT_USER, studentByNo, type DeptHold } from '@/lib/mock/department-data'

const TODAY = 'Oct 10, 2026'

// Mock-only hold state: nothing is saved. A hold always shows its reason and who placed it.
export default function HoldsClient() {
  const [holds, setHolds] = useState<DeptHold[]>(DEPT_HOLDS)
  const [studentNo, setStudentNo] = useState('')
  const [reason, setReason] = useState('')
  const [errors, setErrors] = useState<{ student?: string; reason?: string }>({})
  const studentId = useId()
  const reasonId = useId()

  function place() {
    const next: { student?: string; reason?: string } = {}
    if (!studentNo) next.student = 'Choose a student.'
    if (!reason.trim()) next.reason = 'Enter the reason for the hold.'
    setErrors(next)
    if (next.student || next.reason) return
    setHolds((prev) => [
      {
        id: `hold-${prev.length + 1}-${studentNo}`,
        studentNo,
        reason: reason.trim(),
        placedBy: DEPT_USER,
        placedOn: TODAY,
        status: 'Active',
        liftedOn: null,
      },
      ...prev,
    ])
    setStudentNo('')
    setReason('')
  }

  function lift(id: string) {
    setHolds((prev) => prev.map((h) => (h.id === id ? { ...h, status: 'Lifted', liftedOn: TODAY } : h)))
  }

  const active = holds.filter((h) => h.status === 'Active')
  const lifted = holds.filter((h) => h.status === 'Lifted')
  const affected = new Set(holds.map((h) => h.studentNo)).size

  function liftButton(h: DeptHold) {
    if (h.status !== 'Active') return <span className="text-sm text-muted">Lifted</span>
    return (
      <Button
        variant="outline"
        className="h-11 lg:h-10"
        aria-label={`Lift hold for ${studentByNo(h.studentNo).name}`}
        onClick={() => lift(h.id)}
      >
        Lift hold
      </Button>
    )
  }

  const mobile: RecordItem[] = holds.map((h) => {
    const s = studentByNo(h.studentNo)
    return {
      key: h.id,
      title: s.name,
      subtitle: s.studentNo,
      badge: <HoldStatusBadge status={h.status} />,
      fields: [
        { label: 'Reason', value: h.reason },
        { label: 'Placed by', value: h.placedBy },
        { label: 'Placed on', value: h.placedOn },
        { label: 'Lifted on', value: h.liftedOn ?? 'Not lifted' },
      ],
      footer: h.status === 'Active' ? liftButton(h) : undefined,
    }
  })

  return (
    <div className="flex flex-col gap-4">
      <DeptStats
        stats={[
          { label: 'Active', value: active.length, hint: 'hold', hue: 'rose' },
          { label: 'Lifted', value: lifted.length, hint: 'this term' },
          { label: 'Placed', value: holds.length, hint: 'this term' },
          { label: 'Students', value: affected, hint: 'affected' },
        ]}
      />

      <Card className="p-5">
        <CardHeader title="Place a hold" icon="holds" hue="rose" />
        <form
          className="mt-4 grid gap-4 md:grid-cols-[1fr_1.5fr_auto] md:items-start"
          onSubmit={(e) => {
            e.preventDefault()
            place()
          }}
          noValidate
        >
          <Select
            id={studentId}
            label="Student"
            value={studentNo}
            error={errors.student}
            onChange={(e) => setStudentNo(e.target.value)}
          >
            <option value="">Choose a student</option>
            {DEPT_STUDENTS.map((s) => (
              <option key={s.studentNo} value={s.studentNo}>
                {s.name} ({s.studentNo})
              </option>
            ))}
          </Select>
          <Input
            id={reasonId}
            label="Reason"
            value={reason}
            error={errors.reason}
            onChange={(e) => setReason(e.target.value)}
          />
          <Button type="submit" className="h-11 md:mt-[26px]">
            Place hold
          </Button>
        </form>
        <p className="mt-3 text-sm text-muted">
          Placed by {DEPT_USER}. Holds are academic only; finance is handled by the Cashier.
        </p>
      </Card>

      <div className="hidden md:block">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead scope="col">Student no.</TableHead>
              <TableHead scope="col">Student name</TableHead>
              <TableHead scope="col">Reason</TableHead>
              <TableHead scope="col">Placed by</TableHead>
              <TableHead scope="col">Placed on</TableHead>
              <TableHead scope="col">Status</TableHead>
              <TableHead scope="col">Lifted on</TableHead>
              <TableHead scope="col">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {holds.length === 0 && <EmptyRow colSpan={8}>No holds placed.</EmptyRow>}
            {holds.map((h) => {
              const s = studentByNo(h.studentNo)
              return (
                <TableRow key={h.id}>
                  <TableCell className="font-normal text-muted">{s.studentNo}</TableCell>
                  <TableCell className="font-semibold">{s.name}</TableCell>
                  <TableCell className="font-normal text-muted">{h.reason}</TableCell>
                  <TableCell className="font-normal text-muted">{h.placedBy}</TableCell>
                  <TableCell className="font-normal text-muted">{h.placedOn}</TableCell>
                  <TableCell><HoldStatusBadge status={h.status} /></TableCell>
                  <TableCell className="font-normal text-muted">{h.liftedOn ?? 'Not lifted'}</TableCell>
                  <TableCell>{liftButton(h)}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
      <div className="surface rounded-2xl border border-edge bg-card shadow-elev-sm md:hidden">
        <RecordList items={mobile} empty="No holds placed." />
      </div>

      <p className="text-sm text-muted">Changes on this screen are examples and are not saved.</p>
    </div>
  )
}
