import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { createNotificationSafe } from '../services/notification.service'
import { areFriends, isBlockedEitherWay, blockedUserIds } from '../lib/friendships'

function orderedUserIds(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a]
}

function peerIdFromConversation(
  conv: { userLowId: string; userHighId: string },
  me: string,
): string {
  return conv.userLowId === me ? conv.userHighId : conv.userLowId
}

const OpenSchema = z.object({ peerUserId: z.string().uuid() })
const SendSchema = z.object({ body: z.string().min(1).max(2000) })

export async function messagesRoutes(app: FastifyInstance) {
  // GET /v1/messages/conversations
  app.get('/conversations', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user

    const rows = await prisma.directConversation.findMany({
      where: {
        OR: [{ userLowId: me }, { userHighId: me }],
      },
      orderBy: { updatedAt: 'desc' },
      include: {
        messages: { orderBy: { createdAt: 'desc' }, take: 1 },
        userLow: { include: { profile: true } },
        userHigh: { include: { profile: true } },
      },
    })

    // Exclude threads whose peer is blocked either-way: blocking severs the DM
    // relationship, so those conversations must not surface in the list.
    const blocked = new Set(await blockedUserIds(me))

    const data = rows
      .filter((c) => !blocked.has(peerIdFromConversation(c, me)))
      .map((c) => {
      const peer = c.userLowId === me ? c.userHigh : c.userLow
      const last = c.messages[0]
      return {
        conversationId: c.id,
        peer: {
          userId: peer.id,
          username: peer.profile?.username ?? null,
          displayName: peer.profile?.displayName ?? null,
        },
        lastMessage: last
          ? {
              body: last.body,
              createdAt: last.createdAt.toISOString(),
              senderId: last.senderId,
            }
          : null,
        updatedAt: c.updatedAt.toISOString(),
      }
    })

    return reply.send({ data })
  })

  // POST /v1/messages/conversations/open — creează sau returnează DM cu prietenul
  app.post('/conversations/open', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const parsed = OpenSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'peerUserId invalid',
        requestId: request.id,
      })
    }
    const { peerUserId } = parsed.data
    if (peerUserId === me) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Nu poți deschide conversație cu tine',
        requestId: request.id,
      })
    }
    if (await isBlockedEitherWay(me, peerUserId)) {
      return reply.code(403).send({
        error: 'BLOCKED',
        message: 'Nu poți mesaja acest utilizator',
        requestId: request.id,
      })
    }
    if (!(await areFriends(me, peerUserId))) {
      return reply.code(403).send({
        error: 'FORBIDDEN',
        message: 'Poți mesaja doar prieteni acceptați',
        requestId: request.id,
      })
    }

    const [low, high] = orderedUserIds(me, peerUserId)
    const conv = await prisma.directConversation.upsert({
      where: {
        userLowId_userHighId: { userLowId: low, userHighId: high },
      },
      create: { userLowId: low, userHighId: high },
      update: {},
      include: {
        userLow: { include: { profile: true } },
        userHigh: { include: { profile: true } },
      },
    })

    const peer = conv.userLowId === me ? conv.userHigh : conv.userLow
    return reply.send({
      conversationId: conv.id,
      peer: {
        userId: peer.id,
        username: peer.profile?.username ?? null,
        displayName: peer.profile?.displayName ?? null,
      },
    })
  })

  // GET /v1/messages/conversations/:id/messages?limit=
  app.get('/conversations/:id/messages', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id } = request.params as { id: string }
    const q = request.query as { limit?: string; before?: string }
    const limit = Math.min(100, Math.max(1, parseInt(q.limit ?? '50', 10) || 50))

    const conv = await prisma.directConversation.findFirst({
      where: {
        id,
        OR: [{ userLowId: me }, { userHighId: me }],
      },
    })
    if (!conv) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Conversație inexistentă',
        requestId: request.id,
      })
    }

    // Re-check the block relationship on read (like the send path): a block in
    // either direction must stop the viewer from reading the thread too.
    const peer = peerIdFromConversation(conv, me)
    if (await isBlockedEitherWay(me, peer)) {
      return reply.code(403).send({
        error: 'BLOCKED',
        message: 'Nu poți mesaja acest utilizator',
        requestId: request.id,
      })
    }

    const where: { conversationId: string; createdAt?: { lt: Date } } = { conversationId: id }
    if (q.before) {
      // `before` is a message id (what the client holds) — resolve it to that
      // message's createdAt. Fall back to parsing it as an ISO date for older
      // clients. Previously a message-UUID `before` was fed to new Date() → NaN
      // → the filter was dropped → the newest page returned every time →
      // "Load earlier" duplicated the same messages forever.
      const anchor = await prisma.directMessage.findFirst({
        where: { id: q.before, conversationId: id },
        select: { createdAt: true },
      })
      if (anchor) {
        where.createdAt = { lt: anchor.createdAt }
      } else {
        const d = new Date(q.before)
        if (!Number.isNaN(d.getTime())) where.createdAt = { lt: d }
      }
    }

    const msgs = await prisma.directMessage.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    })

    const chronological = [...msgs].reverse()
    // nextCursor = the OLDEST message's id in this page, present only when the
    // page was full (so there may be more). The client sends it as `before` to
    // load the previous page; null signals the start of history.
    const nextCursor = msgs.length === limit ? msgs[msgs.length - 1].id : null
    return reply.send({
      data: chronological.map((m) => ({
        id: m.id,
        senderId: m.senderId,
        body: m.body,
        createdAt: m.createdAt.toISOString(),
      })),
      next_cursor: nextCursor,
    })
  })

  // POST /v1/messages/conversations/:id/messages
  app.post('/conversations/:id/messages', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id } = request.params as { id: string }
    const parsed = SendSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Mesaj invalid',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const conv = await prisma.directConversation.findFirst({
      where: {
        id,
        OR: [{ userLowId: me }, { userHighId: me }],
      },
    })
    if (!conv) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Conversație inexistentă',
        requestId: request.id,
      })
    }

    // Re-check the relationship on every send (not just at open): unfriending or
    // blocking must stop further messages on an existing thread.
    const peer = peerIdFromConversation(conv, me)
    if (await isBlockedEitherWay(me, peer)) {
      return reply.code(403).send({
        error: 'BLOCKED',
        message: 'Nu poți mesaja acest utilizator',
        requestId: request.id,
      })
    }
    if (!(await areFriends(me, peer))) {
      return reply.code(403).send({
        error: 'FORBIDDEN',
        message: 'Poți mesaja doar prieteni acceptați',
        requestId: request.id,
      })
    }

    const { body } = parsed.data
    const msg = await prisma.directMessage.create({
      data: {
        conversationId: id,
        senderId: me,
        body,
      },
    })

    await prisma.directConversation.update({
      where: { id },
      data: { updatedAt: new Date() },
    })

    const peerId = peerIdFromConversation(conv, me)
    const preview = body.length > 120 ? `${body.slice(0, 117)}...` : body
    await createNotificationSafe({
      recipientId: peerId,
      actorId: me,
      type: 'dm_message',
      payload: { conversationId: id, bodyPreview: preview },
    })

    return reply.code(201).send({
      message: {
        id: msg.id,
        senderId: msg.senderId,
        body: msg.body,
        createdAt: msg.createdAt.toISOString(),
      },
    })
  })
}
