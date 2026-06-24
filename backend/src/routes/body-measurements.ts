import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { Prisma } from '@prisma/client'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'

/**
 * Body measurements — server-side persistence for the app's Body tab
 * (was device-only SharedPreferences). Mounted under /v1/me:
 *
 *   GET    /v1/me/measurements          → list (optional ?type=, paginated)
 *   POST   /v1/me/measurements          → create/upsert one measurement
 *   DELETE /v1/me/measurements/:id      → delete one (own rows only)
 *
 * Privacy-by-default: every query is scoped to `request.user.userId`; a row
 * is never readable or deletable across users. Canonical metric storage is
 * the client's job (weight in kg, lengths in cm); the server validates the
 * value range + the controlled type/unit vocabulary but stores whatever
 * canonical pair the client sends so kg/lb display stays a client concern.
 */

/** Controlled vocabulary — kept in one place so the route + tests agree. */
export const MEASUREMENT_TYPES = [
  'weight',
  'body_fat',
  'chest',
  'waist',
  'hips',
  'arm',
  'thigh',
  'calf',
  'shoulders',
  'neck',
] as const

export const MEASUREMENT_UNITS = ['kg', 'lb', 'cm', 'in', 'pct'] as const

export const CreateMeasurementSchema = z.object({
  type: z.enum(MEASUREMENT_TYPES),
  valueNum: z.coerce.number().min(0).max(1000),
  unit: z.enum(MEASUREMENT_UNITS),
  // Client sends an ISO instant; default to "now" when omitted.
  measuredAt: z.coerce.date().optional(),
  source: z.string().trim().min(1).max(24).optional(),
})

const ListQuerySchema = z.object({
  type: z.enum(MEASUREMENT_TYPES).optional(),
  limit: z.coerce.number().int().min(1).max(200).optional().default(100),
  // Cursor = the `id` of the last row from the previous page (keyset paging).
  cursor: z.string().uuid().optional(),
})

/**
 * Pure serializer — Prisma `Decimal` arrives as a Decimal instance; the app's
 * JSON readers (and a known release-only crash) choke on `as num` casts, so we
 * always emit a plain JS number here. Dates go out as ISO strings.
 */
export function serializeMeasurement(row: {
  id: string
  type: string
  valueNum: Prisma.Decimal | number | string
  unit: string
  measuredAt: Date
  source: string | null
  createdAt: Date
  updatedAt: Date
}) {
  return {
    id: row.id,
    type: row.type,
    valueNum: Number(row.valueNum),
    unit: row.unit,
    measuredAt: row.measuredAt.toISOString(),
    source: row.source,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  }
}

export async function bodyMeasurementRoutes(app: FastifyInstance) {
  // GET /v1/me/measurements?type=&limit=&cursor=
  app.get('/measurements', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = ListQuerySchema.safeParse(request.query ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Query: type?, limit? (1-200), cursor? (uuid)',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const { type, limit, cursor } = parsed.data

    // Keyset pagination over (measuredAt desc, id desc). Fetch one extra row to
    // know whether another page exists without a second COUNT query.
    const rows = await prisma.userBodyMeasurement.findMany({
      where: { userId, ...(type ? { type } : {}) },
      orderBy: [{ measuredAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    })

    const hasMore = rows.length > limit
    const page = hasMore ? rows.slice(0, limit) : rows
    return reply.send({
      data: page.map(serializeMeasurement),
      nextCursor: hasMore ? page[page.length - 1]?.id ?? null : null,
    })
  })

  // POST /v1/me/measurements — create / upsert a measurement.
  //
  // Upsert key is (userId, type, measuredAt): re-logging the same metric at the
  // same instant overwrites the value rather than stacking duplicates. There is
  // no DB unique on that triple, so we resolve an existing row in a transaction
  // and update it; otherwise create. This mirrors the app's per-day upsert and
  // makes offline replay idempotent (a re-pushed write won't duplicate).
  app.post('/measurements', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CreateMeasurementSchema.safeParse(request.body ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body: type, valueNum (0-1000), unit, measuredAt?, source?',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const { type, valueNum, unit } = parsed.data
    const measuredAt = parsed.data.measuredAt ?? new Date()
    const source = parsed.data.source ?? null

    const row = await prisma.$transaction(async (tx) => {
      const existing = await tx.userBodyMeasurement.findFirst({
        where: { userId, type, measuredAt },
        select: { id: true },
      })
      if (existing) {
        return tx.userBodyMeasurement.update({
          where: { id: existing.id },
          data: { valueNum, unit, source },
        })
      }
      return tx.userBodyMeasurement.create({
        data: { userId, type, valueNum, unit, measuredAt, source },
      })
    })

    return reply.code(201).send(serializeMeasurement(row))
  })

  // DELETE /v1/me/measurements/:id — remove one own row.
  app.delete<{ Params: { id: string } }>(
    '/measurements/:id',
    { preHandler: authenticate },
    async (request, reply) => {
      const { userId } = request.user
      const idParsed = z.string().uuid().safeParse(request.params.id)
      if (!idParsed.success) {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'Invalid id',
          requestId: request.id,
        })
      }
      // Scope the delete to the owner: a row belonging to someone else (or a
      // missing id) deletes nothing, so we 404 rather than leak existence.
      const result = await prisma.userBodyMeasurement.deleteMany({
        where: { id: idParsed.data, userId },
      })
      if (result.count === 0) {
        return reply.code(404).send({
          error: 'NOT_FOUND',
          message: 'No such measurement',
          requestId: request.id,
        })
      }
      return reply.code(204).send()
    },
  )
}
