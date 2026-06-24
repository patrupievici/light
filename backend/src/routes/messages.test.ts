import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Mock prisma so the REAL `areFriends` gate (which reads prisma.friendship) runs
// end-to-end. directConversation/directMessage + notification cover the send
// + open flows.
const friendshipFindFirst = vi.fn()
const convFindFirst = vi.fn()
const convUpsert = vi.fn()
const convUpdate = vi.fn()
const msgCreate = vi.fn()
const notificationCreate = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    friendship: { findFirst: (...a: unknown[]) => friendshipFindFirst(...a) },
    directConversation: {
      findFirst: (...a: unknown[]) => convFindFirst(...a),
      upsert: (...a: unknown[]) => convUpsert(...a),
      update: (...a: unknown[]) => convUpdate(...a),
    },
    directMessage: { create: (...a: unknown[]) => msgCreate(...a) },
    notification: { create: (...a: unknown[]) => notificationCreate(...a) },
  },
}))

vi.mock('../services/fcm.service', () => ({
  sendPushForInAppNotification: vi.fn().mockResolvedValue(undefined),
}))

let meId = 'me'
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: meId, email: `${meId}@t.dev` }
  },
}))

import { messagesRoutes } from './messages'

async function buildApp() {
  const app = Fastify()
  await app.register(messagesRoutes, { prefix: '/v1/messages' })
  await app.ready()
  return app
}

const PEER = '22222222-2222-2222-2222-222222222222'

beforeEach(() => {
  meId = 'me'
  friendshipFindFirst.mockReset()
  convFindFirst.mockReset()
  convUpsert.mockReset()
  convUpdate.mockReset()
  msgCreate.mockReset()
  notificationCreate.mockReset()
  notificationCreate.mockResolvedValue({ id: 'n1', userId: PEER, type: 'dm_message', actorId: 'me', payload: {} })
  convUpdate.mockResolvedValue({ id: 'c1' })
})

describe('POST /v1/messages/conversations/open — DM gating', () => {
  it('400 when trying to open a conversation with yourself', async () => {
    meId = PEER
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/messages/conversations/open', payload: { peerUserId: PEER } })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    // Gate is hit before any friendship lookup or upsert.
    expect(friendshipFindFirst).not.toHaveBeenCalled()
    expect(convUpsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('403 FORBIDDEN when the peer is NOT an accepted friend', async () => {
    friendshipFindFirst.mockResolvedValue(null) // not friends
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/messages/conversations/open', payload: { peerUserId: PEER } })

    expect(res.statusCode).toBe(403)
    expect(res.json()).toMatchObject({ error: 'FORBIDDEN' })
    // No conversation is created for a non-friend.
    expect(convUpsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('opens (upserts) the conversation with deterministic low/high ordering for friends', async () => {
    friendshipFindFirst.mockResolvedValue({ id: 'f1', status: 'accepted' })
    convUpsert.mockResolvedValue({
      id: 'c1',
      userLowId: 'me', // 'me' < PEER lexically
      userHighId: PEER,
      userLow: { id: 'me', profile: { username: 'me', displayName: 'Me' } },
      userHigh: { id: PEER, profile: { username: 'peer', displayName: 'Peer' } },
    })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/messages/conversations/open', payload: { peerUserId: PEER } })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ conversationId: 'c1', peer: { userId: PEER } })
    // Composite key uses ordered (low, high) ids so the pair maps to ONE row.
    const upsertArg = convUpsert.mock.calls[0][0] as { where: { userLowId_userHighId: { userLowId: string; userHighId: string } } }
    const { userLowId, userHighId } = upsertArg.where.userLowId_userHighId
    expect(userLowId < userHighId).toBe(true)
    expect([userLowId, userHighId].sort()).toEqual(['me', PEER].sort())
    await app.close()
  })

  it('400 on a non-UUID peerUserId', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/messages/conversations/open', payload: { peerUserId: 'nope' } })

    expect(res.statusCode).toBe(400)
    expect(friendshipFindFirst).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('POST /v1/messages/conversations/:id/messages — send', () => {
  it('404 when the sender is not a participant of the conversation', async () => {
    convFindFirst.mockResolvedValue(null) // membership scope filters it out
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/messages/conversations/c1/messages', payload: { body: 'hi' } })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    expect(msgCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('persists the message, bumps updatedAt, and notifies the peer', async () => {
    convFindFirst.mockResolvedValue({ id: 'c1', userLowId: 'me', userHighId: PEER })
    msgCreate.mockResolvedValue({ id: 'm1', senderId: 'me', body: 'hello', createdAt: new Date('2026-01-01T00:00:00Z') })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/messages/conversations/c1/messages', payload: { body: 'hello' } })

    expect(res.statusCode).toBe(201)
    expect(res.json().message).toMatchObject({ id: 'm1', senderId: 'me', body: 'hello' })
    expect(msgCreate).toHaveBeenCalledOnce()
    expect(convUpdate).toHaveBeenCalledOnce() // updatedAt bump for conversation ordering
    // The OTHER participant (peer), not the sender, is notified.
    expect(notificationCreate).toHaveBeenCalledOnce()
    expect((notificationCreate.mock.calls[0][0] as { data: { userId: string } }).data.userId).toBe(PEER)
    await app.close()
  })

  it('400 on an empty message body (min length enforced)', async () => {
    convFindFirst.mockResolvedValue({ id: 'c1', userLowId: 'me', userHighId: PEER })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/messages/conversations/c1/messages', payload: { body: '' } })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(msgCreate).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('GET /v1/messages/conversations/:id/messages — read', () => {
  it('404 for a conversation the viewer is not part of', async () => {
    convFindFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/messages/conversations/c1/messages' })

    expect(res.statusCode).toBe(404)
    await app.close()
  })
})
