import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'

/// User-level block + report (Apple §1.2 / Play UGC). Registered at prefix `/v1`
/// so this serves `/v1/users/:id/block`, `/v1/me/blocked`, `/v1/users/:id/report`.
/// Blocks are enforced across feed/comments/DMs/stories via [blockedUserIds].

const ReportSchema = z.object({
  category: z.enum(['spam', 'harassment', 'nudity', 'hate', 'violence', 'other']),
  note: z.string().max(500).optional(),
})

export async function moderationRoutes(app: FastifyInstance) {
  // POST /v1/users/:id/block — block a user (idempotent). Also severs any
  // friendship both directions so a blocked user isn't still a "friend".
  app.post('/users/:id/block', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: target } = request.params as { id: string }
    if (target === me) {
      return reply.code(400).send({
        error: 'CANNOT_BLOCK_SELF',
        message: 'You cannot block yourself',
        requestId: request.id,
      })
    }
    const exists = await prisma.user.findUnique({ where: { id: target }, select: { id: true } })
    if (!exists) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'User not found', requestId: request.id })
    }
    await prisma.$transaction([
      prisma.userBlock.upsert({
        where: { blockerId_blockedId: { blockerId: me, blockedId: target } },
        create: { blockerId: me, blockedId: target },
        update: {},
      }),
      // Remove any friendship in either direction (block supersedes friendship).
      prisma.friendship.deleteMany({
        where: {
          OR: [
            { userId: me, friendUserId: target },
            { userId: target, friendUserId: me },
          ],
        },
      }),
    ])
    return reply.send({ blocked: true })
  })

  // DELETE /v1/users/:id/block — unblock.
  app.delete('/users/:id/block', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: target } = request.params as { id: string }
    await prisma.userBlock.deleteMany({ where: { blockerId: me, blockedId: target } })
    return reply.send({ blocked: false })
  })

  // GET /v1/me/blocked — the caller's block list (users THEY blocked).
  app.get('/me/blocked', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const rows = await prisma.userBlock.findMany({
      where: { blockerId: me },
      orderBy: { createdAt: 'desc' },
      include: { blocked: { select: { id: true, profile: { select: { displayName: true, username: true } } } } },
    })
    return reply.send({
      data: rows.map((r) => ({
        userId: r.blockedId,
        displayName: r.blocked.profile?.displayName ?? r.blocked.profile?.username ?? 'Blocked user',
        username: r.blocked.profile?.username ?? null,
        blockedAt: r.createdAt.toISOString(),
      })),
    })
  })

  // POST /v1/users/:id/report — file an abuse report for moderator review.
  app.post('/users/:id/report', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: target } = request.params as { id: string }
    if (target === me) {
      return reply.code(400).send({
        error: 'CANNOT_REPORT_SELF',
        message: 'You cannot report yourself',
        requestId: request.id,
      })
    }
    const parsed = ReportSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Invalid report category or note',
        requestId: request.id,
      })
    }
    const exists = await prisma.user.findUnique({ where: { id: target }, select: { id: true } })
    if (!exists) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'User not found', requestId: request.id })
    }
    await prisma.userReport.create({
      data: {
        reporterId: me,
        reportedId: target,
        category: parsed.data.category,
        note: parsed.data.note ?? null,
      },
    })
    return reply.code(201).send({ reported: true })
  })
}
