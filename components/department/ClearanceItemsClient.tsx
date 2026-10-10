'use client'

import { useId, useState } from 'react'
import { Button, Card, CardHeader, EmptyRow, Input, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats } from '@/components/department/DeptStats'
import { ItemStatusBadge } from '@/components/department/DeptBadges'
import { RecordList, type RecordItem } from '@/components/department/RecordList'
import {
  DEPT_CLEARANCE_ITEMS,
  DEPT_HOLDS,
  DEPT_STUDENTS,
  studentByNo,
  type DeptClearanceItem,
} from '@/lib/mock/department-data'

const TODAY = 'Oct 10, 2026'

// Mock-only review state: nothing is saved. Approval is blocked while the student has an active hold
// from this department (REQ-DPT-03).
export default function ClearanceItemsClient() {
  const [items, setItems] = useState<DeptClearanceItem[]>(DEPT_CLEARANCE_ITEMS)
  const [rejecting, setRejecting] = useState<string | null>(null)
  const [remarks, setRemarks] = useState('')
  const [error, setError] = useState('')
  const remarksId = useId()

  const holdCount = (no: string) => DEPT_HOLDS.filter((h) => h.studentNo === no && h.status === 'Active').length
  const activeHolds = DEPT_HOLDS.filter((h) => h.status === 'Active').length

  function approve(no: string) {
    setItems((prev) => prev.map((i) => (i.studentNo === no ? { ...i, status: 'Cleared', clearedOn: TODAY } : i)))
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

  function actions(item: DeptClearanceItem) {
    if (item.status !== 'Pending') return <span className="text-sm text-muted">No action needed</span>
    const blocked = holdCount(item.studentNo) > 0
    const nameLabel = studentByNo(item.studentNo).name
    return (
      <div className="flex flex-col gap-1">
        <div className="flex flex-wrap gap-2">
          <Button
            className="h-11 lg:h-10"
            disabled={blocked}
            aria-label={`Approve item for ${nameLabel}`}
            onClick={() => approve(item.studentNo)}
          >
            Approve
          </Button>
          <Button
            variant="outline"
            className="h-11 lg:h-10"
            aria-label={`Reject item for ${nameLabel}`}
            onClick={() => {
              setRejecting(item.studentNo)
              setError('')
            }}
          >
            Reject
          </Button>
        </div>
        {blocked && <p className="text-xs text-muted">Lift the active hold before approving.</p>}
      </div>
    )
  }

  const cleared = items.filter((i) => i.status === 'Cleared').length
  const pending = items.filter((i) => i.status === 'Pending').length
  const rejectingStudent = rejecting ? studentByNo(rejecting) : null

  const mobile: RecordItem[] = items.map((item) => {
    const s = studentByNo(item.studentNo)
    return {
      key: item.studentNo,
      title: s.name,
      subtitle: `${s.studentNo} · ${s.program}`,
      badge: <ItemStatusBadge status={item.status} />,
      fields: [
        { label: 'Active holds', value: holdCount(item.studentNo) },
        { label: 'Cleared on', value: item.clearedOn ?? 'Not cleared yet' },
        ...(item.remarks ? [{ label: 'Remarks', value: item.remarks }] : []),
      ],
      footer: actions(item),
    }
  })

  return (
    <div className="flex flex-col gap-4">
      <DeptStats
        stats={[
          { label: 'Pending', value: pending, hint: 'to review', hue: 'amber' },
          { label: 'Cleared', value: cleared, hint: 'items', hue: 'teal' },
          { label: 'Active holds', value: activeHolds, hint: 'block approval', hue: 'rose' },
          { label: 'Students', value: DEPT_STUDENTS.length, hint: 'in clearance' },
        ]}
      />

      {rejectingStudent && (
        <Card className="flex flex-col gap-3 p-5" role="group" aria-label="Reject clearance item">
          <CardHeader title={`Reject item for ${rejectingStudent.name}`} icon="holds" hue="rose" />
          <Input
            id={remarksId}
            label="Remarks (shown to the student)"
            value={remarks}
            error={error || undefined}
            onChange={(e) => setRemarks(e.target.value)}
            autoFocus
          />
          <div className="flex flex-wrap gap-2">
            <Button variant="danger" className="h-11 lg:h-10" onClick={confirmReject}>
              Confirm reject
            </Button>
            <Button variant="outline" className="h-11 lg:h-10" onClick={cancelReject}>
              Cancel
            </Button>
          </div>
        </Card>
      )}

      <div className="hidden md:block">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead scope="col">Student no.</TableHead>
              <TableHead scope="col">Student name</TableHead>
              <TableHead scope="col">Program</TableHead>
              <TableHead scope="col">Active holds</TableHead>
              <TableHead scope="col">Item status</TableHead>
              <TableHead scope="col">Cleared on</TableHead>
              <TableHead scope="col">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {items.length === 0 && <EmptyRow colSpan={7}>No clearance items.</EmptyRow>}
            {items.map((item) => {
              const s = studentByNo(item.studentNo)
              return (
                <TableRow key={item.studentNo}>
                  <TableCell className="font-normal text-muted">{s.studentNo}</TableCell>
                  <TableCell className="font-semibold">{s.name}</TableCell>
                  <TableCell className="font-normal text-muted">{s.program}</TableCell>
                  <TableCell className="font-normal text-muted">{holdCount(item.studentNo)}</TableCell>
                  <TableCell>
                    <ItemStatusBadge status={item.status} />
                    {item.remarks && <p className="mt-1 text-xs font-normal text-muted">{item.remarks}</p>}
                  </TableCell>
                  <TableCell className="font-normal text-muted">{item.clearedOn ?? 'Not cleared yet'}</TableCell>
                  <TableCell>{actions(item)}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
      <div className="surface rounded-2xl border border-edge bg-card shadow-elev-sm md:hidden">
        <RecordList items={mobile} empty="No clearance items." />
      </div>

      <p className="text-sm text-muted">
        An item can be approved only when the student has no active hold from your department (REQ-DPT-03).
        Changes on this screen are examples and are not saved.
      </p>
    </div>
  )
}
