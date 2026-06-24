import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
const userExerciseRankFindUnique = vi.fn()
const userProfileFindUnique = vi.fn()
const exerciseFindUnique = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    userExerciseRank: { findUnique: (...a: unknown[]) => userExerciseRankFindUnique(...a) },
    userProfile: { findUnique: (...a: unknown[]) => userProfileFindUnique(...a) },
    exercise: { findUnique: (...a: unknown[]) => exerciseFindUnique(...a) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { rankRoutes } from './ranks'

const URL = '/v1/ranks/exercises/ex1/explain'

async function buildApp() {
  const app = Fastify()
  await app.register(rankRoutes, { prefix: '/v1/ranks' })
  await app.ready()
  return app
}

beforeEach(() => {
  userExerciseRankFindUnique.mockReset()
  userProfileFindUnique.mockReset()
  exerciseFindUnique.mockReset()
})

describe('GET /v1/ranks/exercises/:id/explain — bodyweight is required', () => {
  it('returns 404 (no fabricated rank) when the profile has NO bodyweight', async () => {
    // A rank row exists, but bodyweight is missing → the route must refuse to
    // synthesize an explanation off a guessed bodyweight.
    userExerciseRankFindUnique.mockResolvedValue({
      lpTotal: 150, strengthRatio: 1.5, bestE1rmKg: 120, exercise: { name: 'Squat' },
    })
    userProfileFindUnique.mockResolvedValue({ userId: 'u1', bodyweightKg: null })
    exerciseFindUnique.mockResolvedValue({ id: 'ex1', name: 'Squat', rankModel: 'WEIGHTED' })

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: URL })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    // No explainability payload leaked.
    expect(res.json()).not.toHaveProperty('strengthRatio')
    expect(res.json()).not.toHaveProperty('nextTier')
    await app.close()
  })

  it('returns 404 when there is a bodyweight but NO rank yet (nothing to explain)', async () => {
    userExerciseRankFindUnique.mockResolvedValue(null)
    userProfileFindUnique.mockResolvedValue({ userId: 'u1', bodyweightKg: 80 })
    exerciseFindUnique.mockResolvedValue({ id: 'ex1', name: 'Squat', rankModel: 'WEIGHTED' })

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: URL })

    expect(res.statusCode).toBe(404)
    await app.close()
  })

  it('returns 200 with a real, bodyweight-anchored explanation when both exist', async () => {
    userExerciseRankFindUnique.mockResolvedValue({
      lpTotal: 150, strengthRatio: 1.5, bestE1rmKg: 120, exercise: { name: 'Squat' },
    })
    userProfileFindUnique.mockResolvedValue({ userId: 'u1', bodyweightKg: 80 })
    exerciseFindUnique.mockResolvedValue({
      id: 'ex1', name: 'Squat', rankModel: 'WEIGHTED', bwStrengthFraction: null,
    })

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: URL })

    expect(res.statusCode).toBe(200)
    const body = res.json()
    // The explanation is grounded in the ACTUAL bodyweight (80), not a fallback.
    expect(body.bodyweightAtCalc).toBe(80)
    expect(body.currentLP).toBe(150)
    expect(body.nextTier).toMatchObject({ lpNeeded: 200, lpRemaining: 50 })
    expect(body.explanation).toContain('80')
    await app.close()
  })
})
