import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { computeRanks } from '../services/ranking.service'
import { evaluateWeightJump } from '../services/anti-cheat.service'
import { checkAndAward } from '../services/achievement.service'
import { recordWorkoutProgress } from '../services/session-reconcile.service'
import { clearWorkoutSuggestionCache } from '../services/workout-suggestion-cache.service'
import type { ProgressionLevel } from '../lib/progressive-overload'
import {
  createDraftWorkoutFromSuggestion,
  generateWorkoutSuggestionForUser,
} from '../services/workout-generator.service'
import {
  createWorkoutFromPlanned,
  PlannedConvertError,
} from '../services/planned-workout-converter.service'
import { computeWorkoutGameXp, gameXpPayload } from '../services/gym-xp.service'
import { resolveUserXpContext } from '../services/cardio-xp.service'
import {
  enrichWorkoutExerciseRow,
  enrichWorkoutWithExerciseMedia,
  enrichWorkoutsWithExerciseMedia,
} from '../lib/exercise-media'
import { deepSeekChat } from '../services/deepseek.service'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../ai/app-context'
import { sanitizePromptInput } from '../lib/ai-helpers'

// In-process cache for post-workout AI insights. Keyed by `${userId}:${workoutId}`.
// Workouts are immutable after completion, so caching is safe and lets
// repeated XP-screen views (back-button, app reopens) reuse one AI call.
const INSIGHT_CACHE = new Map<string, { text: string; expiresAt: number }>()
const INSIGHT_TTL_MS = 60 * 60 * 1000 // 1 hour

const AddExerciseSchema = z.object({
  exerciseId: z.string().uuid(),
  position: z.number().int().min(0).optional(),
  restSecondsDefault: z.number().int().min(0).max(600).optional(),
})

const AddSetSchema = z.object({
  weightKg: z.number().min(0).max(500),
  reps: z.number().int().min(1).max(50),
  rpe: z.number().min(1).max(10).optional(),
  tag: z.enum(['WORK', 'WARMUP', 'DROP']).default('WORK'),
  isCompleted: z.boolean().optional(),
  /// Idempotency token de la client (UUID): retry-urile cu același clientSetId
  /// returnează setul existent în loc să creeze duplicate.
  clientSetId: z.string().uuid().optional(),
  /// Optional justification note. REQUIRED (anti-cheat) when the weight is a >2x
  /// jump vs the user's recent (<7d) personal max for this exercise.
  note: z.string().max(500).optional(),
})

const UpdateSetSchema = z
  .object({
    weightKg: z.number().min(0).max(500).optional(),
    reps: z.number().int().min(1).max(50).optional(),
    rpe: z.number().min(1).max(10).nullable().optional(),
    isCompleted: z.boolean().optional(),
    /// Optional user-supplied note. REQUIRED when the new weight is a >2x jump
    /// vs the old weight (anti-cheat: forces a written justification before the
    /// suspicious edit is accepted, and populates the audit's `note` column).
    note: z.string().max(500).optional(),
  })
  .refine(
    (d) =>
      d.weightKg !== undefined ||
      d.reps !== undefined ||
      d.rpe !== undefined ||
      d.isCompleted !== undefined,
    { message: 'At least one field required' },
  )

const CompleteSetSchema = z.object({
  setId: z.string().uuid(),
})

export async function workoutRoutes(app: FastifyInstance) {
  const ymdLocal = (d: Date, tzOffsetMin?: number) => {
    if (tzOffsetMin != null) {
      const x = new Date(d.getTime() + tzOffsetMin * 60 * 1000)
      return `${x.getUTCFullYear()}-${String(x.getUTCMonth() + 1).padStart(2, '0')}-${String(x.getUTCDate()).padStart(2, '0')}`
    }
    // Fallback: use UTC (no timezone info provided)
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
  }
  // POST /v1/workouts — creeaza draft
  app.post('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const workout = await prisma.workout.create({
      data: { userId, status: 'draft' },
    })

    await prisma.analyticsEvent.create({
      data: { userId, eventName: 'workout_started' },
    })

    return reply.code(201).send({ workout })
  })

  // POST /v1/workouts/from-suggestion — draft + exercises from AI planner (before /:id routes)
  app.post('/from-suggestion', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    let suggestion: Awaited<ReturnType<typeof generateWorkoutSuggestionForUser>>
    try {
      suggestion = await generateWorkoutSuggestionForUser(userId)
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e)
      if (msg === 'AI_DISABLED') {
        return reply.code(503).send({
          error: 'AI_DISABLED',
          message: 'Set DEEPSEEK_API_KEY on the server for AI workout planning.',
          requestId: request.id,
        })
      }
      request.server.log.warn({ err: msg }, 'from-suggestion AI error')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'Could not generate workout from suggestion',
        requestId: request.id,
      })
    }

    if (suggestion.exercises.length === 0) {
      return reply.code(422).send({
        error: 'NO_EXERCISES',
        message: 'Nu am putut genera exercitii pentru profilul tau. Completeaza onboarding-ul si ruleaza seed-ul exercitiilor.',
        requestId: request.id,
        warnings: suggestion.warnings,
      })
    }

    const created = await createDraftWorkoutFromSuggestion(userId, suggestion)

    const workoutPayload = await enrichWorkoutWithExerciseMedia(created.workout as any)

    return reply.code(201).send({
      workout: workoutPayload,
      meta: created.meta,
    })
  })

  // POST /v1/workouts/from-planned/:plannedWorkoutId
  // Materialize an AI-planned day (with persisted exercisesJson) into a real
  // draft Workout the tracker can run. Closes the loop: cron → plan → session.
  app.post('/from-planned/:plannedWorkoutId', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { plannedWorkoutId } = request.params as { plannedWorkoutId: string }

    try {
      const { workout, meta } = await createWorkoutFromPlanned(userId, plannedWorkoutId)
      const enriched = await enrichWorkoutWithExerciseMedia(workout as any)
      return reply.code(201).send({ workout: enriched, meta })
    } catch (err) {
      if (err instanceof PlannedConvertError) {
        const status = err.code === 'NOT_FOUND' ? 404 : 422
        return reply.code(status).send({
          error: err.code,
          message: err.message,
          requestId: request.id,
        })
      }
      request.server.log.warn({ err: err instanceof Error ? err.message : String(err) }, 'from-planned failed')
      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Could not create workout from planned',
        requestId: request.id,
      })
    }
  })

  // GET /v1/workouts — lista workout-uri ale userului
  app.get('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const query = request.query as { page?: string; limit?: string }

    const page = Math.max(1, parseInt(query.page ?? '1'))
    const limit = Math.min(50, parseInt(query.limit ?? '10'))
    const skip = (page - 1) * limit

    const [workouts, total] = await Promise.all([
      prisma.workout.findMany({
        where: { userId, status: { not: 'draft' } },
        orderBy: { startedAt: 'desc' },
        skip,
        take: limit,
        include: {
          exercises: {
            include: { exercise: true, sets: { orderBy: { setIndex: 'asc' } } },
            orderBy: { position: 'asc' },
          },
        },
      }),
      prisma.workout.count({ where: { userId, status: { not: 'draft' } } }),
    ])

    return reply.send({
      data: await enrichWorkoutsWithExerciseMedia(workouts as any),
      meta: { page, limit, total, totalPages: Math.ceil(total / limit) },
    })
  })

  // GET /v1/workouts/:id
  app.get('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }

    const workout = await prisma.workout.findFirst({
      where: { id, userId },
      include: {
        exercises: {
          include: { exercise: true, sets: { orderBy: { setIndex: 'asc' } } },
          orderBy: { position: 'asc' },
        },
      },
    })

    if (!workout) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Workout negasit',
        requestId: request.id,
      })
    }

    return reply.send({ workout: await enrichWorkoutWithExerciseMedia(workout as any) })
  })

  // POST /v1/workouts/:id/exercises
  app.post('/:id/exercises', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: workoutId } = request.params as { id: string }

    const workout = await prisma.workout.findFirst({ where: { id: workoutId, userId } })
    if (!workout) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Workout negasit',
        requestId: request.id,
      })
    }

    const parsed = AddExerciseSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    // Determina pozitia daca nu e specificata
    let position = parsed.data.position
    if (position === undefined) {
      const lastEx = await prisma.workoutExercise.findFirst({
        where: { workoutId },
        orderBy: { position: 'desc' },
      })
      position = (lastEx?.position ?? -1) + 1
    }

    const workoutExercise = await prisma.workoutExercise.create({
      data: {
        workoutId,
        exerciseId: parsed.data.exerciseId,
        position,
        restSecondsDefault: parsed.data.restSecondsDefault,
      },
      include: { exercise: true },
    })

    return reply.code(201).send({
      workoutExercise: await enrichWorkoutExerciseRow(workoutExercise as any),
    })
  })

  // POST /v1/workouts/:id/exercises/:weId/sets
  app.post('/:id/exercises/:weId/sets', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: workoutId, weId } = request.params as { id: string; weId: string }

    // Verifica ownership
    const we = await prisma.workoutExercise.findFirst({
      where: { id: weId, workoutId, workout: { userId } },
    })
    if (!we) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'WorkoutExercise negasit',
        requestId: request.id,
      })
    }

    const parsed = AddSetSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    // Idempotency: dacă clientSetId există deja pentru acest user, returnează setul fără să creezi unul nou.
    if (parsed.data.clientSetId) {
      const existing = await prisma.workoutSet.findFirst({
        where: {
          clientSetId: parsed.data.clientSetId,
          workoutExercise: { workoutId, workout: { userId } },
        },
      })
      if (existing) return reply.code(200).send({ set: existing, idempotent: true })
    }

    // Anti-cheat (CLAUDE.md "Weight >2× max istoric personal + <7 zile → confirm +
    // notă obligatorie"): a WORK set whose weight is more than 2× the user's
    // recent personal max for THIS exercise (and that max is <7 days old) needs a
    // written justification note. Same pure validator as the edit path so add/edit
    // can't drift. The current workout is excluded so the baseline is the genuine
    // historical max, not a set just logged in this session.
    const note = parsed.data.note?.trim() ? parsed.data.note.trim() : null
    if ((parsed.data.tag ?? 'WORK') !== 'WARMUP' && parsed.data.weightKg > 0) {
      const pmax = await prisma.workoutSet.findFirst({
        where: {
          tag: 'WORK',
          weightKg: { gt: 0 },
          workoutExercise: {
            exerciseId: we.exerciseId,
            workout: { userId, id: { not: workoutId } },
          },
        },
        orderBy: { weightKg: 'desc' },
        select: { weightKg: true, createdAt: true },
      })
      const jump = evaluateWeightJump({
        newWeightKg: parsed.data.weightKg,
        personalMaxKg: pmax ? Number(pmax.weightKg) : null,
        personalMaxAt: pmax?.createdAt ?? null,
        hasNote: !!note,
      })
      if (jump.rejected) {
        return reply.code(422).send({
          error: 'WEIGHT_JUMP_REQUIRES_NOTE',
          message:
            'O greutate de peste 2× recordul tău personal recent necesită o notă explicativă.',
          requestId: request.id,
        })
      }
    }

    // Determina index-ul urmatorului set
    const lastSet = await prisma.workoutSet.findFirst({
      where: { workoutExerciseId: weId },
      orderBy: { setIndex: 'desc' },
    })
    const setIndex = (lastSet?.setIndex ?? -1) + 1

    try {
      const set = await prisma.workoutSet.create({
        data: {
          workoutExerciseId: weId,
          setIndex,
          weightKg: parsed.data.weightKg,
          reps: parsed.data.reps,
          rpe: parsed.data.rpe,
          tag: parsed.data.tag,
          isCompleted: parsed.data.isCompleted ?? true,
          clientSetId: parsed.data.clientSetId,
          note,
        },
      })
      return reply.code(201).send({ set })
    } catch (err: any) {
      // P2002 = unique constraint. Cursă: alt request a creat deja setul între findFirst și create.
      if (err?.code === 'P2002' && parsed.data.clientSetId) {
        const existing = await prisma.workoutSet.findFirst({
          where: {
            clientSetId: parsed.data.clientSetId,
            workoutExercise: { workoutId, workout: { userId } },
          },
        })
        if (existing) return reply.code(200).send({ set: existing, idempotent: true })
      }
      throw err
    }
  })

  // PATCH /v1/workouts/:id/exercises/:weId/sets/:setId
  app.patch('/:id/exercises/:weId/sets/:setId', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: workoutId, weId, setId } = request.params as {
      id: string
      weId: string
      setId: string
    }

    const existing = await prisma.workoutSet.findFirst({
      where: {
        id: setId,
        workoutExerciseId: weId,
        workoutExercise: { workoutId, workout: { userId } },
      },
    })
    if (!existing) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Set negasit',
        requestId: request.id,
      })
    }

    const parsed = UpdateSetSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    // Anti-cheat (CLAUDE.md "Weight >2× ... + nota obligatorie"): a >2x jump vs
    // the OLD weight requires a written note. The pure validator
    // (anti-cheat.service.evaluateWeightJump) is the single source of truth — the
    // prior set weight is the baseline and `personalMaxAt = now` keeps the 7-day
    // recency gate open for an in-place edit. Checked BEFORE mutating the DB so a
    // suspicious edit without justification is rejected outright; every non-jump
    // edit is unaffected.
    const beforeW = Number(existing.weightKg)
    const proposedW = parsed.data.weightKg !== undefined ? parsed.data.weightKg : beforeW
    const note = parsed.data.note?.trim() ? parsed.data.note.trim() : null
    const jump = evaluateWeightJump({
      newWeightKg: proposedW,
      personalMaxKg: beforeW > 0 ? beforeW : null,
      personalMaxAt: new Date(),
      hasNote: !!note,
    })

    if (jump.rejected) {
      return reply.code(422).send({
        error: 'WEIGHT_JUMP_REQUIRES_NOTE',
        message:
          'O creștere de greutate de peste 2× față de setul anterior necesită o notă explicativă.',
        requestId: request.id,
      })
    }

    const data: Record<string, unknown> = {}
    if (parsed.data.weightKg !== undefined) data.weightKg = parsed.data.weightKg
    if (parsed.data.reps !== undefined) data.reps = parsed.data.reps
    if (parsed.data.rpe !== undefined) data.rpe = parsed.data.rpe
    if (parsed.data.isCompleted !== undefined) data.isCompleted = parsed.data.isCompleted

    const set = await prisma.workoutSet.update({
      where: { id: setId },
      data: data as any,
    })

    // Anti-cheat (CLAUDE.md): persist a before/after audit of every set edit,
    // flag a >2x weight jump as a potential anomaly, and store the user's
    // justification note. Best-effort — an audit-write failure must never block
    // the user's edit.
    const afterW = Number(set.weightKg)
    void prisma.setEditAudit
      .create({
        data: {
          setId,
          userId,
          workoutId,
          before: {
            weightKg: beforeW,
            reps: existing.reps,
            rpe: existing.rpe != null ? Number(existing.rpe) : null,
            tag: existing.tag,
            isCompleted: existing.isCompleted,
          },
          after: {
            weightKg: afterW,
            reps: set.reps,
            rpe: set.rpe != null ? Number(set.rpe) : null,
            tag: set.tag,
            isCompleted: set.isCompleted,
          },
          note,
          flagged: jump.requiresConfirmation,
        },
      })
      .catch((err: unknown) =>
        app.log.warn({ err, setId }, 'set edit audit write failed'),
      )

    return reply.send({ set })
  })

  // DELETE /v1/workouts/:id/exercises/:weId/sets/:setId
  app.delete('/:id/exercises/:weId/sets/:setId', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { setId, weId, id: workoutId } = request.params as { id: string; weId: string; setId: string }

    const set = await prisma.workoutSet.findFirst({
      where: {
        id: setId,
        workoutExerciseId: weId,
        workoutExercise: { workoutId, workout: { userId } },
      },
    })

    if (!set) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Set negasit',
        requestId: request.id,
      })
    }

    await prisma.workoutSet.delete({ where: { id: setId } })
    return reply.code(204).send()
  })

  // GET /v1/workouts/:id/insight
  //
  // Post-workout AI coach insight: 2-3 sentences referencing what the user
  // actually did, with prior-session comparison and goal-aware framing.
  // Replaces the generic "Workout saved!" banner with something the user
  // wants to read. Cached in-process for 1h so revisits don't re-call AI.
  app.get('/:id/insight', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: workoutId } = request.params as { id: string }

    const cacheKey = `${userId}:${workoutId}`
    const cached = INSIGHT_CACHE.get(cacheKey)
    if (cached && cached.expiresAt > Date.now()) {
      return reply.send({ insight: cached.text, cached: true })
    }

    if (!process.env.DEEPSEEK_API_KEY) {
      return reply.code(503).send({
        error: 'AI_DISABLED',
        message: 'AI coach is offline',
        requestId: request.id,
      })
    }

    const workout = await prisma.workout.findFirst({
      where: { id: workoutId, userId, status: 'completed' },
      include: {
        exercises: {
          include: {
            exercise: { select: { id: true, name: true, primaryMuscle: true } },
            sets: {
              where: { tag: 'WORK', isCompleted: true },
              orderBy: { setIndex: 'asc' },
            },
          },
          orderBy: { position: 'asc' },
        },
      },
    })

    if (!workout) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Workout not found or not completed yet',
        requestId: request.id,
      })
    }

    // Filter to exercises with at least one logged work set; an insight on an
    // empty workout would be nonsense.
    const exercisesWithSets = workout.exercises.filter((we) => we.sets.length > 0)
    if (exercisesWithSets.length === 0) {
      return reply.send({
        insight: 'Workout logged — but no working sets recorded, so no coach read this session.',
        cached: false,
      })
    }

    // Pull user goal text + a tiny prior comparison per exercise (top work
    // weight from their last completed session for the same exercise).
    const [trainingProfile, priorComparison] = await Promise.all([
      prisma.userTrainingProfile.findUnique({
        where: { userId },
        select: { onboardingGoalText: true, primaryGoal: true },
      }),
      Promise.all(
        exercisesWithSets.map(async (we) => {
          const prior = await prisma.workoutSet.findMany({
            where: {
              workoutExercise: {
                exerciseId: we.exerciseId,
                workout: {
                  userId,
                  status: 'completed',
                  id: { not: workoutId },
                },
              },
              tag: 'WORK',
              isCompleted: true,
              reps: { gte: 1 },
            },
            orderBy: { createdAt: 'desc' },
            take: 10,
            select: { weightKg: true, reps: true },
          })
          if (prior.length === 0) {
            return { name: we.exercise.name, topPriorKg: null, topNowKg: 0, delta: 0 }
          }
          const topPriorKg = Math.max(...prior.map((s) => Number(s.weightKg)))
          const topNowKg = Math.max(...we.sets.map((s) => Number(s.weightKg)))
          return {
            name: we.exercise.name,
            topPriorKg,
            topNowKg,
            delta: Math.round((topNowKg - topPriorKg) * 10) / 10,
          }
        }),
      ),
    ])

    const goalText = trainingProfile?.onboardingGoalText?.trim() ?? ''
    const goalEnum = trainingProfile?.primaryGoal ?? null

    const exerciseSummary = exercisesWithSets
      .map((we) => {
        const sets = we.sets
          .map((s) => {
            const w = Number(s.weightKg)
            const wStr = w > 0 ? `${w}kg` : 'BW'
            const rpe = s.rpe ? ` @ RPE ${Number(s.rpe)}` : ''
            return `${wStr}×${s.reps}${rpe}`
          })
          .join(', ')
        return `- ${we.exercise.name}: ${sets}`
      })
      .join('\n')

    const comparisons = priorComparison.filter((c) => c.topPriorKg != null && c.topPriorKg > 0)
    const comparisonSummary = comparisons.length > 0
      ? comparisons
          .map((c) => {
            const sign = c.delta > 0 ? '+' : ''
            return `- ${c.name}: today's top ${c.topNowKg}kg vs prior top ${c.topPriorKg}kg (${sign}${c.delta}kg)`
          })
          .join('\n')
      : '(no prior recorded sessions for these exercises — first time hitting them)'

    const prompt = `The user just completed a workout. Generate a SHORT 2-3 sentence coach insight (max 60 words total) that the app will show in place of a generic "Workout saved!" banner.

WORKOUT TODAY:
${exerciseSummary}

PRIOR-SESSION COMPARISON (top working weight per exercise):
${comparisonSummary}

USER GOAL: ${goalText ? `"${sanitizePromptInput(goalText)}"` : `(category hint: ${goalEnum ?? 'general fitness'})`}

Rules:
- 2-3 sentences max, ≤60 words total.
- Reference at least ONE specific number from today (weight, reps, or RPE).
- If there's a notable PR, progression, regression, or RPE pattern, call it out concretely.
- Connect to the user's goal naturally — only if it fits, don't force it.
- Coach tone: direct, warm, never motivational filler.
- BANNED phrases (rewrite without these): "great job", "keep it up", "you got this", "amazing work", "way to go", "crushing it", "killed it", "well done", "proud of you".
- English only. No emojis. No markdown.`

    try {
      const out = await deepSeekChat(
        [
          {
            role: 'system',
            content: `${ZVELT_APP_CONTEXT_FOR_AI}

You write post-workout coach commentary. Concrete, specific to the numbers the user just logged. Never generic praise — always reference what actually happened.`,
          },
          { role: 'user', content: prompt },
        ],
        { maxTokens: 200, temperature: 0.5 },
      )
      const insight = out.text.trim().slice(0, 600)
      if (insight.length === 0) {
        throw new Error('Empty insight from model')
      }
      INSIGHT_CACHE.set(cacheKey, { text: insight, expiresAt: Date.now() + INSIGHT_TTL_MS })
      // Best-effort cache eviction so memory doesn't grow unbounded.
      if (INSIGHT_CACHE.size > 500) {
        const now = Date.now()
        for (const [k, v] of INSIGHT_CACHE) {
          if (v.expiresAt < now) INSIGHT_CACHE.delete(k)
        }
      }
      return reply.send({ insight, cached: false })
    } catch (e: any) {
      app.log.warn({ err: String(e?.message ?? e), userId, workoutId }, 'post-workout insight failed')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'Coach is briefly unavailable',
        requestId: request.id,
      })
    }
  })

  // POST /v1/workouts/:id/complete
  app.post('/:id/complete', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: workoutId } = request.params as { id: string }

    const workoutFull = await prisma.workout.findFirst({
      where: { id: workoutId, userId },
      include: {
        exercises: {
          include: { exercise: true, sets: { orderBy: { setIndex: 'asc' } } },
          orderBy: { position: 'asc' },
        },
      },
    })
    if (!workoutFull) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Workout negasit',
        requestId: request.id,
      })
    }

    if (workoutFull.status !== 'draft') {
      return reply.code(400).send({
        error: 'ALREADY_COMPLETED',
        message: 'Workout-ul a fost deja finalizat',
        requestId: request.id,
      })
    }

    const profile = await prisma.userProfile.findUnique({ where: { userId } })
    const bodyweightKg =
      profile?.bodyweightKg != null ? Number(profile.bodyweightKg) : 80
    const exercisesForXp = workoutFull.exercises.map((we) => ({
      name: we.exercise.name,
      rankModel: we.exercise.rankModel,
      fatigueScore: we.exercise.fatigueScore,
      category: we.exercise.category,
      equipment: we.exercise.equipment,
      sets: we.sets.map((s) => ({
        weightKg: Number(s.weightKg),
        reps: s.reps,
        tag: s.tag,
        isCompleted: s.isCompleted,
      })),
    }))
    // Age + sex + bodyweight context so older lifters get the same age bonus
    // cardio already grants. Was: gym XP ignored age entirely.
    const userXpContext = resolveUserXpContext({
      bodyweightKg: profile?.bodyweightKg as unknown as number | null,
      birthYear: profile?.birthYear,
      sex: profile?.sex,
    })
    const { sessionXp, ageMultiplier } = computeWorkoutGameXp(
      exercisesForXp,
      bodyweightKg,
      userXpContext,
    )

    const updated = await prisma.workout.update({
      where: { id: workoutId },
      data: { status: 'completed', endedAt: new Date() },
      include: {
        exercises: {
          include: { exercise: true, sets: { orderBy: { setIndex: 'asc' } } },
          orderBy: { position: 'asc' },
        },
      },
    })

    await prisma.plannedWorkout.updateMany({
      where: {
        userId,
        day: ymdLocal(updated.startedAt),
        kind: 'gym',
        status: 'pending',
      },
      data: { status: 'completed' },
    })

    let gameXp = gameXpPayload(profile?.gameXpTotal ?? 0)
    if (profile) {
      const newTotal = profile.gameXpTotal + sessionXp
      await prisma.userProfile.update({
        where: { userId },
        data: { gameXpTotal: newTotal },
      })
      gameXp = gameXpPayload(newTotal)
    }

    await prisma.analyticsEvent.create({
      data: { userId, eventName: 'workout_completed' },
    })

    // Calculează rangurile la complete (ca la post) — ca Rank tab să se actualizeze
    try {
      await computeRanks(userId, workoutId)
    } catch (err: any) {
      app.log.warn({ err, userId, workoutId }, 'Ranking skip la complete (ex: BW_REQUIRED)')
    }

    let newAchievementKeys: string[] = []
    try {
      newAchievementKeys = await checkAndAward(userId)
    } catch (err: any) {
      app.log.warn({ err, userId }, 'checkAndAward failed after workout complete')
    }

    // Adaptive loop: record per-lift autoregulation state from what was just
    // logged (weight/reps/RPE → progress/hold/deload decision) and bust the
    // stale daily-suggestion cache so the next suggestion reflects this session.
    // Best-effort; never blocks completion.
    try {
      const tp = await prisma.userTrainingProfile.findUnique({
        where: { userId },
        select: { trainingLevel: true },
      })
      const level: ProgressionLevel =
        tp?.trainingLevel === 'advanced'
          ? 'advanced'
          : tp?.trainingLevel === 'beginner'
            ? 'beginner'
            : 'intermediate'
      await recordWorkoutProgress(userId, updated as any, level)
      await clearWorkoutSuggestionCache(userId)
    } catch (err: any) {
      app.log.warn({ err, userId, workoutId }, 'adaptive progress record failed')
    }

    return reply.send({
      workout: await enrichWorkoutWithExerciseMedia(updated as any),
      newAchievements: newAchievementKeys,
      xpGain: sessionXp,
      // Surfaced so the UI can show "×1.22 age bonus" on the XP screen —
      // older lifters see why their XP is higher than a younger user with
      // the same numbers. Defaults to 1.0 if no birthYear on profile.
      ageMultiplier,
      gameXp,
    })
  })
}
