import type { FastifyInstance } from 'fastify'
import { authenticate } from '../middleware/auth'
import { generateWorkoutSuggestionForUser } from '../services/workout-generator.service'

export async function workoutSuggestionRoutes(app: FastifyInstance) {
  // GET /v1/me/workout-suggestion
  app.get('/workout-suggestion', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { refresh?: string }
    const refresh = q.refresh === 'true' || q.refresh === '1'
    try {
      const suggestion = await generateWorkoutSuggestionForUser(userId, { refresh })
      return reply.send({ suggestion, cached: !refresh })
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e)
      if (msg === 'AI_DISABLED') {
        return reply.code(503).send({
          error: 'AI_DISABLED',
          message: 'Set DEEPSEEK_API_KEY on the server for AI workout planning.',
          requestId: request.id,
        })
      }
      app.log.warn({ err: msg }, 'workout-suggestion AI error')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'Could not generate workout suggestion',
        requestId: request.id,
      })
    }
  })
}
