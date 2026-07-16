import Fastify from 'fastify'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const workoutFindFirst = vi.fn()
const postFindUnique = vi.fn()
const postCreate = vi.fn()
const workoutUpdate = vi.fn()
const postPrivacyCreate = vi.fn()
const analyticsCreate = vi.fn()
const transaction = vi.fn()
const updateStreak = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    workout: {
      findFirst: (...args: unknown[]) => workoutFindFirst(...args),
      update: (...args: unknown[]) => workoutUpdate(...args),
    },
    post: {
      findUnique: (...args: unknown[]) => postFindUnique(...args),
      create: (...args: unknown[]) => postCreate(...args),
    },
    postPrivacySetting: {
      create: (...args: unknown[]) => postPrivacyCreate(...args),
    },
    analyticsEvent: { create: (...args: unknown[]) => analyticsCreate(...args) },
    $transaction: (...args: unknown[]) => transaction(...args),
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (request: { user?: { userId: string; email: string } }) => {
    request.user = { userId: 'user-1', email: 'user@example.com' }
  },
}))

vi.mock('../services/streak.service', () => ({
  updateStreak: (...args: unknown[]) => updateStreak(...args),
}))

import { postRoutes } from './posts'

beforeEach(() => {
  workoutFindFirst.mockReset().mockResolvedValue({
    id: '11111111-1111-4111-8111-111111111111',
    userId: 'user-1',
    status: 'completed',
    hasPr: true,
  })
  postFindUnique.mockReset().mockResolvedValue(null)
  postCreate.mockReset().mockImplementation(({ data }) => Promise.resolve({
    id: 'post-1',
    userId: 'user-1',
    workoutId: '11111111-1111-4111-8111-111111111111',
    visibility: data.visibility,
    caption: data.caption,
    isPr: data.isPr,
  }))
  workoutUpdate.mockReset().mockResolvedValue({ status: 'posted' })
  postPrivacyCreate.mockReset().mockResolvedValue({ id: 'privacy-1' })
  analyticsCreate.mockReset().mockResolvedValue({ id: 'event-1' })
  updateStreak.mockReset().mockResolvedValue(1)
  transaction
    .mockReset()
    .mockImplementation((operations: Promise<unknown>[]) =>
      Promise.all(operations),
    )
})

describe('POST /v1/posts workout PR propagation', () => {
  it('copies the rank result saved at completion without recalculating ranking', async () => {
    const app = Fastify()
    await app.register(postRoutes, { prefix: '/v1/posts' })
    await app.ready()

    const response = await app.inject({
      method: 'POST',
      url: '/v1/posts',
      payload: {
        workoutId: '11111111-1111-4111-8111-111111111111',
        visibility: 'private',
        caption: 'New personal record',
      },
    })

    expect(response.statusCode).toBe(201)
    expect(response.json().post.isPr).toBe(true)
    expect(postCreate.mock.calls[0][0].data.isPr).toBe(true)
    await app.close()
  })
})
