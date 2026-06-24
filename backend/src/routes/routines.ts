import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'

/** One exercise slot in a routine — mirrors PlannedWorkout.exercisesJson so a
 * routine can be built from an AI plan and started via the same draft-workout
 * shape. `exerciseId` resolves the catalog row; name is the human label. */
const RoutineExerciseSchema = z.object({
  name: z.string().min(1).max(120),
  exerciseId: z.string().min(1).max(64).nullable().optional(),
  sets: z.number().int().min(1).max(10).optional(),
  reps: z.number().int().min(1).max(50).optional(),
  restSeconds: z.number().int().min(0).max(900).optional(),
  notes: z.string().max(500).nullable().optional(),
})

const CreateRoutineSchema = z.object({
  name: z.string().min(1).max(80),
  focus: z.string().max(140).nullable().optional(),
  exercises: z.array(RoutineExerciseSchema).min(1).max(40),
})

const UpdateRoutineSchema = z.object({
  name: z.string().min(1).max(80).optional(),
  focus: z.string().max(140).nullable().optional(),
  exercises: z.array(RoutineExerciseSchema).min(1).max(40).optional(),
})

type RoutineExercise = z.infer<typeof RoutineExerciseSchema>

function clampInt(v: unknown, lo: number, hi: number, fallback: number): number {
  const n = typeof v === 'number' ? Math.round(v) : NaN
  if (!Number.isFinite(n)) return fallback
  return Math.max(lo, Math.min(hi, n))
}

/** Shape a stored routine for the client: derive an exercise count + pass the
 * exercise list through. */
function serializeRoutine(r: {
  id: string
  name: string
  focus: string | null
  exercisesJson: unknown
  createdAt: Date
  updatedAt: Date
}) {
  const exercises = Array.isArray(r.exercisesJson) ? (r.exercisesJson as RoutineExercise[]) : []
  return {
    id: r.id,
    name: r.name,
    focus: r.focus,
    exerciseCount: exercises.length,
    exercises,
    createdAt: r.createdAt.toISOString(),
    updatedAt: r.updatedAt.toISOString(),
  }
}

export async function routineRoutes(app: FastifyInstance) {
  // GET /v1/routines — the signed-in user's saved routines (mockup 4).
  app.get('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const routines = await prisma.routine.findMany({
      where: { userId },
      orderBy: [{ position: 'asc' }, { createdAt: 'desc' }],
    })
    return reply.send({ data: routines.map(serializeRoutine) })
  })

  // POST /v1/routines — save a new routine (from the builder or a logged workout).
  app.post('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CreateRoutineSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide pentru rutină',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const { name, focus, exercises } = parsed.data
    const count = await prisma.routine.count({ where: { userId } })
    const routine = await prisma.routine.create({
      data: {
        userId,
        name: name.trim(),
        focus: focus?.trim() || null,
        exercisesJson: exercises,
        position: count,
      },
    })
    return reply.code(201).send({ routine: serializeRoutine(routine) })
  })

  // GET /v1/routines/:id
  app.get('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const routine = await prisma.routine.findFirst({ where: { id, userId } })
    if (!routine) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Rutină negăsită', requestId: request.id })
    }
    return reply.send({ routine: serializeRoutine(routine) })
  })

  // PATCH /v1/routines/:id
  app.patch('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const parsed = UpdateRoutineSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide pentru rutină',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const existing = await prisma.routine.findFirst({ where: { id, userId } })
    if (!existing) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Rutină negăsită', requestId: request.id })
    }
    const { name, focus, exercises } = parsed.data
    const routine = await prisma.routine.update({
      where: { id },
      data: {
        ...(name !== undefined ? { name: name.trim() } : {}),
        ...(focus !== undefined ? { focus: focus?.trim() || null } : {}),
        ...(exercises !== undefined ? { exercisesJson: exercises } : {}),
      },
    })
    return reply.send({ routine: serializeRoutine(routine) })
  })

  // DELETE /v1/routines/:id
  app.delete('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const existing = await prisma.routine.findFirst({ where: { id, userId } })
    if (!existing) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Rutină negăsită', requestId: request.id })
    }
    await prisma.routine.delete({ where: { id } })
    return reply.code(204).send()
  })

  // POST /v1/routines/:id/start — build a fresh draft Workout (+ pre-filled
  // exercises/sets) from the routine, ready for the live tracker. Mirrors
  // createWorkoutFromPlanned: only catalog-resolved exercises are materialized.
  app.post('/:id/start', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const routine = await prisma.routine.findFirst({ where: { id, userId } })
    if (!routine) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Rutină negăsită', requestId: request.id })
    }
    const raw = Array.isArray(routine.exercisesJson) ? (routine.exercisesJson as RoutineExercise[]) : []
    const withId = raw.filter((e) => typeof e?.exerciseId === 'string' && e.exerciseId!.length > 0)
    // Validate the ids against the catalog scoped to this user (public OR their
    // own custom) — exercisesJson is arbitrary user JSON, so an unvalidated id
    // would hit the WorkoutExercise FK and 500 (or materialize a foreign custom
    // exercise). Keep only ids that resolve. Mirrors exercises.ts scoping.
    const validIds = new Set(
      (
        await prisma.exercise.findMany({
          where: {
            id: { in: withId.map((e) => e.exerciseId!) },
            OR: [{ isCustom: false }, { createdByUserId: userId }],
          },
          select: { id: true },
        })
      ).map((e) => e.id),
    )
    const resolved = withId.filter((e) => validIds.has(e.exerciseId!))
    if (resolved.length === 0) {
      return reply.code(400).send({
        error: 'NO_EXERCISES',
        message: 'Rutina nu are exerciții din catalog de pornit',
        requestId: request.id,
      })
    }

    const workoutId = await prisma.$transaction(async (tx) => {
      const w = await tx.workout.create({
        data: { userId, status: 'draft', notes: `From routine: ${routine.name}` },
      })
      for (let i = 0; i < resolved.length; i++) {
        const ex = resolved[i]
        const we = await tx.workoutExercise.create({
          data: {
            workoutId: w.id,
            exerciseId: ex.exerciseId!,
            position: i,
            restSecondsDefault: clampInt(ex.restSeconds, 30, 600, 90),
            repRangeHint: ex.reps ? String(ex.reps) : null,
          },
        })
        const setCount = clampInt(ex.sets, 1, 10, 3)
        const reps = clampInt(ex.reps, 1, 50, 8)
        for (let si = 0; si < setCount; si++) {
          await tx.workoutSet.create({
            data: {
              workoutExerciseId: we.id,
              setIndex: si,
              weightKg: 0,
              reps,
              tag: 'WORK',
              isCompleted: false,
            },
          })
        }
      }
      return w.id
    })

    await prisma.analyticsEvent.create({
      data: { userId, eventName: 'routine_started' },
    })
    return reply.code(201).send({ workout: { id: workoutId } })
  })
}
