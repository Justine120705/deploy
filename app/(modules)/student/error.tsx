'use client'

import { useEffect } from 'react'
import { Button, Card } from '@/components/ui'

// Shown when the student pages fail to load. Technical details go to the console only, never on screen.
export default function StudentError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => {
    console.error(error)
  }, [error])

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-4">
      <Card role="alert" className="flex w-full max-w-md flex-col items-start gap-3 p-6">
        <h1 className="text-xl font-extrabold">We could not load this page</h1>
        <p className="text-sm text-muted">Something went wrong on our side. Try again, and if it keeps happening, come back in a few minutes.</p>
        <Button onClick={() => retry()}>Try again</Button>
      </Card>
    </div>
  )
}
