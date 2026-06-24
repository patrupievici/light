import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { generateAndPersistWeeklyPlan, WeeklyPlanError } from '../services/weekly-plan.service'

const GenerateWeeklySchema = z.object({
  tzOffset: z.number().int().min(-840).max(840).optional().default(0),
  force: z.boolean().optional().default(false),
})

const UpdateStatusSchema = z.object({
  status: z.enum(['pending', 'completed']),
})

function ymdFromUtcWithOffset(d: Date, offsetMin: number): string {
  const x = new Date(d.getTime() + offsetMin * 60 * 1000)
  const y = x.getUTCFullYear()
  const m = String(x.getUTCMonth() + 1).padStart(2, '0')
  const day = String(x.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function dateFromYmdUtc(ymd: string): Date {
  const [y, m, d] = ymd.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d, 0, 0, 0, 0))
}

function mondayOfWeek(ymd: string): string {
  const d = dateFromYmdUtc(ymd)
  const wd = d.getUTCDay() // 0 sun ... 6 sat
  const shift = wd === 0 ? 6 : wd - 1
  d.setUTCDate(d.getUTCDate() - shift)
  return ymdFromUtcWithOffset(d, 0)
}

export async function plannedWorkoutsRoutes(app: FastifyInstance) {
  // POST /v1/me/planned-workouts/generate-weekly
  app.post('/planned-workouts/generate-weekly', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = GenerateWeeklySchema.safeParse(request.body ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
      })
    }

    const { tzOffset, force } = parsed.data
    const todayYmd = ymdFromUtcWithOffset(new Date(), tzOffset)
    const weekStart = mondayOfWeek(todayYmd)

    const existing = await prisma.plannedWorkout.findMany({
      where: { userId, weekStart },
      orderBy: [{ day: 'asc' }, { createdAt: 'asc' }],
    })
    if (existing.length > 0 && !force) {
      return reply.send({ weekStart, generated: false, workouts: existing })
    }

    // Unified with the rich adaptive generator (the same path the Monday cron
    // uses): populates exercisesJson with progressive, RPE-autoregulated loads
    // instead of title-only sessions, so the autoregulation engine actually
    // reaches the app's weekly plan. applyDailyTargets:false so this button
    // never silently overwrites manually-set nutrition macro targets.
    try {
      await generateAndPersistWeeklyPlan(userId, { weekStart, applyDailyTargets: false })
    } catch (e: unknown) {
      const code = e instanceof WeeklyPlanError ? e.code : null
      if (code === 'AI_DISABLED') {
        return reply.code(503).send({
          error: 'AI_DISABLED',
          message: 'Set DEEPSEEK_API_KEY in server environment to generate weekly plans.',
          requestId: request.id,
        })
      }
      if (code === 'PROFILE_INCOMPLETE') {
        return reply.code(400).send({
          error: 'PROFILE_INCOMPLETE',
          message: 'Complete your training profile before generating a plan.',
          requestId: request.id,
        })
      }
      const msg = e instanceof Error ? e.message : String(e)
      app.log.warn({ err: msg }, 'planned-week rich generation failed')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'Could not generate weekly plan',
        requestId: request.id,
      })
    }

    // generateAndPersistWeeklyPlan already deletes the week's pending rows and
    // writes fresh ones — return them in the exact shape the app consumes today.
    const created = await prisma.plannedWorkout.findMany({
      where: { userId, weekStart },
      orderBy: [{ day: 'asc' }, { createdAt: 'asc' }],
    })

    await prisma.analyticsEvent.create({
      data: {
        userId,
        eventName: 'planned_week_generated',
        props: { weekStart, days: created.length, blueprintId: 'ai_adaptive' },
      },
    })

    return reply.send({ weekStart, generated: true, workouts: created })
  })

  // PATCH /v1/me/planned-workouts/:id
  app.patch('/planned-workouts/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const parsed = UpdateStatusSchema.safeParse(request.body ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
      })
    }
    const row = await prisma.plannedWorkout.findFirst({ where: { id, userId } })
    if (!row) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Planned workout negasit',
        requestId: request.id,
      })
    }
    const updated = await prisma.plannedWorkout.update({
      where: { id },
      data: { status: parsed.data.status },
    })
    return reply.send({ plannedWorkout: updated })
  })

  // DELETE /v1/me/planned-workouts/:id
  app.delete('/planned-workouts/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const row = await prisma.plannedWorkout.findFirst({ where: { id, userId } })
    if (!row) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Planned workout negasit',
        requestId: request.id,
      })
    }
    await prisma.plannedWorkout.delete({ where: { id } })
    return reply.code(204).send()
  })
}
