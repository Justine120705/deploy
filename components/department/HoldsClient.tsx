'use client'

import { useActionState, useId } from 'react'
import { Button, EmptyRow, Input, Section, Select, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats, type DeptStat } from '@/components/department/DeptStats'
import { HoldStatusBadge } from '@/components/department/DeptBadges'
import { ActionMessage, DEPT_IDLE } from '@/components/department/DeptNotice'
import { RecordList, type RecordItem } from '@/components/department/RecordList'
import { liftHold, placeHold, type DeptActionState } from '@/lib/data/department-actions'
import type { HoldRow, PickerStudent } from '@/lib/data/department'

// Live holds screen. A hold always shows its reason, who placed it and when. Placing writes
// academic_holds (placed_by = the signed-in user); lifting writes lifted_at and lifted_by. Both run on
// the server, so the dates come from the server.
export default function HoldsClient({
  holds,
  students,
  stats,
  departmentName,
}: {
  holds: HoldRow[]
  students: PickerStudent[]
  stats: DeptStat[]
  departmentName: string
}) {
  const [placeState, placeAction, placing] = useActionState<DeptActionState, FormData>(placeHold, DEPT_IDLE)
  const [liftState, liftAction, lifting] = useActionState<DeptActionState, FormData>(liftHold, DEPT_IDLE)
  const studentId = useId()
  const reasonId = useId()

  const active = holds.filter((h) => h.status === 'Active')
  const lifted = holds.filter((h) => h.status === 'Lifted')

  // The latest result of either action goes in the one status region under the form.
  const last = liftState.stamp > placeState.stamp ? liftState : placeState
  // After success the form starts empty again; after an error it keeps what was typed.
  const keep = placeState.status === 'error' ? placeState.values : undefined

  function liftButton(h: HoldRow) {
    return (
      <form action={liftAction}>
        <input type="hidden" name="holdId" value={h.holdId} />
        <input type="hidden" name="studentName" value={h.name} />
        <Button type="submit" variant="outline" disabled={lifting} aria-label={`Lift hold for ${h.name}`}>
          Lift hold
        </Button>
      </form>
    )
  }

  const activeMobile: RecordItem[] = active.map((h) => ({
    key: String(h.holdId),
    title: h.name,
    subtitle: h.studentNo,
    badge: <HoldStatusBadge status={h.status} />,
    fields: [
      { label: 'Reason', value: h.reason },
      { label: 'Placed by', value: h.placedByName },
      { label: 'Placed on', value: h.placedOn },
    ],
    footer: liftButton(h),
  }))

  const liftedMobile: RecordItem[] = lifted.map((h) => ({
    key: String(h.holdId),
    title: h.name,
    subtitle: h.studentNo,
    badge: <HoldStatusBadge status={h.status} />,
    fields: [
      { label: 'Reason', value: h.reason },
      { label: 'Placed by', value: h.placedByName },
      { label: 'Placed on', value: h.placedOn },
      { label: 'Lifted on', value: h.liftedOn ?? 'Not lifted' },
      ...(h.liftedByName ? [{ label: 'Lifted by', value: h.liftedByName }] : []),
    ],
  }))

  return (
    <div className="flex flex-col gap-6">
      <DeptStats stats={stats} />

      <Section
        title="Place a hold"
        description={`For students of ${departmentName}. Holds are academic only; finance is handled by the Cashier.`}
      >
        <form
          key={placeState.stamp}
          className="grid gap-3 md:grid-cols-[1fr_1.5fr_auto] md:items-start"
          action={placeAction}
          noValidate
        >
          <Select
            id={studentId}
            name="studentId"
            label="Student"
            defaultValue={keep?.studentId ?? ''}
            error={placeState.status === 'error' && placeState.field === 'student' ? placeState.message : undefined}
          >
            <option value="">Choose a student</option>
            {students.map((s) => (
              <option key={s.studentId} value={s.studentId}>
                {s.name} ({s.studentNo})
              </option>
            ))}
          </Select>
          <Input
            id={reasonId}
            name="reason"
            label="Reason"
            maxLength={300}
            autoComplete="off"
            defaultValue={keep?.reason ?? ''}
            error={placeState.status === 'error' && placeState.field === 'reason' ? placeState.message : undefined}
          />
          <Button type="submit" disabled={placing} className="md:mt-[26px]">
            {placing ? 'Placing...' : 'Place hold'}
          </Button>
        </form>
        {students.length === 0 && (
          <p className="text-sm text-muted">
            No students of your department have requested clearance yet, so there is nobody to place a hold on.
          </p>
        )}
        <ActionMessage state={last.field ? { ...last, message: last.status === 'error' ? '' : last.message } : last} />
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
              {active.map((h) => (
                <TableRow key={h.holdId}>
                  <TableCell>
                    <span className="block font-semibold">{h.name}</span>
                    <span className="block text-xs text-muted">{h.studentNo}</span>
                  </TableCell>
                  <TableCell className="max-w-72 whitespace-normal">{h.reason}</TableCell>
                  <TableCell className="text-muted">{h.placedByName}</TableCell>
                  <TableCell className="text-muted">{h.placedOn}</TableCell>
                  <TableCell><HoldStatusBadge status={h.status} /></TableCell>
                  <TableCell>{liftButton(h)}</TableCell>
                </TableRow>
              ))}
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
                <TableHead scope="col">Lifted by</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {lifted.length === 0 && <EmptyRow colSpan={6}>No lifted holds yet.</EmptyRow>}
              {lifted.map((h) => (
                <TableRow key={h.holdId}>
                  <TableCell>
                    <span className="block font-semibold">{h.name}</span>
                    <span className="block text-xs text-muted">{h.studentNo}</span>
                  </TableCell>
                  <TableCell className="max-w-72 whitespace-normal">{h.reason}</TableCell>
                  <TableCell className="text-muted">{h.placedByName}</TableCell>
                  <TableCell className="text-muted">{h.placedOn}</TableCell>
                  <TableCell className="text-muted">{h.liftedOn ?? 'Not lifted'}</TableCell>
                  <TableCell className="text-muted">{h.liftedByName ?? '-'}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
        <RecordList className="md:hidden" items={liftedMobile} empty="No lifted holds yet." />
      </Section>
    </div>
  )
}
