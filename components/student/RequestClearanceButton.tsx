'use client'

import { useState } from 'react'
import { Button } from '@/components/ui'

// UI only for now: no backend call yet.
export default function RequestClearanceButton({ department }: { department: string }) {
  const [requested, setRequested] = useState(false)

  return (
    <Button
      variant={requested ? 'outline' : 'primary'}
      className="h-9 px-4"
      disabled={requested}
      onClick={() => setRequested(true)}
      aria-label={`Request clearance from ${department}`}
    >
      {requested ? 'Requested' : 'Request clearance'}
    </Button>
  )
}
