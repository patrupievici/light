import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// Offline-first workout creation: POST /v1/workouts accepts an optional
// client-provided PK (`id`) and upserts on it so a queued create replays
// idempotently. These tests pin that contract.
const workoutFindUnique = vi.fn()
const workoutUpsert = vi.fn()
const workoutCreate = vi.fn()
const analyticsEventCreate = vi.fn().mockResolvedValue({})

vi.mock('../lib/prisma', () => ({
  prisma: {
    workout: {
      findUnique: (...a: unknown[]) => workoutFindUnique(...a),
      upsert: (...a: unknown[]) => workoutUpsert(...a),
      create: (...a: unknown[]) => workoutCreate(...a),
    },
    analyticsEvent: { create: (...a: unknown[]) => analyticsEventCreate(...a) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { workoutRoutes } from './workouts'

const CID = '11111111-1111-4111-8111-111111111111'

async function buildApp() {
  const app = Fastify()
  await app.register(workoutRoutes, { prefix: '/v1/workouts' })
  await app.ready()
  return app
}

beforeEach(() => {
  workoutFindUnique.mockReset()
  workoutUpsert.mockReset()
  workoutCreate.mockReset()
  analyticsEventCreate.mockClear()
})

describe('POST /v1/workouts — offline-first client id', () => {
  it('no client id → plain server-generated create', async () => {
    const app = await buildApp()
    workoutCreate.mockResolvedValue({ id: 'srv1', userId: 'u1', status: 'draft' })
    const res = await app.inject({ method: 'POST', url: '/v1/workouts', payload: {} })
    expect(res.statusCode).toBe(201)
    expect(workoutCreate).toHaveBeenCalledTimes(1)
    expect(workoutUpsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('client id, first time → upsert create on that id + analytics event', async () => {
    const app = await buildApp()
    workoutFindUnique.mockResolvedValue(null)
    workoutUpsert.mockResolvedValue({ id: CID, userId: 'u1', status: 'draft' })
    const res = await app.inject({ method: 'POST', url: '/v1/workouts', payload: { id: CID } })
    expect(res.statusCode).toBe(201)
    expect(res.json().workout.id).toBe(CID)
    expect(workoutUpsert).toHaveBeenCalledTimes(1)
    expect(analyticsEventCreate).toHaveBeenCalledTimes(1)
    await app.close()
  })

  it('client id replay (already exists, same user) → idempotent, no new analytics event', async () => {
    const app = await buildApp()
    workoutFindUnique.mockResolvedValue({ id: CID, userId: 'u1', status: 'draft' })
    workoutUpsert.mockResolvedValue({ id: CID, userId: 'u1', status: 'draft' })
    const res = await app.inject({ method: 'POST', url: '/v1/workouts', payload: { id: CID } })
    expect(res.statusCode).toBe(201)
    expect(workoutUpsert).toHaveBeenCalledTimes(1)
    expect(analyticsEventCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('client id owned by ANOTHER user → 409 ID_CONFLICT, no upsert', async () => {
    const app = await buildApp()
    workoutFindUnique.mockResolvedValue({ id: CID, userId: 'someone-else', status: 'draft' })
    const res = await app.inject({ method: 'POST', url: '/v1/workouts', payload: { id: CID } })
    expect(res.statusCode).toBe(409)
    expect(res.json()).toMatchObject({ error: 'ID_CONFLICT' })
    expect(workoutUpsert).not.toHaveBeenCalled()
    await app.close()
  })
})
