'use client'

import { useId, useMemo, useState } from 'react'
import TableCard from '@/components/admin/TableCard'
import {
  Button,
  Section,
  EmptyRow,
  HUE_SOFT,
  HUE_TEXT,
  Input,
  Select,
  SummaryStrip,
  StatusBadge,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'
import type { AdminUserRow } from '@/lib/mock/admin-data'

export type UserRow = AdminUserRow

function RoleChip({ role }: { role: string }) {
  const tone = role === 'Student' ? `${HUE_SOFT.violet} ${HUE_TEXT.violet}` : 'bg-neutral-soft text-neutral'
  return (
    <span className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ${tone}`}>
      {role}
    </span>
  )
}

// UI only for now: edits stay in local state, no backend call yet. Accounts are deactivated, never deleted.
export default function UsersTable({ initialUsers, roleNames }: { initialUsers: UserRow[]; roleNames: string[] }) {
  const uid = useId()
  const [users, setUsers] = useState(initialUsers)
  const [editing, setEditing] = useState<UserRow | 'new' | null>(null)
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [role, setRole] = useState(roleNames[0] ?? 'Student')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [query, setQuery] = useState('')
  const [roleFilter, setRoleFilter] = useState('')

  function openForm(user: UserRow | 'new') {
    setEditing(user)
    setName(user === 'new' ? '' : user.name)
    setEmail(user === 'new' ? '' : user.email)
    setRole(user === 'new' ? (roleNames[0] ?? 'Student') : user.role)
    setError('')
  }

  function save() {
    if (!name.trim() || !email.trim()) {
      setError('Enter a name and an email address.')
      return
    }
    if (editing === 'new') {
      setUsers((prev) => [
        ...prev,
        {
          id: `new-${prev.length}`,
          name: name.trim(),
          email: email.trim(),
          role,
          department: 'None',
          active: true,
          created: 'Today',
        },
      ])
    } else if (editing) {
      const id = editing.id
      setUsers((prev) => prev.map((u) => (u.id === id ? { ...u, name: name.trim(), email: email.trim(), role } : u)))
    }
    setEditing(null)
  }

  function toggleActive(id: string) {
    const target = users.find((u) => u.id === id)
    // Never lock everyone out: the last active Admin cannot be deactivated.
    if (target?.active && target.role === 'Admin' && users.filter((u) => u.role === 'Admin' && u.active).length === 1) {
      setNotice(`${target.name} is the only active Admin, so this account cannot be deactivated. Add or activate another Admin first.`)
      return
    }
    setNotice('')
    setUsers((prev) => prev.map((u) => (u.id === id ? { ...u, active: !u.active } : u)))
  }

  const staffRoles = roleNames.filter((r) => r !== 'Student')
  const students = users.filter((u) => u.role === 'Student')
  const staff = users.filter((u) => u.role !== 'Student')
  const inactive = users.filter((u) => !u.active).length

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    return users.filter(
      (u) =>
        (!roleFilter || u.role === roleFilter) &&
        (!q || u.name.toLowerCase().includes(q) || u.email.toLowerCase().includes(q))
    )
  }, [users, query, roleFilter])

  const rowActions = (u: UserRow) => (
    <div className="flex gap-2">
      <Button
        variant="outline"
        onClick={() => openForm(u)}
        aria-label={`Edit ${u.name}`}
      >
        Edit
      </Button>
      <Button
        variant={u.active ? 'danger' : 'accent'}
        onClick={() => toggleActive(u.id)}
        aria-label={`${u.active ? 'Deactivate' : 'Activate'} ${u.name}`}
      >
        {u.active ? 'Deactivate' : 'Activate'}
      </Button>
    </div>
  )

  return (
    <div className="flex flex-col gap-6">
      <SummaryStrip
        items={[
          { label: 'Total users', value: users.length, hint: 'accounts' },
          { label: 'Active students', value: students.filter((u) => u.active).length, hint: 'can sign in', hue: 'teal' },
          { label: 'Staff', value: staff.length, hint: staffRoles.map((r) => r.toLowerCase()).join(', ') },
          { label: 'Inactive', value: inactive, hint: 'deactivated' },
        ]}
      />

      <p role="status" className={notice ? 'rounded-lg border border-edge bg-warning-soft px-4 py-3 text-sm font-medium text-warning' : 'sr-only'}>
        {notice}
      </p>

      {editing && (
        <Section title={editing === 'new' ? 'Add user' : 'Edit user'}>
          <div className="rounded-lg border border-edge bg-card p-4 lg:p-5">
            <div className="grid gap-4 sm:grid-cols-3">
              <Input id={`${uid}-name`} label="Name" value={name} onChange={(e) => setName(e.target.value)} />
              <Input
                id={`${uid}-email`}
                label="Email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
              <Select id={`${uid}-role`} label="Role" value={role} onChange={(e) => setRole(e.target.value)}>
                {roleNames.map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </Select>
            </div>
            {error && (
              <p role="alert" className="mt-3 text-sm text-danger">
                {error}
              </p>
            )}
            <div className="mt-4 flex gap-2">
              <Button onClick={save}>Save</Button>
              <Button variant="outline" onClick={() => setEditing(null)}>
                Cancel
              </Button>
            </div>
            <p className="mt-3 text-sm text-muted">Changes stay on this page until the database is connected.</p>
          </div>
        </Section>
      )}

      <div className="flex flex-wrap items-end gap-3 border-b border-edge pb-4">
        <div className="min-w-[200px] flex-1">
          <Input
            id={`${uid}-search`}
            label="Search accounts"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="w-full sm:w-48">
          <Select id={`${uid}-filter`} label="Role" value={roleFilter} onChange={(e) => setRoleFilter(e.target.value)}>
            <option value="">All roles</option>
            {roleNames.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </Select>
        </div>
        <Button onClick={() => openForm('new')} className="max-sm:w-full">
          Add user
        </Button>
      </div>

      {/* Phone: one hairline list, one account per block. */}
      <ul className="-mt-3 divide-y divide-edge overflow-hidden rounded-lg border border-edge bg-card md:hidden">
        {visible.length === 0 && <li className="px-4 py-8 text-center text-sm text-muted">No accounts match.</li>}
        {visible.map((u) => (
          <li key={u.id} className="flex flex-col gap-3 px-4 py-3">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="font-semibold">{u.name}</p>
                <p className="break-all text-sm text-muted">{u.email}</p>
              </div>
              <StatusBadge status={u.active ? 'Active' : 'Inactive'} />
            </div>
            <div className="flex flex-wrap items-center gap-2 text-sm text-muted">
              <RoleChip role={u.role} />
              <span>Department: {u.department}</span>
              <span>Created {u.created}</span>
            </div>
            {rowActions(u)}
          </li>
        ))}
      </ul>

      {/* Tablet and desktop: table. */}
      <div className="-mt-3 max-md:hidden">
        <TableCard
          minWidth="min-w-[860px]"
          footer={`Showing ${visible.length} of ${users.length} users. Accounts are deactivated, never deleted.`}
        >
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead scope="col">Email</TableHead>
              <TableHead scope="col">Name</TableHead>
              <TableHead scope="col">Role</TableHead>
              <TableHead scope="col">Department</TableHead>
              <TableHead scope="col">Status</TableHead>
              <TableHead scope="col">Created</TableHead>
              <TableHead scope="col">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.length === 0 && <EmptyRow colSpan={7}>No accounts match.</EmptyRow>}
            {visible.map((u) => (
              <TableRow key={u.id}>
                <TableCell className="font-normal text-muted">{u.email}</TableCell>
                <TableCell>{u.name}</TableCell>
                <TableCell>
                  <RoleChip role={u.role} />
                </TableCell>
                <TableCell className="font-normal text-muted">{u.department}</TableCell>
                <TableCell>
                  <StatusBadge status={u.active ? 'Active' : 'Inactive'} />
                </TableCell>
                <TableCell className="whitespace-nowrap font-normal text-muted">{u.created}</TableCell>
                <TableCell>{rowActions(u)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </TableCard>
      </div>
    </div>
  )
}
