'use client'

import { useActionState, useId, useState } from 'react'
import { Button, Card, EmptyRow, Input, Section, Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui'
import { DeptStats, type DeptStat } from '@/components/department/DeptStats'
import { ItemStatusBadge } from '@/components/department/DeptBadges'
import { ActionMessage, DEPT_IDLE } from '@/components/department/DeptNotice'
import { RecordList, type RecordItem } from '@/components/department/RecordList'
import { reviewItem, type DeptActionState } from '@/lib/data/department-actions'
import type { ReviewItem } from '@/lib/data/department'

// Live review screen. Approve writes cleared_at and cleared_by; Reject writes remarks only (the item
// stays pending and the student sees the remarks). The database blocks approval while this department
// has an active hold on the student, and the message says so. One status region announces the result.
export default function ClearanceItemsClient({ items, stats }: { items: ReviewItem[]; stats: DeptStat[] }) {
  const [state, formAction, pending] = useActionState<DeptActionState, FormData>(reviewItem, DEPT_IDLE)
  // The reject panel closes once a later result succeeds; a failed result keeps it open.
  const [panel, setPanel] = useState<{ item: ReviewItem; base: DeptActionState } | null>(null)
  const remarksId = useId()

  const open = panel !== null && !(state !== panel.base && state.status === 'success')
  const rejecting = open ? panel.item : null

  const pendingItems = items.filter((i) => i.status === 'Pending')
  const decided = items.filter((i) => i.status === 'Cleared')

  function holdNote(item: ReviewItem) {
    if (item.holds.length === 0) return <span className="text-muted">No active hold</span>
    return (
      <span>
        {item.holds.map((h) => (
          <span key={h.holdId} className="block">
            <span className="font-medium text-danger">Active hold: </span>
            {h.reason}
            <span className="text-muted"> (placed by {h.placedByName})</span>
          </span>
        ))}
      </span>
    )
  }

  function actions(item: ReviewItem) {
    const blocked = item.holds.length > 0
    return (
      <div className="flex flex-col gap-1.5">
        <div className="flex flex-wrap gap-2">
          <form action={formAction}>
            <input type="hidden" name="itemId" value={item.itemId} />
            <input type="hidden" name="intent" value="approve" />
            <input type="hidden" name="studentName" value={item.name} />
            <Button type="submit" disabled={blocked || pending} aria-label={`Approve item for ${item.name}`}>
              Approve
            </Button>
          </form>
          <Button
            variant="outline"
            disabled={pending}
            aria-label={`Reject item for ${item.name}`}
            onClick={() => setPanel({ item, base: state })}
          >
            Reject
          </Button>
        </div>
        {blocked && <p className="text-xs text-muted">Approval is blocked. Lift the active hold first.</p>}
      </div>
    )
  }

  const pendingMobile: RecordItem[] = pendingItems.map((item) => ({
    key: String(item.itemId),
    title: item.name,
    subtitle: `${item.studentNo} · ${item.program}`,
    badge: <ItemStatusBadge status={item.status} />,
    fields: [
      { label: 'Requested', value: item.requestedOn },
      { label: 'Hold', value: holdNote(item) },
      ...(item.remarks ? [{ label: 'Your remarks', value: item.remarks }] : []),
    ],
    footer: actions(item),
  }))

  const decidedMobile: RecordItem[] = decided.map((item) => ({
    key: String(item.itemId),
    title: item.name,
    subtitle: `${item.studentNo} · ${item.program}`,
    badge: <ItemStatusBadge status={item.status} />,
    fields: [
      { label: 'Cleared on', value: item.clearedOn ?? 'Not cleared' },
      ...(item.remarks ? [{ label: 'Remarks', value: item.remarks }] : []),
    ],
  }))

  return (
    <div className="flex flex-col gap-6">
      <DeptStats stats={stats} />

      <ActionMessage state={state} />

      <Section
        title="Items to review"
        description="Approve an item once the student has no active hold from your department."
      >
        {rejecting && (
          <Card elevation="flat" className="flex flex-col gap-3 p-4" role="group" aria-label="Reject clearance item">
            <h3 className="text-sm font-semibold">Reject item for {rejecting.name}</h3>
            <form action={formAction} className="flex flex-col gap-3">
              <input type="hidden" name="itemId" value={rejecting.itemId} />
              <input type="hidden" name="intent" value="reject" />
              <input type="hidden" name="studentName" value={rejecting.name} />
              <Input
                id={remarksId}
                name="remarks"
                label="Remarks (shown to the student)"
                maxLength={500}
                required
                autoFocus
                autoComplete="off"
              />
              <div className="flex flex-wrap gap-2">
                <Button type="submit" variant="danger" disabled={pending}>
                  {pending ? 'Saving...' : 'Confirm reject'}
                </Button>
                <Button variant="outline" onClick={() => setPanel(null)}>
                  Cancel
                </Button>
              </div>
            </form>
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
              {pendingItems.map((item) => (
                <TableRow key={item.itemId}>
                  <TableCell>
                    <span className="block font-semibold">{item.name}</span>
                    <span className="block text-xs text-muted">{item.studentNo}</span>
                    {item.remarks && <span className="block text-xs text-muted">Your remarks: {item.remarks}</span>}
                  </TableCell>
                  <TableCell className="text-muted">{item.program}</TableCell>
                  <TableCell className="text-muted">{item.requestedOn}</TableCell>
                  <TableCell className="max-w-72 whitespace-normal">{holdNote(item)}</TableCell>
                  <TableCell>{actions(item)}</TableCell>
                </TableRow>
              ))}
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
              {decided.map((item) => (
                <TableRow key={item.itemId}>
                  <TableCell>
                    <span className="block font-semibold">{item.name}</span>
                    <span className="block text-xs text-muted">{item.studentNo}</span>
                  </TableCell>
                  <TableCell className="text-muted">{item.program}</TableCell>
                  <TableCell><ItemStatusBadge status={item.status} /></TableCell>
                  <TableCell className="text-muted">{item.clearedOn ?? 'Not cleared'}</TableCell>
                  <TableCell className="text-muted">{item.remarks ?? 'None'}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
        <RecordList className="md:hidden" items={decidedMobile} empty="No decided items yet." />
      </Section>
    </div>
  )
}
