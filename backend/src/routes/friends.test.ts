import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Mock prisma at the lib level so the REAL friendship lib + notification helpers
// run against our stubs (no separate service stubs needed). `friendship.*`,
// `user.findUnique`, `userProfile.findMany`, and `notification.*` are everything
// the request/accept/block flows touch.
const friendshipFindFirst = vi.fn()
const friendshipFindMany = vi.fn()
const friendshipCreate = vi.fn()
const friendshipUpdate = vi.fn()
const friendshipDeleteMany = vi.fn()
const userFindUnique = vi.fn()
const userProfileFindMany = vi.fn()
const notificationCreate = vi.fn()
const notificationUpdateMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    friendship: {
      findFirst: (...a: unknown[]) => friendshipFindFirst(...a),
      findMany: (...a: unknown[]) => friendshipFindMany(...a),
      create: (...a: unknown[]) => friendshipCreate(...a),
      update: (...a: unknown[]) => friendshipUpdate(...a),
      deleteMany: (...a: unknown[]) => friendshipDeleteMany(...a),
    },
    user: { findUnique: (...a: unknown[]) => userFindUnique(...a) },
    userProfile: { findMany: (...a: unknown[]) => userProfileFindMany(...a) },
    notification: {
      create: (...a: unknown[]) => notificationCreate(...a),
      updateMany: (...a: unknown[]) => notificationUpdateMany(...a),
    },
  },
}))

// fcm push is fire-and-forget inside createNotificationSafe — stub so a created
// notification doesn't try to reach a real push service.
vi.mock('../services/fcm.service', () => ({
  sendPushForInAppNotification: vi.fn().mockResolvedValue(undefined),
}))

// Async authenticate injecting `me` (a sync preHandler would hang Fastify).
let meId = 'me'
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: meId, email: `${meId}@t.dev` }
  },
}))

import { friendRoutes } from './friends'

async function buildApp() {
  const app = Fastify()
  await app.register(friendRoutes, { prefix: '/v1/friends' })
  await app.ready()
  return app
}

beforeEach(() => {
  meId = 'me'
  friendshipFindFirst.mockReset()
  friendshipFindMany.mockReset()
  friendshipCreate.mockReset()
  friendshipUpdate.mockReset()
  friendshipDeleteMany.mockReset()
  userFindUnique.mockReset()
  userProfileFindMany.mockReset()
  notificationCreate.mockReset()
  notificationUpdateMany.mockReset()
  notificationCreate.mockResolvedValue({ id: 'n1', userId: 'x', type: 't', actorId: 'me', payload: {} })
  notificationUpdateMany.mockResolvedValue({ count: 0 })
  userProfileFindMany.mockResolvedValue([])
})

const TARGET = '11111111-1111-1111-1111-111111111111'

describe('POST /v1/friends/requests — send request', () => {
  it('rejects befriending yourself with 400 INVALID_TARGET (no DB write)', async () => {
    meId = TARGET // authenticate as the same id we target
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'INVALID_TARGET' })
    // Never reaches the existence check or any write.
    expect(userFindUnique).not.toHaveBeenCalled()
    expect(friendshipCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('404 when the target user does not exist', async () => {
    userFindUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    expect(friendshipCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('creates a "requested" row + notifies the target on a fresh request', async () => {
    userFindUnique.mockResolvedValue({ id: TARGET })
    friendshipFindFirst.mockResolvedValue(null) // no prior relation
    friendshipCreate.mockResolvedValue({ id: 'f1', userId: 'me', friendUserId: TARGET, status: 'requested' })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ status: 'requested', friendshipId: 'f1' })
    const createArg = friendshipCreate.mock.calls[0][0] as { data: { userId: string; friendUserId: string; status: string } }
    expect(createArg.data).toMatchObject({ userId: 'me', friendUserId: TARGET, status: 'requested' })
    // The target is notified of the incoming request.
    expect(notificationCreate).toHaveBeenCalledOnce()
    expect((notificationCreate.mock.calls[0][0] as { data: { userId: string } }).data.userId).toBe(TARGET)
    await app.close()
  })

  it('409 ALREADY_FRIENDS when an accepted relation already exists', async () => {
    userFindUnique.mockResolvedValue({ id: TARGET })
    friendshipFindFirst.mockResolvedValue({ id: 'f1', userId: 'me', friendUserId: TARGET, status: 'accepted' })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(409)
    expect(res.json()).toMatchObject({ error: 'ALREADY_FRIENDS' })
    expect(friendshipCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('409 REQUEST_PENDING when I already sent a request to them', async () => {
    userFindUnique.mockResolvedValue({ id: TARGET })
    friendshipFindFirst.mockResolvedValue({ id: 'f1', userId: 'me', friendUserId: TARGET, status: 'requested' })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(409)
    expect(res.json()).toMatchObject({ error: 'REQUEST_PENDING' })
    await app.close()
  })

  it('auto-accepts when THEY already requested ME (reverse-pending → accepted)', async () => {
    userFindUnique.mockResolvedValue({ id: TARGET })
    // Reverse direction: the target requested me first.
    friendshipFindFirst.mockResolvedValue({ id: 'f9', userId: TARGET, friendUserId: 'me', status: 'requested' })
    friendshipUpdate.mockResolvedValue({ id: 'f9', status: 'accepted' })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ status: 'accepted', friendshipId: 'f9' })
    // Updates the existing row rather than creating a duplicate.
    expect(friendshipUpdate).toHaveBeenCalledOnce()
    expect((friendshipUpdate.mock.calls[0][0] as { data: { status: string } }).data.status).toBe('accepted')
    expect(friendshipCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('403 BLOCKED when a blocked relation exists', async () => {
    userFindUnique.mockResolvedValue({ id: TARGET })
    friendshipFindFirst.mockResolvedValue({ id: 'f1', userId: TARGET, friendUserId: 'me', status: 'blocked' })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(403)
    expect(res.json()).toMatchObject({ error: 'BLOCKED' })
    expect(friendshipCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 on a non-UUID userId', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/requests', payload: { userId: 'not-a-uuid' } })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })
})

describe('POST /v1/friends/accept', () => {
  it('accepts a pending request FROM the given user', async () => {
    friendshipFindFirst.mockResolvedValue({ id: 'f3', userId: TARGET, friendUserId: 'me', status: 'requested' })
    friendshipUpdate.mockResolvedValue({ id: 'f3', status: 'accepted' })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/accept', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ ok: true, friendshipId: 'f3' })
    // Only an incoming (from→me) requested row is acceptable.
    const whereArg = (friendshipFindFirst.mock.calls[0][0] as { where: { userId: string; friendUserId: string; status: string } }).where
    expect(whereArg).toMatchObject({ userId: TARGET, friendUserId: 'me', status: 'requested' })
    expect(friendshipUpdate).toHaveBeenCalledOnce()
    await app.close()
  })

  it('404 when there is no pending request from that user', async () => {
    friendshipFindFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/friends/accept', payload: { userId: TARGET } })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    expect(friendshipUpdate).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('DELETE /v1/friends/:userId — unfriend / cancel', () => {
  it('deletes the relation in either direction and returns ok', async () => {
    friendshipDeleteMany.mockResolvedValue({ count: 1 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/friends/${TARGET}` })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ ok: true })
    // The delete matches BOTH directions of the pair.
    const whereArg = (friendshipDeleteMany.mock.calls[0][0] as { where: { OR: unknown[] } }).where
    expect(whereArg.OR).toHaveLength(2)
    await app.close()
  })

  it('404 when there is no relation to delete', async () => {
    friendshipDeleteMany.mockResolvedValue({ count: 0 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/friends/${TARGET}` })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    await app.close()
  })
})
