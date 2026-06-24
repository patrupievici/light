import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'

/**
 * Health-consent ledger (GDPR Art. 7 — verifiable, auditable consent).
 * Mounted under /v1/me.
 *
 *   GET  /v1/me/health-consents       → current consent state
 *   POST /v1/me/health-consents       → record/update one or more consent decisions
 *
 * Per-data-type so the user can grant sleep but deny vitals, etc.
 */

// Known per-type categories (aligns with HealthService _types). "all" = blanket.
const CONSENT_TYPES = [
  'all',
  'steps',
  'heart_rate',
  'sleep',
  'weight',
  'hrv',
  'blood_oxygen',
  'active_energy',
  'distance',
  'workout',
] as const

const ConsentEntrySchema = z.object({
  consentType: z.enum(CONSENT_TYPES),
  granted: z.boolean(),
  source: z.enum(['healthkit', 'health_connect', 'manual']).optional(),
  consentVersion: z.string().max(16).optional(),
})

const RecordConsentSchema = z.object({
  consents: z.array(ConsentEntrySchema).min(1).max(CONSENT_TYPES.length),
})

export async function healthConsentRoutes(app: FastifyInstance) {
  // GET /v1/me/health-consents
  app.get('/me/health-consents', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const rows = await prisma.healthConsent.findMany({
      where: { userId },
      orderBy: { grantedAt: 'desc' },
    })
    return reply.send({
      data: rows.map((r) => ({
        consentType: r.consentType,
        granted: r.granted,
        consentVersion: r.consentVersion,
        source: r.source,
        grantedAt: r.grantedAt.toISOString(),
        revokedAt: r.revokedAt ? r.revokedAt.toISOString() : null,
      })),
    })
  })

  // POST /v1/me/health-consents — upsert one or more per-type decisions.
  app.post('/me/health-consents', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = RecordConsentSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const now = new Date()
    // Two writes per decision in ONE transaction:
    //   1. upsert the CURRENT state in `health_consents` (unchanged behavior), and
    //   2. append an IMMUTABLE event to `health_consent_events` — an append-only
    //      ledger giving a verifiable Art.7 grant/revoke history (the current
    //      state row is mutated in place; this ledger never is).
    await prisma.$transaction(
      parsed.data.consents.flatMap((c) => [
        prisma.healthConsent.upsert({
          where: { userId_consentType: { userId, consentType: c.consentType } },
          create: {
            userId,
            consentType: c.consentType,
            granted: c.granted,
            consentVersion: c.consentVersion ?? '1',
            source: c.source ?? null,
            grantedAt: now,
            revokedAt: c.granted ? null : now,
          },
          update: {
            granted: c.granted,
            consentVersion: c.consentVersion ?? '1',
            source: c.source ?? undefined,
            grantedAt: c.granted ? now : undefined,
            revokedAt: c.granted ? null : now,
          },
        }),
        prisma.healthConsentEvent.create({
          data: {
            userId,
            consentType: c.consentType,
            granted: c.granted,
            consentVersion: c.consentVersion ?? '1',
            source: c.source ?? null,
            createdAt: now,
          },
        }),
      ]),
    )

    return reply.code(201).send({ ok: true })
  })
}
