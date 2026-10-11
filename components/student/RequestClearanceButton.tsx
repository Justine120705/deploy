'use client'

import { useState } from 'react'
import { Button } from '@/components/ui'

// UI only for now: no backend call yet. Alone it keeps its own state; pass `requested` and
// `onRequest` to let a parent own the state (the clearance page does, so the chain can follow it).
export default function RequestClearanceButton({
  department,
  requested: requestedProp,
  onRequest,
}: {
  department: string
  requested?: boolean
  onRequest?: () => void
}) {
  const [own, setOwn] = useState(false)
  const requested = requestedProp ?? own

  return (
    <Button
      variant={requested ? 'outline' : 'primary'}
      className="h-9 px-4 max-lg:h-11"
      disabled={requested}
      onClick={() => (onRequest ? onRequest() : setOwn(true))}
      aria-label={requested ? `Clearance requested from ${department}` : `Request clearance from ${department}`}
    >
      {requested ? 'Requested' : 'Request clearance'}
    </Button>
  )
}
