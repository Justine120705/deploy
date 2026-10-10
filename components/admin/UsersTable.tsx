'use client'

import { useState } from 'react'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Input,
  StatusBadge,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui'

export type UserRow = {
  id: string
  name: string
  email: string
  role: string
  department: string
  active: boolean
}

// UI only for now: edits stay in local state, no backend call yet.
export default function UsersTable({ initialUsers }: { initialUsers: UserRow[] }) {
  const [users, setUsers] = useState(initialUsers)
  const [editing, setEditing] = useState<UserRow | 'new' | null>(null)
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')

  function openForm(user: UserRow | 'new') {
    setEditing(user)
    setName(user === 'new' ? '' : user.name)
    setEmail(user === 'new' ? '' : user.email)
  }

  function save() {
    if (!name.trim() || !email.trim()) return
    if (editing === 'new') {
      setUsers((prev) => [
        ...prev,
        { id: `new-${prev.length}`, name, email, role: 'Student', department: '-', active: true },
      ])
    } else if (editing) {
      const id = editing.id
      setUsers((prev) => prev.map((u) => (u.id === id ? { ...u, name, email } : u)))
    }
    setEditing(null)
  }

  function toggleActive(id: string) {
    setUsers((prev) => prev.map((u) => (u.id === id ? { ...u, active: !u.active } : u)))
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <Button onClick={() => openForm('new')}>Create user</Button>
      </div>

      {editing && (
        <Card className="p-5">
          <CardHeader title={editing === 'new' ? 'Create user' : 'Edit user'} />
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <Input id="user-name" label="Name" value={name} onChange={(e) => setName(e.target.value)} />
            <Input
              id="user-email"
              label="Email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="mt-4 flex gap-2">
            <Button onClick={save}>Save</Button>
            <Button variant="outline" onClick={() => setEditing(null)}>
              Cancel
            </Button>
          </div>
        </Card>
      )}

      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>Name</TableHead>
            <TableHead>Email</TableHead>
            <TableHead>Role</TableHead>
            <TableHead>Department</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Actions</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {users.map((u) => (
            <TableRow key={u.id}>
              <TableCell>{u.name}</TableCell>
              <TableCell className="text-muted">{u.email}</TableCell>
              <TableCell>
                <Badge>{u.role}</Badge>
              </TableCell>
              <TableCell>{u.department}</TableCell>
              <TableCell>
                <StatusBadge status={u.active ? 'Active' : 'Inactive'} />
              </TableCell>
              <TableCell>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    className="h-9 px-4"
                    onClick={() => openForm(u)}
                    aria-label={`Edit ${u.name}`}
                  >
                    Edit
                  </Button>
                  <Button
                    variant={u.active ? 'danger' : 'accent'}
                    className="h-9 px-4"
                    onClick={() => toggleActive(u.id)}
                    aria-label={`${u.active ? 'Deactivate' : 'Activate'} ${u.name}`}
                  >
                    {u.active ? 'Deactivate' : 'Activate'}
                  </Button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
