import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

const workoutSet = { findMany: vi.fn() }
const userExerciseRank = { findMany: vi.fn() }

vi.mock('../lib/prisma', () => ({
  prisma: {
    workoutSet: { findMany: (...a: unknown[]) => workoutSet.findMany(...a) },
    userExerciseRank: { findMany: (...a: unknown[]) => userExerciseRank.findMany(...a) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { muscleLevelsRoutes } from './muscle-levels'

async function buildApp() {
  const app = Fastify()
  await app.register(muscleLevelsRoutes, { prefix: '/v1/me' })
  await app.ready()
  return app
}

function chestSet(weightKg: number, reps: number) {
  return {
    weightKg,
    reps,
    createdAt: new Date('2026-06-20T10:00:00.000Z'),
    workoutExercise: { exercise: { primaryMuscle: 'chest', secondaryMuscles: ['triceps'] } },
  }
}

beforeEach(() => {
  workoutSet.findMany.mockReset()
  userExerciseRank.findMany.mockReset()
})

describe('GET /v1/me/muscle-levels', () => {
  it('attributes primary 1.0 / secondary 0.5 volume and folds in strength LP', async () => {
    // chest primary (×1.0), triceps secondary (×0.5). Bench rank gives chest LP 350.
    workoutSet.findMany.mockResolvedValue([chestSet(100, 5), chestSet(100, 5)])
    userExerciseRank.findMany.mockResolvedValue([
      { lpTotal: 350, exercise: { primaryMuscle: 'chest' } },
    ])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/muscle-levels' })
    expect(res.statusCode).toBe(200)
    const data = res.json().data as Array<Record<string, number | string>>
    const chest = data.find((m) => m.slug === 'chest')!
    const triceps = data.find((m) => m.slug === 'triceps')!
    // 2 sets × 100 × 5 = 1000 chest volumeXp; triceps 0.5× = 500
    expect(chest.volumeXp).toBe(1000)
    expect(triceps.volumeXp).toBe(500)
    expect(chest.workSets).toBe(2)
    // secondary muscle (triceps) also gets trained-metadata, not just volumeXp
    expect(triceps.workSets).toBe(2)
    expect(triceps.volumeKg).toBe(500)
    // chest: volumeLevel floor(sqrt(1000/2000))=0, strengthBonus floor(350/100)=3 → level 3
    expect(chest.strengthBonus).toBe(3)
    expect(chest.level).toBe(3)
    // sorted by level desc → chest (3) before triceps (1)
    expect(data[0].slug).toBe('chest')
    await app.close()
  })

  it('omits untrained muscles by default, includes them with includeUntrained', async () => {
    workoutSet.findMany.mockResolvedValue([chestSet(100, 5)])
    userExerciseRank.findMany.mockResolvedValue([])
    const app = await buildApp()

    const trained = await app.inject({ method: 'GET', url: '/v1/me/muscle-levels' })
    const trainedData = trained.json().data as Array<{ slug: string }>
    expect(trainedData.map((m) => m.slug).sort()).toEqual(['chest', 'triceps'])

    const all = await app.inject({ method: 'GET', url: '/v1/me/muscle-levels?includeUntrained=true' })
    expect((all.json().data as unknown[]).length).toBe(15) // all SVG slugs
    await app.close()
  })

  it('returns an empty list for a user with no work sets', async () => {
    workoutSet.findMany.mockResolvedValue([])
    userExerciseRank.findMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/muscle-levels' })
    expect(res.json().data).toEqual([])
    await app.close()
  })
})
