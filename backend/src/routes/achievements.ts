import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { checkAndAward } from '../services/achievement.service'

const CheckAchievementsSchema = z.object({
  stepsToday: z.coerce.number().int().min(0).max(200_000).optional(),
})

export async function achievementsRoutes(app: FastifyInstance) {
  // GET /v1/achievements/me — toate achievement-urile + care sunt deblocate
  app.get('/me', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const [all, earned] = await Promise.all([
      prisma.achievement.findMany({
        orderBy: [{ tier: 'asc' }, { xpReward: 'asc' }],
      }),
      prisma.userAchievement.findMany({
        where: { userId },
        include: { achievement: true },
        orderBy: { achievedAt: 'desc' },
      }),
    ])

    const earnedIds = new Set(earned.map((e) => e.achievementId))

    return reply.send({
      achievements: all.map((a) => ({
        id: a.id,
        key: a.key,
        title: a.title,
        description: a.description,
        tier: a.tier,
        xpReward: a.xpReward,
        iconName: a.iconName,
        earned: earnedIds.has(a.id),
        earnedAt: earned.find((e) => e.achievementId === a.id)?.achievedAt ?? null,
      })),
      totalEarned: earned.length,
      totalXp: earned.reduce((sum, e) => sum + e.achievement.xpReward, 0),
    })
  })

  /** POST /v1/achievements/check — re-evaluează regulile (ex. după sync pași din Health). Body opțional: { stepsToday?: number } */
  app.post('/check', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const body = CheckAchievementsSchema.parse(request.body ?? {})
    const opts =
      body.stepsToday !== undefined ? { stepsToday: body.stepsToday } : undefined
    const newAchievements = await checkAndAward(userId, opts)
    return reply.send({ newAchievements })
  })
}
