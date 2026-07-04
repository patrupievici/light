import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

const userBlockUpsert = vi.fn().mockResolvedValue({})
const userBlockDeleteMany = vi.fn().mockResolvedValue({ count: 1 })
const userBlockFindMany = vi.fn().mockResolvedValue([])
const userReportCreate = vi.fn().mockResolvedValue({})
const friendshipDeleteMany = vi.fn().mockResolvedValue({ count: 0 })
const userFindUnique = vi.fn().mockResolvedValue({ id: 'target' })
const txMock = vi.fn(async (ops: unknown) =>
  Array.isArray(ops) ? Promise.all(ops) : ops,
)

vi.mock('../lib/prisma', () => ({
  prisma: {
    user: { findUnique: (...a: unknown[]) => userFindUnique(...a) },
    userBlock: {
      upsert: (...a: unknown[]) => userBlockUpsert(...a),
      deleteMany: (...a: unknown[]) => userBlockDeleteMany(...a),
      findMany: (...a: unknown[]) => userBlockFindMany(...a),
    },
    userReport: { create: (...a: unknown[]) => userReportCreate(...a) },
    friendship: { deleteMany: (...a: unknown[]) => friendshipDeleteMany(...a) },
    $transaction: (...a: unknown[]) => txMock(...(a as [unknown])),
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'me', email: 'me@t.dev' }
  },
}))

import { moderationRoutes } from './moderation'

async function buildApp() {
  const app = Fastify()
  await app.register(moderationRoutes, { prefix: '/v1' })
  await app.ready()
  return app
}

beforeEach(() => {
  userBlockUpsert.mockClear()
  userBlockDeleteMany.mockClear()
  userBlockFindMany.mockReset().mockResolvedValue([])
  userReportCreate.mockClear()
  friendshipDeleteMany.mockClear()
  userFindUnique.mockReset().mockResolvedValue({ id: 'target' })
})

describe('POST /v1/users/:id/block', () => {
  it('blocks a user and severs friendship (both directions)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/users/target/block' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ blocked: true })
    expect(userBlockUpsert).toHaveBeenCalledOnce()
    expect(friendshipDeleteMany).toHaveBeenCalledOnce()
    await app.close()
  })

  it('400 when blocking yourself (no write)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/users/me/block' })
    expect(res.statusCode).toBe(400)
    expect(userBlockUpsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('404 when the target does not exist', async () => {
    userFindUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/users/ghost/block' })
    expect(res.statusCode).toBe(404)
    await app.close()
  })
})

describe('DELETE /v1/users/:id/block', () => {
  it('unblocks', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/users/target/block' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ blocked: false })
    expect(userBlockDeleteMany).toHaveBeenCalledOnce()
    await app.close()
  })
})

describe('GET /v1/me/blocked', () => {
  it('returns the block list in { data } shape', async () => {
    userBlockFindMany.mockResolvedValue([
      {
        blockedId: 'u2',
        createdAt: new Date('2026-01-01T00:00:00Z'),
        blocked: { id: 'u2', profile: { displayName: 'Bob', username: 'bob' } },
      },
    ])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/blocked' })
    expect(res.statusCode).toBe(200)
    expect(res.json().data[0]).toMatchObject({ userId: 'u2', displayName: 'Bob', username: 'bob' })
    await app.close()
  })
})

describe('POST /v1/users/:id/report', () => {
  it('files a report with a valid category', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/users/target/report',
      payload: { category: 'harassment', note: 'abusive DMs' },
    })
    expect(res.statusCode).toBe(201)
    expect(userReportCreate).toHaveBeenCalledOnce()
    await app.close()
  })

  it('400 on an invalid category (no write)', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/users/target/report',
      payload: { category: 'not-a-category' },
    })
    expect(res.statusCode).toBe(400)
    expect(userReportCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 when reporting yourself', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/users/me/report',
      payload: { category: 'spam' },
    })
    expect(res.statusCode).toBe(400)
    await app.close()
  })
})
