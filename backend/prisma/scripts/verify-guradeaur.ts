// Quick read-only check of the seeded Guradeaur account via the public API.
// Run from backend/:  npx tsx prisma/scripts/verify-guradeaur.ts
const API = process.env.SEED_API ?? 'https://zveltutzu.onrender.com/v1'

async function main() {
  const login = await fetch(`${API}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'guradeaur.bot@zvelt.app', password: 'Guradeaur123!' }),
  })
  if (!login.ok) throw new Error(`login ${login.status}: ${await login.text()}`)
  const { accessToken } = (await login.json()) as any
  const h = { Authorization: `Bearer ${accessToken}` }
  const get = async (p: string) => {
    const r = await fetch(`${API}${p}`, { headers: h })
    return r.ok ? r.json() : { _err: `${r.status}` }
  }

  const me: any = await get('/me')
  console.log('profile:', me.profile?.displayName, '@' + me.profile?.username, 'BW', me.profile?.bodyweightKg)
  console.log('streak:', JSON.stringify(me.streak))
  console.log('gameXp:', JSON.stringify(me.gameXp)?.slice(0, 160))

  const w: any = await get('/workouts?limit=10')
  console.log('workouts:', w.meta?.total, '→', (w.data ?? []).map((x: any) => `${x.startedAt?.slice(0, 10)}(${x.status})`).join(' '))

  const daily: any = await get('/me/stats/daily-training?days=7')
  const arr = Array.isArray(daily) ? daily : daily.data ?? daily.days ?? []
  console.log('daily-training (7d):', JSON.stringify(arr.map?.((d: any) => ({ d: d.day, s: d.sessions, v: Math.round(d.volumeKg ?? d.volume_kg ?? 0) }))))

  const feed: any = await get('/posts/feed?limit=10')
  console.log('feed posts (own visible):', (feed.data ?? []).length)

  const today = new Date().toISOString().slice(0, 10)
  const day: any = await get(`/nutrition/day?date=${today}`)
  console.log(`nutrition today: entries=${day.entries?.length} water=${day.waterMl} weight=${day.weightKg}`)

  const stats: any = await get('/me/stats')
  console.log('character stats:', JSON.stringify(stats?.stats ? Object.fromEntries(Object.entries(stats.stats).map(([k, v]: any) => [k, v.value])) : stats).slice(0, 200), 'overall:', stats?.overall)
}

main().catch((e) => {
  console.error('VERIFY FAILED:', e)
  process.exitCode = 1
})
