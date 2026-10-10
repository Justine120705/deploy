import { Skeleton } from '@/components/ui'

// Flat skeleton shaped like the student dashboard: the sidebar edge (from lg), the greeting, the clearance
// route sheet, the two columns (classes; tasks and dates), then the grades table.
const SHEET = 'rounded-lg border border-edge bg-card'

export default function Loading() {
  return (
    <div role="status" aria-live="polite" className="min-h-screen bg-background lg:pl-60">
      <span className="sr-only">Loading your dashboard</span>
      <div aria-hidden="true" className="fixed inset-y-0 left-0 hidden w-60 border-r border-border px-5 py-5 lg:block">
        <Skeleton className="h-6 w-36" />
        <div className="mt-8 flex flex-col gap-3">
          {[0, 1, 2, 3, 4].map((i) => (
            <Skeleton key={i} className="h-5 w-32" />
          ))}
        </div>
      </div>

      <div aria-hidden="true" className="mx-auto flex max-w-[1200px] flex-col gap-8 px-4 py-5 sm:px-6 lg:gap-10 lg:px-8 lg:py-8">
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <Skeleton className="h-6 w-56" />
            <Skeleton className="h-4 w-72 max-w-full" />
          </div>
          <div className={`${SHEET} flex flex-col gap-5 p-5`}>
            <div className="flex items-start justify-between gap-4">
              <div className="flex flex-col gap-2">
                <Skeleton className="h-5 w-24" />
                <Skeleton className="h-4 w-48" />
              </div>
              <Skeleton className="h-9 w-32" />
            </div>
            <Skeleton className="h-px w-full" />
            <div className="grid gap-3 md:grid-cols-5">
              {[0, 1, 2, 3, 4].map((i) => (
                <Skeleton key={i} className="h-8 w-full max-w-40" />
              ))}
            </div>
            <Skeleton className="h-4 w-2/3" />
          </div>
        </div>

        <div className="grid gap-8 lg:grid-cols-2 lg:gap-6">
          <div className="flex flex-col gap-3">
            <Skeleton className="h-5 w-24" />
            <div className={`${SHEET} flex flex-col gap-3 p-4`}>
              <Skeleton className="h-5 w-1/2" />
              <Skeleton className="h-4 w-1/3" />
              <Skeleton className="mt-2 h-24 w-full" />
            </div>
          </div>
          <div className="flex flex-col gap-3">
            <Skeleton className="h-5 w-20" />
            <div className={`${SHEET} flex flex-col gap-3 p-4`}>
              {[0, 1, 2, 3].map((i) => (
                <Skeleton key={i} className="h-6 w-full" />
              ))}
            </div>
          </div>
        </div>

        <div className="flex flex-col gap-3">
          <Skeleton className="h-5 w-36" />
          <div className={`${SHEET} flex flex-col gap-3 p-4`}>
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-8 w-full" />
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
