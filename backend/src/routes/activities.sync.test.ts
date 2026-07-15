import { beforeEach, describe, expect, it, vi } from 'vitest'
import Fastify from 'fastify'

const gpsCreate = vi.fn()
const gpsFindMany = vi.fn()
const workoutFindMany = vi.fn()
const plannedFindMany = vi.fn()
const nutritionFindMany = vi.fn()
const analyticsCreate = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    gpsActivity: {
      create: (...args: unknown[]) => gpsCreate(...args),
      findMany: (...args: unknown[]) => gpsFindMany(...args),
    },
    workout: { findMany: (...args: unknown[]) => workoutFindMany(...args) },
    plannedWorkout: { findMany: (...args: unknown[]) => plannedFindMany(...args) },
    nutritionPlanDay: { findMany: (...args: unknown[]) => nutritionFindMany(...args) },
    analyticsEvent: { create: (...args: unknown[]) => analyticsCreate(...args) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (request: { user?: { userId: string; email: string } }) => {
    request.user = { userId: 'u1', email: 'u1@test.dev' }
  },
}))

import { activitiesRoutes } from './activities'

async function buildApp() {
  const app = Fastify()
  await app.register(activitiesRoutes, { prefix: '/v1/activities' })
  await app.ready()
  return app
}

beforeEach(() => {
  gpsCreate.mockReset()
  gpsFindMany.mockReset()
  workoutFindMany.mockReset()
  plannedFindMany.mockReset()
  nutritionFindMany.mockReset()
  analyticsCreate.mockReset()
  analyticsCreate.mockResolvedValue({})
  plannedFindMany.mockResolvedValue([])
  nutritionFindMany.mockResolvedValue([])
})

describe('GPS sport synchronization', () => {
  it('persists a cycle alias as ride and returns the canonical type', async () => {
    gpsCreate.mockImplementation(({ data }) => ({ id: 'gps-1', ...data, createdAt: new Date() }))
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/activities',
      payload: {
        activity_type: 'cycle',
        distance_m: 10_000,
        duration_s: 3_600,
        started_at: '2026-07-01T08:00:00.000Z',
        ended_at: '2026-07-01T09:00:00.000Z',
      },
    })

    expect(res.statusCode).toBe(201)
    expect(res.json().activity.type).toBe('ride')
    expect(gpsCreate.mock.calls[0][0].data.activityType).toBe('ride')
    await app.close()
  })

  it('does not misclassify a slow ride as a run in the unified feed', async () => {
    gpsFindMany.mockResolvedValue([
      {
        id: 'gps-1',
        userId: 'u1',
        activityType: 'ride',
        distanceM: 10_000,
        durationS: 3_600,
        calories: 400,
        startedAt: new Date('2026-07-01T08:00:00.000Z'),
        endedAt: new Date('2026-07-01T09:00:00.000Z'),
      },
    ])
    workoutFindMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/activities/feed' })

    expect(res.statusCode).toBe(200)
    expect(res.json().feed).toHaveLength(1)
    expect(res.json().feed[0].type).toBe('ride')
    await app.close()
  })

  it('includes GPS types alongside gym in the monthly calendar', async () => {
    workoutFindMany.mockResolvedValue([
      { id: 'w1', startedAt: new Date('2026-07-01T12:00:00.000Z') },
    ])
    gpsFindMany.mockResolvedValue([
      {
        id: 'g1',
        userId: 'u1',
        activityType: 'run',
        distanceM: 5_000,
        durationS: 1_800,
        calories: 300,
        startedAt: new Date('2026-07-01T08:00:00.000Z'),
        endedAt: new Date('2026-07-01T08:30:00.000Z'),
      },
      {
        id: 'g2',
        userId: 'u1',
        activityType: 'ride',
        distanceM: 10_000,
        durationS: 3_600,
        calories: 400,
        startedAt: new Date('2026-07-01T18:00:00.000Z'),
        endedAt: new Date('2026-07-01T19:00:00.000Z'),
      },
    ])
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: '/v1/activities/calendar?month=2026-07&tzOffset=0',
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().days['2026-07-01'].types).toEqual(['gym', 'run', 'ride'])
    await app.close()
  })
})
