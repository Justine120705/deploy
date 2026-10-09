import { redirect } from 'next/navigation'

// The proxy sends signed-in users to their dashboard; everyone else lands on /login.
export default function Home() {
  redirect('/login')
}
