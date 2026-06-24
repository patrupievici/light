import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Only the Prisma-method endpoints are exercised here (/stats aggregate score +
// /stats/rank-lp). The raw-SQL stats endpoints ($queryRawUnsafe) are excluded —
// mocking raw SQL would assert nothing about real behaviour.
const userExerciseRankFindMany = vi.fn()
const workoutFindMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    userExerciseRank: { findMany: (...a: unknown[]) => userExerciseRankFindMany(...a) },
    workout: { findMany: (...a: unknown[]) => workoutFindMany(...a) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { statsRoutes } from './stats'

async function buildApp() {
  const app = Fastify()
  await app.register(statsRoutes, { prefix: '/v1/me' })
  await app.ready()
  return app
}

beforeEach(() => {
  userExerciseRankFindMany.mockReset()
  workoutFindMany.mockReset()
})

describe('GET /v1/me/stats — RPG attribute scoring', () => {
  it('derives strength from strength-category ranks and clamps to 100', async () => {
    // Two strength ranks averaging very high LP → strengthScore clamps at 100.
    userExerciseRankFindMany.mockResolvedValue([
      { exerciseId: 'e1', lpTotal: 600, exercise: { category: 'strength' } },
      { exerciseId: 'e2', lpTotal: 600, exercise: { category: 'strength' } },
    ])
    workoutFindMany.mockResolvedValue([])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats' })

    expect(res.statusCode).toBe(200)
    const body = res.json()
    // avg LP 600 / 3 = 200 → clamped to 100.
    expect(body.stats.strength.value).toBe(100)
    // No explosive ranks → agility 0.
    expect(body.stats.agility.value).toBe(0)
    await app.close()
  })

  it('computes strength as round(avgLP/3) for mid-range ranks', async () => {
    userExerciseRankFindMany.mockResolvedValue([
      { exerciseId: 'e1', lpTotal: 90, exercise: { category: 'strength' } },
      { exerciseId: 'e2', lpTotal: 60, exercise: { category: 'strength' } },
    ])
    workoutFindMany.mockResolvedValue([])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats' })

    // avg = (90+60)/2 = 75 ; 75/3 = 25.
    expect(res.json().stats.strength.value).toBe(25)
    await app.close()
  })

  it('separates explosive-category ranks into the agility attribute', async () => {
    userExerciseRankFindMany.mockResolvedValue([
      { exerciseId: 'e1', lpTotal: 30, exercise: { category: 'strength' } },
      { exerciseId: 'e3', lpTotal: 90, exercise: { category: 'explosive' } },
    ])
    workoutFindMany.mockResolvedValue([])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats' })

    const body = res.json()
    expect(body.stats.strength.value).toBe(10) // 30/3
    expect(body.stats.agility.value).toBe(30) // 90/3
    await app.close()
  })

  it('vitality scales with workouts in the last 30 days (20 sessions ⇒ 100)', async () => {
    userExerciseRankFindMany.mockResolvedValue([])
    // 20 recent workouts → vitality = min(100, round(20/20*100)) = 100.
    const now = Date.now()
    workoutFindMany.mockResolvedValue(
      Array.from({ length: 20 }, (_, i) => ({ startedAt: new Date(now - i * 60_000) })),
    )

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats' })

    expect(res.json().stats.vitality.value).toBe(100)
    await app.close()
  })

  it('ignores workouts older than 30 days for vitality', async () => {
    userExerciseRankFindMany.mockResolvedValue([])
    const old = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000)
    workoutFindMany.mockResolvedValue([{ startedAt: old }, { startedAt: old }])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats' })

    // Both workouts are outside the 30-day window → vitality 0.
    expect(res.json().stats.vitality.value).toBe(0)
    await app.close()
  })

  it('overall is the mean of the five attributes and the query is owner-scoped', async () => {
    userExerciseRankFindMany.mockResolvedValue([])
    workoutFindMany.mockResolvedValue([])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats' })

    const body = res.json()
    // All attributes 0 with no data → overall 0.
    expect(body.overall).toBe(0)
    expect((userExerciseRankFindMany.mock.calls[0][0] as { where: { userId: string } }).where.userId).toBe('u1')
    expect((workoutFindMany.mock.calls[0][0] as { where: { userId: string } }).where.userId).toBe('u1')
    await app.close()
  })
})

describe('GET /v1/me/stats/rank-lp — per-exercise LP snapshot', () => {
  it('returns LP rows ordered by lpTotal desc with bestE1rmKg as a number', async () => {
    userExerciseRankFindMany.mockResolvedValue([
      { exerciseId: 'e1', lpTotal: 320, bestE1rmKg: '142.5', exercise: { name: 'Squat' } },
      { exerciseId: 'e2', lpTotal: 180, bestE1rmKg: '100', exercise: { name: 'Bench' } },
    ])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats/rank-lp?limit=5' })

    expect(res.statusCode).toBe(200)
    const data = res.json().data
    expect(data).toHaveLength(2)
    expect(data[0]).toMatchObject({ exerciseId: 'e1', name: 'Squat', lpTotal: 320 })
    // Prisma Decimal (string) is coerced to a JS number.
    expect(data[0].bestE1rmKg).toBe(142.5)
    expect(typeof data[0].bestE1rmKg).toBe('number')
    // Query asks the DB for desc ordering and clamps the limit.
    const call = userExerciseRankFindMany.mock.calls[0][0] as { orderBy: { lpTotal: string }; take: number; where: { userId: string } }
    expect(call.orderBy).toEqual({ lpTotal: 'desc' })
    expect(call.where.userId).toBe('u1')
    await app.close()
  })

  it('clamps an over-large limit to 30', async () => {
    userExerciseRankFindMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/stats/rank-lp?limit=999' })

    expect(res.statusCode).toBe(200)
    expect((userExerciseRankFindMany.mock.calls[0][0] as { take: number }).take).toBe(30)
    await app.close()
  })
})
