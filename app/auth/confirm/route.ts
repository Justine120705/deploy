import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// The link in the acceptance email lands here. Only the 'recovery' type is accepted: it creates the
// session that lets the new student choose a password. Anything else, or a bad or used link, goes to
// /login?notice=link-expired.
function go(request: NextRequest, path: string, search = '') {
  const url = request.nextUrl.clone()
  url.pathname = path
  url.search = search
  return NextResponse.redirect(url)
}

export async function GET(request: NextRequest) {
  const tokenHash = request.nextUrl.searchParams.get('token_hash')
  const type = request.nextUrl.searchParams.get('type')

  if (!tokenHash || type !== 'recovery') return go(request, '/login', '?notice=link-expired')

  const supabase = await createClient()
  const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: 'recovery' })
  if (error) return go(request, '/login', '?notice=link-expired')

  return go(request, '/set-password')
}
