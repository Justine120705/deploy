import { createClient } from '@/lib/supabase/server'

// Temporary proof that Row Level Security works: shows how many rows of a table
// the signed-in user is allowed to see. Remove once real module screens exist.
export default async function RlsCheck({ table, expected }: { table: string; expected: string }) {
  const supabase = await createClient()
  const { count, error } = await supabase.from(table).select('*', { count: 'exact', head: true })

  return (
    <section className="rounded-lg border border-dashed border-zinc-300 bg-white p-4 text-sm text-zinc-700">
      <p className="font-medium text-zinc-900">Database check (temporary)</p>
      {error ? (
        <p className="mt-1 text-red-700">Could not read {table}: {error.message}</p>
      ) : (
        <p className="mt-1">
          You can see <strong>{count}</strong> row(s) in <code>{table}</code>. {expected}
        </p>
      )}
    </section>
  )
}
