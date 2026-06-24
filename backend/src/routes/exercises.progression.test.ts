import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
const trainingProfileFindUnique = vi.fn()
const computeProgressiveLoads = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    userTrainingProfile: {
      findUnique: (...a: unknown[]) => trainingProfileFindUnique(...a),
    },
    // exerciseRoutes references other models at import/use; the progression
    // route only touches userTrainingProfile + the (mocked) engine.
    workoutSet: { findMany: vi.fn() },
    exercise: { findMany: vi.fn() },
  },
}))

vi.mock('../lib/progressive-overload', () => ({
  computeProgressiveLoads: (...a: unknown[]) => computeProgressiveLoads(...a),
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { exerciseRoutes } from './exercises'

async function buildApp() {
  const app = Fastify()
  await app.register(exerciseRoutes, { prefix: '/v1/exercises' })
  await app.ready()
  return app
}

const DECISION = {
  suggestedWeightKg: 82.5,
  suggestedReps: 8,
  source: 'progression',
  reason: 'Linear progression: hit the prescription → +2.5kg to 82.5kg.',
}

beforeEach(() => {
  trainingProfileFindUnique.mockReset()
  computeProgressiveLoads.mockReset()
  computeProgressiveLoads.mockResolvedValue([DECISION])
})

describe('GET /v1/exercises/:id/progression — auto-progression endpoint', () => {
  it('returns the engine decision wrapped in { data } and forwards level + scheme', async () => {
    trainingProfileFindUnique.mockResolvedValue({
      trainingLevel: 'intermediate',
      progressionScheme: 'linear',
    })
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/exercises/ex1/progression?reps=5' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ data: DECISION })

    // userId, inputs (exerciseId + clamped reps), level, opts.scheme all wired through.
    expect(computeProgressiveLoads).toHaveBeenCalledWith(
      'u1',
      [{ exerciseId: 'ex1', prescribedReps: 5 }],
      'intermediate',
      { progressionScheme: 'linear' },
    )
    await app.close()
  })

  it('defaults level to beginner (the brief +2.5kg) when no profile/level is set', async () => {
    trainingProfileFindUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/exercises/ex1/progression' })

    expect(res.statusCode).toBe(200)
    const [, , level, opts] = computeProgressiveLoads.mock.calls[0]
    expect(level).toBe('beginner')
    expect(opts).toEqual({ progressionScheme: undefined })
    await app.close()
  })

  it('defaults prescribedReps to 8 and ignores out-of-range reps', async () => {
    trainingProfileFindUnique.mockResolvedValue({ trainingLevel: 'beginner', progressionScheme: 'auto' })
    const app = await buildApp()
    await app.inject({ method: 'GET', url: '/v1/exercises/ex1/progression?reps=999' })

    const [, inputs] = computeProgressiveLoads.mock.calls[0]
    expect(inputs).toEqual([{ exerciseId: 'ex1', prescribedReps: 8 }])
    await app.close()
  })
})
