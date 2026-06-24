import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
const routineFindMany = vi.fn()
const routineFindFirst = vi.fn()
const routineCreate = vi.fn()
const routineCount = vi.fn()
const transaction = vi.fn()
const analyticsCreate = vi.fn()
const exerciseFindMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    routine: {
      findMany: (...a: unknown[]) => routineFindMany(...a),
      findFirst: (...a: unknown[]) => routineFindFirst(...a),
      create: (...a: unknown[]) => routineCreate(...a),
      count: (...a: unknown[]) => routineCount(...a),
      update: vi.fn(),
      delete: vi.fn(),
    },
    exercise: { findMany: (...a: unknown[]) => exerciseFindMany(...a) },
    analyticsEvent: { create: (...a: unknown[]) => analyticsCreate(...a) },
    $transaction: (fn: (tx: unknown) => unknown) => transaction(fn),
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { routineRoutes } from './routines'

async function buildApp() {
  const app = Fastify()
  await app.register(routineRoutes, { prefix: '/v1/routines' })
  await app.ready()
  return app
}

const NOW = new Date('2026-06-24T00:00:00Z')
const STORED = {
  id: 'r1',
  name: 'Push Day',
  focus: 'Chest • Shoulders • Triceps',
  exercisesJson: [
    { name: 'Bench Press', exerciseId: 'ex1', sets: 3, reps: 8, restSeconds: 120 },
    { name: 'Incline DB Press', exerciseId: 'ex2', sets: 3, reps: 10 },
  ],
  position: 0,
  createdAt: NOW,
  updatedAt: NOW,
}

beforeEach(() => {
  routineFindMany.mockReset()
  routineFindFirst.mockReset()
  routineCreate.mockReset()
  routineCount.mockReset().mockResolvedValue(0)
  transaction.mockReset()
  analyticsCreate.mockReset().mockResolvedValue({})
  // By default the two seeded exercise ids resolve in the catalog.
  exerciseFindMany.mockReset().mockResolvedValue([{ id: 'ex1' }, { id: 'ex2' }])
})

describe('routines CRUD + start', () => {
  it('POST / creates a routine and returns it with a derived exerciseCount', async () => {
    routineCreate.mockResolvedValue(STORED)
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/routines',
      payload: {
        name: 'Push Day',
        focus: 'Chest • Shoulders • Triceps',
        exercises: STORED.exercisesJson,
      },
    })
    expect(res.statusCode).toBe(201)
    const body = res.json()
    expect(body.routine.id).toBe('r1')
    expect(body.routine.exerciseCount).toBe(2)
    await app.close()
  })

  it('POST / rejects an empty exercise list (400)', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/routines',
      payload: { name: 'Empty', exercises: [] },
    })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('GET / lists the user routines (serialized)', async () => {
    routineFindMany.mockResolvedValue([STORED])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/routines' })
    expect(res.statusCode).toBe(200)
    expect(res.json().data).toHaveLength(1)
    expect(res.json().data[0].exerciseCount).toBe(2)
    await app.close()
  })

  it('GET /:id returns 404 when the routine is not the user’s', async () => {
    routineFindFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/routines/nope' })
    expect(res.statusCode).toBe(404)
    await app.close()
  })

  it('POST /:id/start builds a draft workout from the routine', async () => {
    routineFindFirst.mockResolvedValue(STORED)
    // The route runs its body inside prisma.$transaction(fn) — drive fn with a
    // tx stub whose creators return fakes, and have it resolve to a workout id.
    transaction.mockImplementation(async (fn: (tx: unknown) => unknown) => {
      const tx = {
        workout: { create: vi.fn().mockResolvedValue({ id: 'w99' }) },
        workoutExercise: { create: vi.fn().mockResolvedValue({ id: 'we1' }) },
        workoutSet: { create: vi.fn().mockResolvedValue({ id: 's1' }) },
      }
      return fn(tx)
    })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/routines/r1/start' })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toEqual({ workout: { id: 'w99' } })
    await app.close()
  })

  it('POST /:id/start returns 400 when no exercises resolve to the catalog', async () => {
    routineFindFirst.mockResolvedValue({
      ...STORED,
      exercisesJson: [{ name: 'Made-up lift', exerciseId: null }],
    })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/routines/r1/start' })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('POST /:id/start returns 400 (no FK 500) when exerciseId is forged / not in the catalog', async () => {
    routineFindFirst.mockResolvedValue({
      ...STORED,
      exercisesJson: [{ name: 'Hacked', exerciseId: 'not-a-real-id' }],
    })
    exerciseFindMany.mockResolvedValue([]) // id resolves to nothing for this user
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/routines/r1/start' })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('NO_EXERCISES')
    await app.close()
  })
})
