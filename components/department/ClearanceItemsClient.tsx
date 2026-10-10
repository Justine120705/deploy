'use client'

import { useId, useState } from 'react'
import { Button, Card, EmptyRow, Input, Section, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats } from '@/components/department/DeptStats'
import { ItemStatusBadge } from '@/components/department/DeptBadges'
import { RecordList, type RecordItem } from '@/components/department/RecordList'
import {
  DEPT_CLEARANCE_ITEMS,
  DEPT_HOLDS,
  DEPT_STUDENTS,
  studentByNo,
  todayLabel,
  type DeptClearanceItem,
} from '@/lib/mock/department-data'

// Mock-only review state: nothing is saved. Approval is blocked while the student has an active hold
// from this department (REQ-DPT-03).
export default function ClearanceItemsClient() {
  const [items, setItems] = useState<DeptClearanceItem[]>(DEPT_CLEARANCE_ITEMS)
  const [rejecting, setRejecting] = useState<string | null>(null)
  const [remarks, setRemarks] = useState('')
  const [error, setError] = useState('')
  const remarksId = useId()

  const activeHoldsFor = (no: string) => DEPT_HOLDS.filter((h) => h.studentNo === no && h.status === 'Active')
  const activeHoldCount = DEPT_HOLDS.filter((h) => h.status === 'Active').length

  function approve(no: string) {
    setItems((prev) => prev.map((i) => (i.studentNo === no ? { ...i, status: 'Cleared', clearedOn: todayLabel() } : i)))
  }

  function cancelReject() {
    setRejecting(null)
    setRemarks('')
    setError('')
  }

  function confirmReject() {
    if (!remarks.trim()) {
      setError('Enter the reason for rejecting this item.')
      return
    }
    setItems((prev) =>
      prev.map((i) => (i.studentNo === rejecting ? { ...i, status: 'Rejected', remarks: remarks.trim() } : i))
    )
    cancelReject()
  }

  // Why approval is blocked, in words: the hold's reason and who placed it.
  function holdNote(no: string) {
    const holds = activeHoldsFor(no)
    if (holds.length === 0) return <span className="text-muted">No active hold</span>
    return (
      <span>
        {holds.map((h) => (
          <span key={h.id} className="block">
            <span className="font-medium text-danger">Active hold: </span>
            {h.reason}
            <span className="text-muted"> (placed by {h.placedBy})</span>
          </span>
        ))}
      </span>
    )
  }

  function actions(item: DeptClearanceItem) {
    const blocked = activeHoldsFor(item.studentNo).length > 0
    const nameLabel = studentByNo(item.studentNo).name
    return (
      <div className="flex flex-col gap-1.5">
        <div className="flex flex-wrap gap-2">
          <Button
            disabled={blocked}
            aria-label={`Approve item for ${nameLabel}`}
            onClick={() => approve(item.studentNo)}
          >
            Approve
          </Button>
          <Button
            variant="outline"
            aria-label={`Reject item for ${nameLabel}`}
            onClick={() => {
              setRejecting(item.studentNo)
              setRemarks('')
              setError('')
            }}
          >
            Reject
          </Button>
        </div>
        {blocked && <p className="text-xs text-muted">Approval is blocked. Lift the active hold first.</p>}
      </div>
    )
  }

  const pendingItems = items.filter((i) => i.status === 'Pending')
  const decided = items.filter((i) => i.status !== 'Pending')
  const cleared = items.filter((i) => i.status === 'Cleared').length
  const rejectingStudent = rejecting ? studentByNo(rejecting) : null

  const pendingMobile: RecordItem[] = pendingItems.map((item) => {
    const s = studentByNo(item.studentNo)
    return {
      key: item.studentNo,
      title: s.name,
      subtitle: `${s.studentNo} · ${s.program}`,
      badge: <ItemStatusBadge status={item.status} />,
      fields: [
        { label: 'Requested', value: item.requestedOn },
        { label: 'Hold', value: holdNote(item.studentNo) },
      ],
      footer: actions(item),
    }
  })

  const decidedMobile: RecordItem[] = decided.map((item) => {
    const s = studentByNo(item.studentNo)
    return {
      key: item.studentNo,
      title: s.name,
      subtitle: `${s.studentNo} · ${s.program}`,
      badge: <ItemStatusBadge status={item.status} />,
      fields: [
        { label: 'Cleared on', value: item.clearedOn ?? 'Not cleared' },
        ...(item.remarks ? [{ label: 'Remarks', value: item.remarks }] : []),
      ],
    }
  })

  return (
    <div className="flex flex-col gap-6">
      <DeptStats
        stats={[
          { label: 'Items to review', value: pendingItems.length, hint: 'waiting for you', hue: pendingItems.length ? 'amber' : undefined },
          { label: 'Active holds', value: activeHoldCount, hint: 'block approval', hue: activeHoldCount ? 'rose' : undefined },
          { label: 'Cleared', value: cleared, hint: 'items approved' },
          { label: 'Students', value: DEPT_STUDENTS.length, hint: 'in clearance' },
        ]}
      />

      <Section
        title="Items to review"
        description="Approve an item once the student has no active hold from your department."
      >
        {rejectingStudent && (
          <Card elevation="flat" className="flex flex-col gap-3 p-4" role="group" aria-label="Reject clearance item">
            <h3 className="text-sm font-semibold">Reject item for {rejectingStudent.name}</h3>
            <Input
              id={remarksId}
              label="Remarks (shown to the student)"
              value={remarks}
              error={error || undefined}
              onChange={(e) => setRemarks(e.target.value)}
              autoFocus
            />
            <div className="flex flex-wrap gap-2">
              <Button variant="danger" onClick={confirmReject}>
                Confirm reject
              </Button>
              <Button variant="outline" onClick={cancelReject}>
                Cancel
              </Button>
            </div>
          </Card>
        )}

        <div className="hidden md:block">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead scope="col">Student</TableHead>
                <TableHead scope="col">Program</TableHead>
                <TableHead scope="col">Requested</TableHead>
                <TableHead scope="col">Hold</TableHead>
                <TableHead scope="col">Action</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pendingItems.length === 0 && <EmptyRow colSpan={5}>No items waiting for review.</EmptyRow>}
              {pendingItems.map((item) => {
                const s = studentByNo(item.studentNo)
                return (
                  <TableRow key={item.studentNo}>
                    <TableCell>
                      <span className="block font-semibold">{s.name}</span>
                      <span className="block text-xs text-muted">{s.studentNo}</span>
                    </TableCell>
                    <TableCell className="text-muted">{s.program}</TableCell>
                    <TableCell className="text-muted">{item.requestedOn}</TableCell>
                    <TableCell className="max-w-72 whitespace-normal">{holdNote(item.studentNo)}</TableCell>
                    <TableCell>{actions(item)}</TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </div>
        <RecordList className="md:hidden" items={pendingMobile} empty="No items waiting for review." />
      </Section>

      <Section title="Decided">
        <div className="hidden md:block">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead scope="col">Student</TableHead>
                <TableHead scope="col">Program</TableHead>
                <TableHead scope="col">Status</TableHead>
                <TableHead scope="col">Cleared on</TableHead>
                <TableHead scope="col">Remarks</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {decided.length === 0 && <EmptyRow colSpan={5}>No decided items yet.</EmptyRow>}
              {decided.map((item) => {
                const s = studentByNo(item.studentNo)
                return (
                  <TableRow key={item.studentNo}>
                    <TableCell>
                      <span className="block font-semibold">{s.name}</span>
                      <span className="block text-xs text-muted">{s.studentNo}</span>
                    </TableCell>
                    <TableCell className="text-muted">{s.program}</TableCell>
                    <TableCell><ItemStatusBadge status={item.status} /></TableCell>
                    <TableCell className="text-muted">{item.clearedOn ?? 'Not cleared'}</TableCell>
                    <TableCell className="text-muted">{item.remarks ?? 'None'}</TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </div>
        <RecordList className="md:hidden" items={decidedMobile} empty="No decided items yet." />
      </Section>

      <p className="text-sm text-muted">Changes on this screen are examples and are not saved.</p>
    </div>
  )
}
