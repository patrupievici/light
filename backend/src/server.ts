import './bootstrap-env'
import path from 'node:path'
import fs from 'node:fs/promises'
import Fastify from 'fastify'
import cors from '@fastify/cors'
import jwt from '@fastify/jwt'
import rateLimit from '@fastify/rate-limit'
import fastifyStatic from '@fastify/static'
import rawBody from 'fastify-raw-body'
import { authRoutes } from './routes/auth'
import { profileRoutes } from './routes/profile'
import { exerciseRoutes } from './routes/exercises'
import { workoutRoutes } from './routes/workouts'
import { routineRoutes } from './routes/routines'
import { postRoutes } from './routes/posts'
import { challengeRoutes } from './routes/challenges'
import { rankRoutes } from './routes/ranks'
import { achievementsRoutes } from './routes/achievements'
import { statsRoutes } from './routes/stats'
import { trainingProfileRoutes } from './routes/training-profile'
import { workoutSuggestionRoutes } from './routes/workout-suggestion'
import { weeklyCoachReadRoutes } from './routes/weekly-coach-read'
import { friendRoutes } from './routes/friends'
import { notificationRoutes } from './routes/notifications'
import { messagesRoutes } from './routes/messages'
import { activitiesRoutes } from './routes/activities'
import { weatherRoutes } from './routes/weather'
import { aiRoutes } from './routes/ai'
import { pushRoutes } from './routes/push'
import { nutritionRoutes } from './routes/nutrition'
import { plannedWorkoutsRoutes } from './routes/planned-workouts'
import { bodyMeasurementRoutes } from './routes/body-measurements'
import { gdprRoutes } from './routes/gdpr'
import { healthConsentRoutes } from './routes/health-consent'
import { buildCorsOrigin } from './lib/cors'
import { storyRoutes } from './routes/stories'
import { segmentRoutes } from './routes/segments'
import { integrationsRoutes } from './routes/integrations'
import { startGlobalDailyQuoteCron } from './services/global-daily-quote'
import { startWeeklyPlanRegenCron } from './services/weekly-plan-cron.service'
import { startGoalAwarePushCron } from './services/goal-aware-push.service'
import { startStoriesCleanupCron } from './services/stories-cleanup.service'
import { startWebhookReconcileCron } from './services/webhook-reconcile-cron.service'
import { startSoftDeleteCron } from './services/soft-delete-cron.service'
import { adminRoutes } from './routes/admin'

const app = Fastify({
  logger: {
    level: process.env.NODE_ENV === 'production' ? 'warn' : 'info',
  },
  genReqId: () => crypto.randomUUID(),
  /** Implicit 1 MiB — prea mic pentru POST /v1/posts cu photoBase64 (~2.4M chars la 1.8MB binar). */
  bodyLimit: 6 * 1024 * 1024,
})

/**
 * Rezolva secretul JWT din mediu, esuand rapid la boot daca lipseste sau e prea
 * scurt. Nu acceptam un default hardcodat: un secret public ar permite oricui sa
 * semneze token-uri valide. Minim 32 chars pentru entropie rezonabila (HS256).
 */
function resolveJwtSecret(): string {
  const secret = process.env.JWT_SECRET
  if (!secret || secret.trim().length === 0) {
    throw new Error(
      'JWT_SECRET is not set. Refusing to start: set JWT_SECRET to a strong random value (>=32 chars).',
    )
  }
  if (secret.length < 32) {
    throw new Error(
      `JWT_SECRET is too short (${secret.length} chars). Refusing to start: use at least 32 chars.`,
    )
  }
  return secret
}

async function main() {
  // ─── Plugins ──────────────────────────────────────────────────────────────

  const jwtSecret = resolveJwtSecret()

  await app.register(cors, {
    // Allowlist from CORS_ORIGINS (comma-separated). Native mobile / no-Origin
    // requests always pass; in production an empty allowlist rejects browser
    // cross-origin instead of the old blanket `false`.
    origin: buildCorsOrigin(process.env.CORS_ORIGINS, process.env.NODE_ENV),
  })

  await app.register(jwt, {
    secret: jwtSecret,
  })

  await app.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
  })

  await app.register(rawBody, {
    field: 'rawBody',
    global: false,
    encoding: 'utf8',
    runFirst: true,
  })

  const uploadRoot = path.join(process.cwd(), 'uploads')
  await fs.mkdir(path.join(uploadRoot, 'posts'), { recursive: true })
  await fs.mkdir(path.join(uploadRoot, 'avatars'), { recursive: true })
  await fs.mkdir(path.join(uploadRoot, 'stories'), { recursive: true })
  await app.register(fastifyStatic, {
    root: uploadRoot,
    prefix: '/uploads/',
    decorateReply: false,
  })

  // ─── Health check ─────────────────────────────────────────────────────────

  app.get('/health', async () => ({ status: 'ok', timestamp: new Date().toISOString() }))

  // ─── Routes ───────────────────────────────────────────────────────────────

  app.register(authRoutes, { prefix: '/v1/auth' })
  app.register(profileRoutes, { prefix: '/v1' })
  app.register(exerciseRoutes, { prefix: '/v1/exercises' })
  app.register(workoutRoutes, { prefix: '/v1/workouts' })
  app.register(routineRoutes, { prefix: '/v1/routines' })
  app.register(postRoutes, { prefix: '/v1/posts' })
  app.register(challengeRoutes, { prefix: '/v1/challenges' })
  app.register(friendRoutes, { prefix: '/v1/friends' })
  app.register(notificationRoutes, { prefix: '/v1/notifications' })
  app.register(messagesRoutes, { prefix: '/v1/messages' })
  app.register(rankRoutes, { prefix: '/v1/ranks' })
  app.register(achievementsRoutes, { prefix: '/v1/achievements' })
  app.register(statsRoutes, { prefix: '/v1/me' })
  app.register(trainingProfileRoutes, { prefix: '/v1/me' })
  app.register(workoutSuggestionRoutes, { prefix: '/v1/me' })
  app.register(weeklyCoachReadRoutes, { prefix: '/v1/me' })
  app.register(plannedWorkoutsRoutes, { prefix: '/v1/me' })
  app.register(bodyMeasurementRoutes, { prefix: '/v1/me' })
  app.register(pushRoutes, { prefix: '/v1/me' })
  app.register(activitiesRoutes, { prefix: '/v1/activities' })
  app.register(weatherRoutes, { prefix: '/v1/weather' })
  app.register(aiRoutes, { prefix: '/v1/ai' })
  app.register(nutritionRoutes, { prefix: '/v1/nutrition' })
  app.register(integrationsRoutes, { prefix: '/v1/integrations' })
  app.register(adminRoutes, { prefix: '/v1/admin' })
  // storyRoutes is Razvan's expanded version (post-merge canonical name)
  app.register(storyRoutes, { prefix: '/v1/stories' })
  app.register(segmentRoutes, { prefix: '/v1' })
  app.register(gdprRoutes, { prefix: '/v1' })
  app.register(healthConsentRoutes, { prefix: '/v1' })

  startGlobalDailyQuoteCron(app.log)
  startWeeklyPlanRegenCron(app.log)
  startGoalAwarePushCron(app.log)
  startStoriesCleanupCron(app.log)
  startWebhookReconcileCron(app.log)
  startSoftDeleteCron(app.log)

  // ─── Error handler global ─────────────────────────────────────────────────

  app.setErrorHandler((error, request, reply) => {
    app.log.error(error)
    reply.code(error.statusCode ?? 500).send({
      error: error.code ?? 'INTERNAL_ERROR',
      message:
        process.env.NODE_ENV === 'production' ? 'Eroare interna' : error.message,
      requestId: request.id,
    })
  })

  // ─── Start ────────────────────────────────────────────────────────────────

  const port = parseInt(process.env.PORT ?? '3000')
  await app.listen({ port, host: '0.0.0.0' })
  console.log(`Zvelt backend running on http://localhost:${port}`)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
