import { Card } from '@/components/ui'

// Skeleton shaped like the student dashboard: banner, three cards, a wide card, and the side column.
const BLOCK = 'animate-pulse rounded-lg bg-accent motion-reduce:animate-none'

export default function Loading() {
  return (
    <div role="status" aria-live="polite" className="min-h-screen bg-background p-3 lg:p-4">
      <span className="sr-only">Loading your dashboard</span>
      <div aria-hidden="true" className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_304px]">
        <div className="flex min-w-0 flex-col gap-4">
          <div className={`${BLOCK} h-32 rounded-2xl`} />
          <div className="grid gap-4 md:grid-cols-3">
            {[0, 1, 2].map((i) => (
              <Card key={i} className="flex min-h-[204px] flex-col gap-3 p-5">
                <div className={`${BLOCK} h-5 w-1/2`} />
                <div className={`${BLOCK} h-28 w-full`} />
              </Card>
            ))}
          </div>
          <Card className="flex min-h-[200px] flex-col gap-3 p-5">
            <div className={`${BLOCK} h-5 w-1/3`} />
            <div className={`${BLOCK} h-32 w-full`} />
          </Card>
        </div>
        <div className="flex flex-col gap-4">
          <Card className="flex min-h-[280px] flex-col gap-3 p-5">
            <div className={`${BLOCK} h-5 w-1/2`} />
            <div className={`${BLOCK} h-52 w-full`} />
          </Card>
          <Card className="flex min-h-[160px] flex-col gap-3 p-5">
            <div className={`${BLOCK} h-5 w-1/2`} />
            <div className={`${BLOCK} h-16 w-full`} />
          </Card>
        </div>
      </div>
    </div>
  )
}
