'use client'

import { useId, useState } from 'react'
import { Button, EmptyRow, Input, Section, Select, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats } from '@/components/department/DeptStats'
import { HoldStatusBadge } from '@/components/department/DeptBadges'
import { RecordList, type RecordItem } from '@/components/department/RecordList'
import { DEPT_HOLDS, DEPT_STUDENTS, DEPT_USER, studentByNo, todayLabel, type DeptHold } from '@/lib/mock/department-data'

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
        placedOn: todayLabel(),
        status: 'Active',
        liftedOn: null,
      },
      ...prev,
    ])
    setStudentNo('')
    setReason('')
  }

  function lift(id: string) {
    setHolds((prev) => prev.map((h) => (h.id === id ? { ...h, status: 'Lifted', liftedOn: todayLabel() } : h)))
  }

  const active = holds.filter((h) => h.status === 'Active')
  const lifted = holds.filter((h) => h.status === 'Lifted')
  const affected = new Set(active.map((h) => h.studentNo)).size

  function liftButton(h: DeptHold) {
    return (
      <Button
        variant="outline"
        aria-label={`Lift hold for ${studentByNo(h.studentNo).name}`}
        onClick={() => lift(h.id)}
      >
        Lift hold
      </Button>
    )
  }

  const activeMobile: RecordItem[] = active.map((h) => {
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
      ],
      footer: liftButton(h),
    }
  })

  const liftedMobile: RecordItem[] = lifted.map((h) => {
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
    }
  })

  return (
    <div className="flex flex-col gap-6">
      <DeptStats
        stats={[
          { label: 'Active holds', value: active.length, hint: 'block approval', hue: active.length ? 'rose' : undefined },
          { label: 'Students on hold', value: affected, hint: 'right now' },
          { label: 'Lifted', value: lifted.length, hint: 'this term' },
          { label: 'Placed', value: holds.length, hint: 'this term' },
        ]}
      />

      <Section
        title="Place a hold"
        description={`Placed by ${DEPT_USER}. Holds are academic only; finance is handled by the Cashier.`}
      >
        <form
          className="grid gap-3 md:grid-cols-[1fr_1.5fr_auto] md:items-start"
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
          <Button type="submit" className="md:mt-[26px]">
            Place hold
          </Button>
        </form>
      </Section>

      <Section title="Active holds">
        <div className="hidden md:block">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead scope="col">Student</TableHead>
                <TableHead scope="col">Reason</TableHead>
                <TableHead scope="col">Placed by</TableHead>
                <TableHead scope="col">Placed on</TableHead>
                <TableHead scope="col">Status</TableHead>
                <TableHead scope="col">Action</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {active.length === 0 && <EmptyRow colSpan={6}>No active holds.</EmptyRow>}
              {active.map((h) => {
                const s = studentByNo(h.studentNo)
                return (
                  <TableRow key={h.id}>
                    <TableCell>
                      <span className="block font-semibold">{s.name}</span>
                      <span className="block text-xs text-muted">{s.studentNo}</span>
                    </TableCell>
                    <TableCell className="max-w-72 whitespace-normal">{h.reason}</TableCell>
                    <TableCell className="text-muted">{h.placedBy}</TableCell>
                    <TableCell className="text-muted">{h.placedOn}</TableCell>
                    <TableCell><HoldStatusBadge status={h.status} /></TableCell>
                    <TableCell>{liftButton(h)}</TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </div>
        <RecordList className="md:hidden" items={activeMobile} empty="No active holds." />
      </Section>

      <Section title="Lifted holds">
        <div className="hidden md:block">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead scope="col">Student</TableHead>
                <TableHead scope="col">Reason</TableHead>
                <TableHead scope="col">Placed by</TableHead>
                <TableHead scope="col">Placed on</TableHead>
                <TableHead scope="col">Lifted on</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {lifted.length === 0 && <EmptyRow colSpan={5}>No lifted holds yet.</EmptyRow>}
              {lifted.map((h) => {
                const s = studentByNo(h.studentNo)
                return (
                  <TableRow key={h.id}>
                    <TableCell>
                      <span className="block font-semibold">{s.name}</span>
                      <span className="block text-xs text-muted">{s.studentNo}</span>
                    </TableCell>
                    <TableCell className="max-w-72 whitespace-normal">{h.reason}</TableCell>
                    <TableCell className="text-muted">{h.placedBy}</TableCell>
                    <TableCell className="text-muted">{h.placedOn}</TableCell>
                    <TableCell className="text-muted">{h.liftedOn ?? 'Not lifted'}</TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </div>
        <RecordList className="md:hidden" items={liftedMobile} empty="No lifted holds yet." />
      </Section>

      <p className="text-sm text-muted">Changes on this screen are examples and are not saved.</p>
    </div>
  )
}
