import { createClient } from '@/lib/supabase/server'

export type ProgramOption = { program_id: number; code: string; name: string }

// Lists the programs an applicant can choose. rpc list_programs() is callable by anon. It is not in
// types/database.types.ts yet, so the call goes through a local cast.
export async function listPrograms(): Promise<ProgramOption[]> {
  try {
    const supabase = await createClient()
    const rpc = supabase.rpc.bind(supabase) as unknown as (
      fn: string
    ) => PromiseLike<{ data: ProgramOption[] | null; error: { message: string } | null }>
    const { data, error } = await rpc('list_programs')
    if (error || !Array.isArray(data)) return []
    return data
  } catch {
    return []
  }
}
