// Verifies the NEW race endpoints (progress / standings / messages) against
// a locally running server (same live DB). Uses the Guradeaur bot account.
// Run:  npx tsx prisma/scripts/verify-race-endpoints.ts
const API = process.env.SEED_API ?? 'http://localhost:3000/v1'

async function main() {
  const login = await fetch(`${API}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'guradeaur.bot@zvelt.app', password: 'Guradeaur123!' }),
  })
  if (!login.ok) throw new Error(`login ${login.status}: ${await login.text()}`)
  const { accessToken } = (await login.json()) as any
  const h = { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }

  // Find Guradeaur's bench challenge.
  const feed: any = await (await fetch(`${API}/challenges/feed`, { headers: h })).json()
  const ch = (feed.data as any[]).find((c) => c.kind === 'benchPress') ?? feed.data[0]
  if (!ch) throw new Error('no challenge in feed')
  console.log('challenge:', ch.title, ch.id)

  // Log progress ×2.
  for (const amount of [120, 80.5]) {
    const r = await fetch(`${API}/challenges/${ch.id}/progress`, {
      method: 'POST',
      headers: h,
      body: JSON.stringify({ amount }),
    })
    console.log(`progress +${amount}:`, r.status, JSON.stringify(await r.json()))
  }

  // Standings.
  const st: any = await (await fetch(`${API}/challenges/${ch.id}/standings`, { headers: h })).json()
  console.log('standings:', JSON.stringify(st.data), 'me:', JSON.stringify(st.me))

  // Chat: send + list.
  const send = await fetch(`${API}/challenges/${ch.id}/messages`, {
    method: 'POST',
    headers: h,
    body: JSON.stringify({ body: 'Catch me if you can 😤' }),
  })
  console.log('send message:', send.status, JSON.stringify(((await send.json()) as any).data))
  const msgs: any = await (await fetch(`${API}/challenges/${ch.id}/messages?limit=10`, { headers: h })).json()
  console.log('messages:', (msgs.data as any[]).map((m) => `${m.displayName}: ${m.body}`).join(' | '))

  // Validation guards.
  const bad = await fetch(`${API}/challenges/${ch.id}/progress`, {
    method: 'POST',
    headers: h,
    body: JSON.stringify({ amount: -5 }),
  })
  console.log('negative amount rejected:', bad.status === 400 ? 'OK (400)' : `FAIL (${bad.status})`)

  // Stories feed shape (likeCount/likedByMe fields present even when empty).
  const stories: any = await (await fetch(`${API}/stories/feed`, { headers: h })).json()
  console.log('stories feed:', Array.isArray(stories.data) ? `${stories.data.length} stories` : 'FAIL')
}

main().catch((e) => {
  console.error('VERIFY FAILED:', e)
  process.exitCode = 1
})
