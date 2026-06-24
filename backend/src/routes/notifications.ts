import { FastifyInstance } from 'fastify'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { getUserDisplayHints } from '../lib/user-display'

export async function notificationRoutes(app: FastifyInstance) {
  // POST /v1/notifications/read-all — înainte de /:id/read
  app.post('/read-all', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    await prisma.notification.updateMany({
      where: { userId: me, readAt: null },
      data: { readAt: new Date() },
    })
    return reply.send({ ok: true })
  })

  // GET /v1/notifications/unread-count
  app.get('/unread-count', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const count = await prisma.notification.count({
      where: { userId: me, readAt: null },
    })
    return reply.send({ count })
  })

  // GET /v1/notifications?page=&limit=
  app.get('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const q = request.query as { page?: string; limit?: string }
    const page = Math.max(1, parseInt(q.page ?? '1'))
    const limit = Math.min(50, parseInt(q.limit ?? '30'))
    const skip = (page - 1) * limit

    const rows = await prisma.notification.findMany({
      where: { userId: me },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    })

    const actors = await getUserDisplayHints(rows.map((r) => r.actorId).filter((x): x is string => !!x))

    const data = rows.map((r) => {
      const a = r.actorId ? actors.get(r.actorId) : undefined
      return {
        id: r.id,
        type: r.type,
        actorId: r.actorId,
        actorUsername: a?.username ?? null,
        actorDisplayName: a?.displayName ?? null,
        actorEmailHint: a?.emailHint ?? null,
        payload: r.payload,
        readAt: r.readAt?.toISOString() ?? null,
        createdAt: r.createdAt.toISOString(),
      }
    })

    return reply.send({ data, meta: { page, limit } })
  })

  // POST /v1/notifications/:id/read
  app.post('/:id/read', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id } = request.params as { id: string }

    const res = await prisma.notification.updateMany({
      where: { id, userId: me },
      data: { readAt: new Date() },
    })

    if (res.count === 0) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Notificare inexistentă',
        requestId: request.id,
      })
    }

    return reply.send({ ok: true })
  })
}
