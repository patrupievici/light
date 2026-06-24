import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
const notificationFindMany = vi.fn()
const notificationCount = vi.fn()
const notificationUpdateMany = vi.fn()
const userProfileFindMany = vi.fn()
const authIdentityFindMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    notification: {
      findMany: (...a: unknown[]) => notificationFindMany(...a),
      count: (...a: unknown[]) => notificationCount(...a),
      updateMany: (...a: unknown[]) => notificationUpdateMany(...a),
    },
    userProfile: { findMany: (...a: unknown[]) => userProfileFindMany(...a) },
    // getUserDisplayHints falls back to authIdentity for an email hint when a
    // profile has no name — stub it so actor-hint resolution never reaches a DB.
    authIdentity: { findMany: (...a: unknown[]) => authIdentityFindMany(...a) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { notificationRoutes } from './notifications'

async function buildApp() {
  const app = Fastify()
  await app.register(notificationRoutes, { prefix: '/v1/notifications' })
  await app.ready()
  return app
}

beforeEach(() => {
  notificationFindMany.mockReset()
  notificationCount.mockReset()
  notificationUpdateMany.mockReset()
  userProfileFindMany.mockReset()
  authIdentityFindMany.mockReset()
  userProfileFindMany.mockResolvedValue([])
  authIdentityFindMany.mockResolvedValue([])
})

describe('GET /v1/notifications — owner-scoped list', () => {
  it('queries ONLY the authenticated user\'s notifications and paginates', async () => {
    notificationFindMany.mockResolvedValue([
      { id: 'n1', type: 'friend_request', actorId: 'a1', payload: {}, readAt: null, createdAt: new Date('2026-06-01T00:00:00Z') },
    ])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/notifications?page=2&limit=5' })

    expect(res.statusCode).toBe(200)
    const call = notificationFindMany.mock.calls[0][0] as { where: { userId: string }; skip: number; take: number }
    // Hard owner scope — a notification for any other user is never selectable.
    expect(call.where).toEqual({ userId: 'u1' })
    // page=2, limit=5 → skip 5, take 5.
    expect(call.skip).toBe(5)
    expect(call.take).toBe(5)
    expect(res.json().meta).toMatchObject({ page: 2, limit: 5 })
    await app.close()
  })

  it('clamps an over-large limit to 50', async () => {
    notificationFindMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/notifications?limit=9999' })

    expect(res.statusCode).toBe(200)
    expect((notificationFindMany.mock.calls[0][0] as { take: number }).take).toBe(50)
    await app.close()
  })
})

describe('GET /v1/notifications/unread-count', () => {
  it('counts only unread notifications for the owner', async () => {
    notificationCount.mockResolvedValue(3)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/notifications/unread-count' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ count: 3 })
    expect((notificationCount.mock.calls[0][0] as { where: object }).where).toEqual({ userId: 'u1', readAt: null })
    await app.close()
  })
})

describe('POST /v1/notifications/:id/read — mark one read', () => {
  it('marks the notification read ONLY when it belongs to the owner', async () => {
    notificationUpdateMany.mockResolvedValue({ count: 1 })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/notifications/n1/read' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ ok: true })
    // The WHERE clause includes the owner id → can't mark someone else's read.
    expect((notificationUpdateMany.mock.calls[0][0] as { where: object }).where).toEqual({ id: 'n1', userId: 'u1' })
    await app.close()
  })

  it('404 when the id is not the owner\'s (updateMany affected 0 rows)', async () => {
    notificationUpdateMany.mockResolvedValue({ count: 0 })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/notifications/someone-elses/read' })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    await app.close()
  })
})

describe('POST /v1/notifications/read-all', () => {
  it('marks all of the owner\'s unread notifications read', async () => {
    notificationUpdateMany.mockResolvedValue({ count: 4 })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/notifications/read-all' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ ok: true })
    const arg = notificationUpdateMany.mock.calls[0][0] as { where: object; data: { readAt: Date } }
    expect(arg.where).toEqual({ userId: 'u1', readAt: null })
    expect(arg.data.readAt).toBeInstanceOf(Date)
    await app.close()
  })
})
