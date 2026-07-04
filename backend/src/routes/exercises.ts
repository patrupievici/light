import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { isAdminTokenValid } from '../lib/admin-auth'
import { MOVEMENT_PATTERNS, type MovementPattern } from '../constants/movement-patterns'
import { buildMediaByExerciseId, enrichExerciseWithMedia } from '../lib/exercise-media'
import { rankSubstitutes } from '../lib/exercise-substitution'
import { exerciseFitsUserEquipment } from '../programming/equipment-compatibility'
import { normalizeEquipmentTagsForAi } from '../lib/equipment-for-ai'
import { computeProgressiveLoads, type ProgressionLevel } from '../lib/progressive-overload'
import { fetchLastWorkingWeights } from '../services/workout-generator.service'
import {
  localizeExercise,
  inheritClassification,
  normalizeLocale,
  type ExerciseTranslationRow,
} from '../lib/exercise-translation'

const MovementPatternSchema = z.string().refine(
  (v): v is MovementPattern => (MOVEMENT_PATTERNS as readonly string[]).includes(v),
  { message: 'Invalid movement pattern' },
)

const CreateCustomSchema = z.object({
  name: z.string().min(1).max(100),
  primaryMuscle: z.string().max(50).optional(),
  equipment: z.string().max(50).optional(),
  movementPattern: MovementPatternSchema.optional(),
  // Optional classification (inherited from parent when omitted).
  rankModel: z.enum(['WEIGHTED', 'BW_REPS', 'TIME']).optional(),
  category: z.string().max(32).optional(),
  // Variation grouping: link this custom exercise to a canonical parent.
  parentExerciseId: z.string().uuid().optional(),
  goalTags: z.array(z.string().max(32)).max(12).optional(),
})

// Defaults match the Prisma schema column defaults for Exercise.
const CLASSIFICATION_DEFAULTS = {
  movementPattern: 'skill_stability',
  rankModel: 'WEIGHTED',
  category: 'strength',
}

const UpsertTranslationSchema = z.object({
  locale: z.string().min(2).max(8),
  name: z.string().min(1).max(100),
  description: z.string().max(2000).optional(),
})

// ─── ExerciseDB (RapidAPI) proxy — key stays server-side ─────────────────────
type ExdbCacheEntry = { data: unknown; expiresAt: number }
const EXDB_CACHE = new Map<string, ExdbCacheEntry>()
const EXDB_TTL_MS = 24 * 60 * 60 * 1000
const EXDB_HOST = 'exercisedb.p.rapidapi.com'
const EXDB_BASE = `https://${EXDB_HOST}`

type ImageCacheEntry = { buffer: Buffer; contentType: string; expiresAt: number }
const EXDB_IMAGE_CACHE = new Map<string, ImageCacheEntry>()
const EXDB_IMAGE_TTL_MS = 7 * 24 * 60 * 60 * 1000

async function exdbFetch(path: string): Promise<unknown> {
  const key = process.env.EXERCISEDB_KEY?.trim()
  if (!key) {
    const err: any = new Error('EXERCISEDB_KEY not configured')
    err.statusCode = 503
    err.code = 'EXDB_NOT_CONFIGURED'
    throw err
  }

  const cached = EXDB_CACHE.get(path)
  if (cached && cached.expiresAt > Date.now()) return cached.data

  const res = await fetch(`${EXDB_BASE}${path}`, {
    headers: {
      'X-RapidAPI-Key': key,
      'X-RapidAPI-Host': EXDB_HOST,
    },
  })
  if (!res.ok) {
    const err: any = new Error(`ExerciseDB upstream error ${res.status}`)
    err.statusCode = res.status >= 500 ? 502 : res.status
    err.code = 'EXDB_UPSTREAM_ERROR'
    throw err
  }
  const data = await res.json()
  EXDB_CACHE.set(path, { data, expiresAt: Date.now() + EXDB_TTL_MS })
  return data
}

/**
 * Load translation rows for a set of exercises restricted to the requested
 * locale + its base language (so "ro-RO" still fetches "ro" rows). Returns a
 * map keyed by exerciseId; missing keys = no translations.
 */
async function loadTranslationsByExerciseId(
  exerciseIds: string[],
  normalizedLocale: string,
): Promise<Map<string, ExerciseTranslationRow[]>> {
  const out = new Map<string, ExerciseTranslationRow[]>()
  if (exerciseIds.length === 0 || !normalizedLocale) return out

  const base = normalizedLocale.split('-')[0]
  const locales = Array.from(new Set([normalizedLocale, base]))

  const rows = await prisma.exerciseTranslation.findMany({
    where: { exerciseId: { in: exerciseIds }, locale: { in: locales } },
    select: { exerciseId: true, locale: true, name: true, description: true },
  })

  for (const r of rows) {
    const list = out.get(r.exerciseId) ?? []
    list.push({ locale: r.locale, name: r.name, description: r.description })
    out.set(r.exerciseId, list)
  }
  return out
}

/**
 * IDOR scoping predicate: an exercise is usable by `userId` when it's a public
 * catalog row (isCustom=false) OR the user's own custom one. Shared across the
 * exercise detail/substitutes/custom-parent lookups, the workout add-exercise
 * validator, and the routine→workout converter so the scope can't drift.
 */
export function accessibleExerciseWhere(userId: string) {
  return { OR: [{ isCustom: false }, { createdByUserId: userId }] }
}

export async function exerciseRoutes(app: FastifyInstance) {
  // GET /v1/exercises/last-weights?ids=a,b,c — most recent completed WORK-set
  // weight per exercise for the signed-in user. Lets the client pre-fill preset
  // sets from the user's real history instead of generic hardcoded numbers.
  app.get('/last-weights', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const raw = (request.query as { ids?: string })?.ids ?? ''
    const ids = raw.split(',').map((s) => s.trim()).filter(Boolean).slice(0, 60)
    if (ids.length === 0) return reply.send({ data: {} })

    // Most-recent completed WORK-set weight per exercise — same query the workout
    // generator uses for warm starts. First (most recent) weight wins per exercise.
    const data = Object.fromEntries(await fetchLastWorkingWeights(userId, ids))
    return reply.send({ data })
  })

  // GET /v1/exercises/:id/progression?reps=8 — the brief's §8.3 auto-progression.
  // Suggests the NEXT working load for ONE exercise from the user's completed
  // WORK-set history, so the live tracker can pre-fill instead of the user
  // guessing. Thin wrapper over the existing (tested) computeProgressiveLoads
  // engine: linear +bump on success, hold on a missed prescription, RPE deload.
  app.get('/:id/progression', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const repsRaw = Number((request.query as { reps?: string })?.reps)
    const prescribedReps = Number.isFinite(repsRaw) && repsRaw >= 1 && repsRaw <= 50 ? Math.round(repsRaw) : 8

    // Training level + chosen scheme drive the bump size and strategy. Default to
    // 'beginner' (the brief's headline +2.5kg) when the profile/level is unset.
    const profile = await prisma.userTrainingProfile.findUnique({
      where: { userId },
      select: { trainingLevel: true, progressionScheme: true },
    })
    const level: ProgressionLevel =
      profile?.trainingLevel === 'intermediate' || profile?.trainingLevel === 'advanced'
        ? profile.trainingLevel
        : 'beginner'

    const [decision] = await computeProgressiveLoads(
      userId,
      [{ exerciseId: id, prescribedReps }],
      level,
      { progressionScheme: profile?.progressionScheme },
    )
    return reply.send({ data: decision })
  })

  // GET /v1/exercises?query=&muscle=&equipment=&ranked=
  app.get('/', { preHandler: authenticate }, async (request, reply) => {
    const query = request.query as {
      query?: string
      muscle?: string
      equipment?: string
      pattern?: string
      ranked?: string
      locale?: string
      page?: string
      limit?: string
    }

    const page = Math.max(1, parseInt(query.page ?? '1'))
    // Cap raised from 50 -> 500 so the exercise picker can load the full
    // catalog in one page (it filters/groups client-side). Default stays small
    // for incidental callers that don't pass a limit.
    const limit = Math.min(500, parseInt(query.limit ?? '50'))
    const skip = (page - 1) * limit

    const where: any = {}

    if (query.query) {
      where.name = { contains: query.query, mode: 'insensitive' }
    }
    if (query.muscle) {
      where.primaryMuscle = { contains: query.muscle, mode: 'insensitive' }
    }
    if (query.equipment) {
      where.equipment = { contains: query.equipment, mode: 'insensitive' }
    }
    if (query.ranked !== undefined) {
      where.isRanked = query.ranked === 'true'
    }
    if (query.pattern) {
      where.movementPattern = query.pattern
    }

    const [exercises, total] = await Promise.all([
      prisma.exercise.findMany({
        where,
        skip,
        take: limit,
        orderBy: { name: 'asc' },
      }),
      prisma.exercise.count({ where }),
    ])

    const mediaById = await buildMediaByExerciseId(exercises)

    // Localization is opt-in via ?locale=. Without it (or with a locale that has
    // no translations) the response is byte-for-byte unchanged.
    const locale = normalizeLocale(query.locale)
    const translationsById = locale
      ? await loadTranslationsByExerciseId(exercises.map((e) => e.id), locale)
      : new Map<string, ExerciseTranslationRow[]>()

    const data = exercises.map((ex) => {
      const base = { ...ex, media: mediaById.get(ex.id) ?? [] }
      if (!locale) return base
      const { name, resolvedLocale } = localizeExercise(
        ex,
        translationsById.get(ex.id) ?? [],
        locale,
      )
      return { ...base, name, localizedLocale: resolvedLocale || null }
    })

    return reply.send({
      data,
      meta: { page, limit, total, totalPages: Math.ceil(total / limit) },
    })
  })

  // POST /v1/exercises/custom
  app.post('/custom', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const parsed = CreateCustomSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const { movementPattern, rankModel, category, parentExerciseId, goalTags, ...rest } =
      parsed.data

    // Variation grouping: a custom exercise may hang off a canonical parent and
    // inherit its classification. The parent must be a real, non-custom catalog
    // row (or one the user owns) to prevent linking to arbitrary IDs.
    let parent: { movementPattern: string; rankModel: string; category: string } | null = null
    if (parentExerciseId) {
      parent = await prisma.exercise.findFirst({
        where: {
          id: parentExerciseId,
          ...accessibleExerciseWhere(userId),
        },
        select: { movementPattern: true, rankModel: true, category: true },
      })
      if (!parent) {
        return reply.code(400).send({
          error: 'INVALID_PARENT',
          message: 'parentExerciseId does not reference an accessible exercise',
          requestId: request.id,
        })
      }
    }

    const classification = inheritClassification(
      { movementPattern, rankModel, category },
      parent,
      CLASSIFICATION_DEFAULTS,
    )

    const exercise = await prisma.exercise.create({
      data: {
        ...rest,
        movementPattern: classification.movementPattern,
        rankModel: classification.rankModel,
        category: classification.category,
        parentExerciseId: parentExerciseId ?? null,
        goalTags: goalTags ?? [],
        isCustom: true,
        isRanked: false,
        createdByUserId: userId,
      },
    })

    return reply.code(201).send({ exercise: await enrichExerciseWithMedia(exercise) })
  })

  // ─── ExerciseDB proxy — register before /:id ───────────────────────────────

  app.get('/db', { preHandler: authenticate }, async (request, reply) => {
    const q = request.query as { offset?: string; limit?: string }
    const offset = Math.max(0, parseInt(q.offset ?? '0'))
    const limit = Math.min(200, Math.max(1, parseInt(q.limit ?? '50')))
    const data = await exdbFetch(`/exercises?offset=${offset}&limit=${limit}`)
    return reply.send({ data })
  })

  app.get('/db/bodyparts', { preHandler: authenticate }, async (_req, reply) => {
    const data = await exdbFetch('/exercises/bodyPartList')
    return reply.send({ data })
  })

  app.get('/db/equipment', { preHandler: authenticate }, async (_req, reply) => {
    const data = await exdbFetch('/exercises/equipmentList')
    return reply.send({ data })
  })

  app.get('/db/targets', { preHandler: authenticate }, async (_req, reply) => {
    const data = await exdbFetch('/exercises/targetList')
    return reply.send({ data })
  })

  app.get('/db/bodypart/:name', { preHandler: authenticate }, async (request, reply) => {
    const { name } = request.params as { name: string }
    const data = await exdbFetch(`/exercises/bodyPart/${encodeURIComponent(name)}`)
    return reply.send({ data })
  })

  app.get('/db/target/:name', { preHandler: authenticate }, async (request, reply) => {
    const { name } = request.params as { name: string }
    const data = await exdbFetch(`/exercises/target/${encodeURIComponent(name)}`)
    return reply.send({ data })
  })

  app.get('/db/equipment/:name', { preHandler: authenticate }, async (request, reply) => {
    const { name } = request.params as { name: string }
    const data = await exdbFetch(`/exercises/equipment/${encodeURIComponent(name)}`)
    return reply.send({ data })
  })

  app.get('/db/name/:name', { preHandler: authenticate }, async (request, reply) => {
    const { name } = request.params as { name: string }
    const data = await exdbFetch(`/exercises/name/${encodeURIComponent(name)}`)
    return reply.send({ data })
  })

  /** Public image proxy — clients use Image.network without Bearer; same pattern as beastpack/zvetutzu. */
  app.get('/db/image/:id', async (request, reply) => {
    const { id } = request.params as { id: string }
    const q = request.query as { resolution?: string }
    const allowed = new Set(['180', '360', '720', '1080'])
    const resolution = allowed.has(q.resolution ?? '') ? q.resolution! : '180'
    const cacheKey = `${id}_${resolution}`

    const cached = EXDB_IMAGE_CACHE.get(cacheKey)
    if (cached && cached.expiresAt > Date.now()) {
      reply.header('Content-Type', cached.contentType)
      reply.header('Cache-Control', 'public, max-age=604800, immutable')
      return reply.send(cached.buffer)
    }

    const key = process.env.EXERCISEDB_KEY?.trim()
    if (!key) {
      return reply.code(503).send({ error: 'EXDB_NOT_CONFIGURED', message: 'EXERCISEDB_KEY not set' })
    }

    const url = `${EXDB_BASE}/image?exerciseId=${encodeURIComponent(id)}&resolution=${resolution}`
    const res = await fetch(url, {
      headers: { 'X-RapidAPI-Key': key, 'X-RapidAPI-Host': EXDB_HOST },
    })
    if (!res.ok) {
      return reply
        .code(res.status === 404 ? 404 : 502)
        .send({ error: 'EXDB_IMAGE_ERROR', message: `Upstream ${res.status}` })
    }

    const contentType = res.headers.get('content-type') ?? 'image/gif'
    const arrayBuffer = await res.arrayBuffer()
    const buffer = Buffer.from(arrayBuffer)

    EXDB_IMAGE_CACHE.set(cacheKey, { buffer, contentType, expiresAt: Date.now() + EXDB_IMAGE_TTL_MS })
    reply.header('Content-Type', contentType)
    reply.header('Cache-Control', 'public, max-age=604800, immutable')
    return reply.send(buffer)
  })

  app.get('/db/:id', { preHandler: authenticate }, async (request, reply) => {
    const { id } = request.params as { id: string }
    const data = await exdbFetch(`/exercises/exercise/${encodeURIComponent(id)}`)
    return reply.send({ data })
  })

  // GET /v1/exercises/:id — detail + GIF when external media DB is configured.
  // Exposes provenance/sourceLicense/reviewStatus + parentExerciseId (already
  // part of the spread Exercise row) and an optional ?locale= localized name.
  app.get('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const q = request.query as { locale?: string }

    const exercise = await prisma.exercise.findFirst({
      where: {
        id,
        ...accessibleExerciseWhere(userId),
      },
    })

    if (!exercise) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Exercise not found',
        requestId: request.id,
      })
    }

    const enriched = await enrichExerciseWithMedia(exercise)

    // Localization is opt-in; without ?locale= the payload is unchanged.
    const locale = normalizeLocale(q.locale)
    if (locale) {
      const translationsById = await loadTranslationsByExerciseId([exercise.id], locale)
      const { name, description, resolvedLocale } = localizeExercise(
        // Exercise has no canonical description column; pass undefined so the
        // localized description (if any) still surfaces.
        { name: exercise.name, description: null },
        translationsById.get(exercise.id) ?? [],
        locale,
      )
      enriched.name = name
      enriched.localizedDescription = description
      enriched.localizedLocale = resolvedLocale || null
    }

    return reply.send({ exercise: enriched })
  })

  // PUT /v1/exercises/:id/translations — admin-ish upsert of a localized
  // name/description. Auth-required; restricted to canonical (non-custom)
  // catalog exercises so users can't shadow others' custom rows.
  app.put('/:id/translations', { preHandler: authenticate }, async (request, reply) => {
    // Shared catalog data — any authenticated user editing it would rewrite the
    // localized name/description for EVERYONE. Gate on the admin token (there is
    // no per-user admin role), same mechanism the /admin routes use.
    if (!isAdminTokenValid(request.headers['x-admin-token'])) {
      return reply.code(403).send({
        error: 'FORBIDDEN',
        message: 'Admin token required to edit catalog translations.',
        requestId: request.id,
      })
    }

    const { id } = request.params as { id: string }

    const parsed = UpsertTranslationSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const exercise = await prisma.exercise.findFirst({
      where: { id, isCustom: false },
      select: { id: true },
    })
    if (!exercise) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Exercise not found',
        requestId: request.id,
      })
    }

    const locale = normalizeLocale(parsed.data.locale)
    const translation = await prisma.exerciseTranslation.upsert({
      where: { exerciseId_locale: { exerciseId: id, locale } },
      create: {
        exerciseId: id,
        locale,
        name: parsed.data.name,
        description: parsed.data.description ?? null,
      },
      update: {
        name: parsed.data.name,
        description: parsed.data.description ?? null,
      },
    })

    return reply.code(200).send({ translation })
  })

  // GET /v1/exercises/:id/substitutes — ranked "swap this lift" alternatives.
  // Read-only: returns same-pattern alternatives scored by movement pattern +
  // primary-muscle overlap + equipment availability + rankModel compat + fatigue
  // proximity, each with a "why this alternative" reason (Explainability #3).
  app.get('/:id/substitutes', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const q = request.query as { limit?: string }
    const limit = Math.min(20, Math.max(1, parseInt(q.limit ?? '8')))

    const source = await prisma.exercise.findFirst({
      where: {
        id,
        ...accessibleExerciseWhere(userId),
      },
    })

    if (!source) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Exercise not found',
        requestId: request.id,
      })
    }

    // Candidate pool: built-in catalog plus the user's own custom exercises.
    // Cap matches the listing endpoint so a single page covers the catalog.
    const [candidates, trainingProfile] = await Promise.all([
      prisma.exercise.findMany({
        where: accessibleExerciseWhere(userId),
        take: 500,
      }),
      prisma.userTrainingProfile.findUnique({
        where: { userId },
        select: { equipment: true },
      }),
    ])

    const rawTags = Array.isArray(trainingProfile?.equipment)
      ? (trainingProfile!.equipment as unknown[]).filter((x): x is string => typeof x === 'string')
      : []
    const userEquipment = normalizeEquipmentTagsForAi(rawTags)

    const ranked = rankSubstitutes(source, candidates, {
      isEquipmentAvailable: (equipment) => exerciseFitsUserEquipment(equipment, userEquipment),
      limit,
    })

    const mediaById = await buildMediaByExerciseId(ranked.map((r) => r.exercise))
    const data = ranked.map((r) => ({
      ...r.exercise,
      media: mediaById.get(r.exercise.id) ?? [],
      substitution: {
        score: r.score,
        equipmentAvailable: r.equipmentAvailable,
        reason: r.reason,
      },
    }))

    return reply.send({
      source: { id: source.id, name: source.name, movementPattern: source.movementPattern },
      data,
      meta: { total: data.length, limit },
    })
  })
}
