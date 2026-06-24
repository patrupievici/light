import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { sendGoalAwarePushForUser } from '../services/goal-aware-push.service'

const RegisterSchema = z.object({
  token: z.string().min(20).max(512),
  platform: z.enum(['android', 'ios', 'web']),
})

export async function pushRoutes(app: FastifyInstance) {
  // POST /v1/me/push-token — înregistrează / actualizează token FCM
  app.post('/push-token', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = RegisterSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'token (20–512 chars) și platform android|ios|web',
        requestId: request.id,
      })
    }
    const { token, platform } = parsed.data

    await prisma.userPushToken.upsert({
      where: { token },
      create: { userId, token, platform },
      update: { userId, platform, updatedAt: new Date() },
    })

    return reply.send({ ok: true })
  })

  // POST /v1/me/test-push
  //
  // QA / demo endpoint: immediately generates + sends the goal-aware push
  // for the calling user, bypassing the hourly schedule. Useful for testing
  // on a real device without waiting for the cron, and for the "see how
  // your daily nudge will look" preview button in settings.
  //
  // Pass ?force=true to override the per-day dedupe.
  app.post(
    '/test-push',
    { preHandler: authenticate, config: { rateLimit: { max: 8, timeWindow: '5 minutes' } } },
    async (request, reply) => {
      const { userId } = request.user
      const q = request.query as { force?: string }
      const force = q.force === 'true' || q.force === '1'

      const result = await sendGoalAwarePushForUser(userId, { force, log: request.log })
      const status = result.ok ? 200 : 422
      return reply.code(status).send(result)
    },
  )

  // DELETE /v1/me/push-token?token=... — logout sau dezactivare push
  app.delete('/push-token', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { token?: string }
    const token = q.token?.trim()
    if (!token) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Query token obligatoriu',
        requestId: request.id,
      })
    }

    await prisma.userPushToken.deleteMany({
      where: { userId, token },
    })

    return reply.send({ ok: true })
  })
}
