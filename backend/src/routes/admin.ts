import type { FastifyInstance } from 'fastify'

import { runWeeklyPlanRegenForActiveUsers } from '../services/weekly-plan-cron.service'

/**
 * Admin-only routes — protected by a static `ADMIN_TOKEN` env var.
 *
 * The token is checked against the `X-Admin-Token` header. This is intentionally
 * the simplest possible protection because admin routes should only be reachable
 * from local/dev or a trusted ops box (NOT exposed on the public LB) — but the
 * token gate prevents accidents if it leaks past a misconfigured proxy.
 *
 * Set `ADMIN_TOKEN` in `backend/.env` to enable these routes. Without the env
 * var set, every request returns 503 (so missing config doesn't accidentally
 * expose the endpoints with an empty-string token).
 */

function isAuthorized(headerValue: unknown): boolean {
  const configured = process.env.ADMIN_TOKEN
  if (!configured || configured.length < 8) return false
  return typeof headerValue === 'string' && headerValue === configured
}

export async function adminRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', async (request, reply) => {
    if (!process.env.ADMIN_TOKEN || process.env.ADMIN_TOKEN.length < 8) {
      return reply.code(503).send({
        error: 'ADMIN_DISABLED',
        message: 'Set ADMIN_TOKEN (8+ chars) in backend env to enable admin routes.',
        requestId: request.id,
      })
    }
    if (!isAuthorized(request.headers['x-admin-token'])) {
      return reply.code(401).send({
        error: 'UNAUTHORIZED',
        message: 'Missing or invalid X-Admin-Token header.',
        requestId: request.id,
      })
    }
  })

  // POST /v1/admin/cron/weekly-plan/run
  // Manually fire the weekly plan regeneration without waiting for Monday 03:00 UTC.
  // Returns the same summary the cron logs: { scanned, generated, skipped, failed }.
  app.post('/cron/weekly-plan/run', async (request, reply) => {
    try {
      const summary = await runWeeklyPlanRegenForActiveUsers(app.log)
      return reply.send({ ok: true, summary })
    } catch (err: any) {
      app.log.error({ err: String(err?.message ?? err) }, 'admin: weekly-plan cron run failed')
      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: err?.message ?? 'Cron run failed',
        requestId: request.id,
      })
    }
  })
}
