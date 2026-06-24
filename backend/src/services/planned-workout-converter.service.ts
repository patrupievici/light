import { prisma } from '../lib/prisma'

/**
 * Convert a PlannedWorkout (calendar slot with `exercisesJson` from AI) into
 * a real draft Workout + WorkoutExercise rows + empty WorkoutSet rows.
 *
 * This is what turns the AI plan from "pretty calendar entry" into "session
 * the tracker can actually run". Without it, the cron's output is dead weight.
 *
 * Rules:
 *  - Only AI exercises with a resolved `exerciseId` become WorkoutExercise rows.
 *    Names the resolver couldn't match are skipped (they wouldn't have an FK
 *    target). Surfaced in `meta.unresolved` so UI can show "AI suggested X but
 *    we don't have it in the catalog".
 *  - Each exercise gets `prescribedSets` empty WorkoutSet rows (isCompleted=false)
 *    pre-seeded with the AI's suggested weight (when present) and reps so the
 *    tracker opens with everything ready.
 *  - Marks the planned workout as `in_progress` so the calendar shows it active.
 */

export type ConvertResult = {
  workout: unknown
  meta: {
    plannedWorkoutId: string
    resolved: number
    unresolved: string[]
  }
}

export class PlannedConvertError extends Error {
  constructor(public code: 'NOT_FOUND' | 'NO_EXERCISES' | 'ALREADY_CONVERTED', message: string) {
    super(message)
  }
}

export async function createWorkoutFromPlanned(
  userId: string,
  plannedWorkoutId: string,
): Promise<ConvertResult> {
  const planned = await prisma.plannedWorkout.findFirst({
    where: { id: plannedWorkoutId, userId },
  })
  if (!planned) throw new PlannedConvertError('NOT_FOUND', 'Planned workout not found')

  const rawExercises = Array.isArray(planned.exercisesJson) ? planned.exercisesJson : []
  if (rawExercises.length === 0) {
    throw new PlannedConvertError('NO_EXERCISES', 'Planned workout has no exercises (likely a rest day)')
  }

  type PlannedEx = {
    name?: string
    sets?: number
    reps?: number
    restSeconds?: number
    exerciseId?: string | null
    suggestedWeightKg?: number | null
    notes?: string
  }
  const exercises = rawExercises
    .filter((e): e is PlannedEx => !!e && typeof e === 'object')
    .map((e) => e as PlannedEx)

  const resolvedExercises = exercises.filter((e) => typeof e.exerciseId === 'string' && e.exerciseId.length > 0)
  const unresolvedNames = exercises
    .filter((e) => !e.exerciseId)
    .map((e) => e.name ?? 'Unknown')

  if (resolvedExercises.length === 0) {
    throw new PlannedConvertError('NO_EXERCISES', 'None of the AI exercise names resolved to catalog rows')
  }

  const workoutId = await prisma.$transaction(async (tx) => {
    const w = await tx.workout.create({
      data: {
        userId,
        status: 'draft',
        notes: `From plan: ${planned.title}`,
      },
    })

    for (let i = 0; i < resolvedExercises.length; i++) {
      const ex = resolvedExercises[i]
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
      const weight = typeof ex.suggestedWeightKg === 'number' && ex.suggestedWeightKg >= 0
        ? ex.suggestedWeightKg
        : 0

      for (let si = 0; si < setCount; si++) {
        await tx.workoutSet.create({
          data: {
            workoutExerciseId: we.id,
            setIndex: si,
            weightKg: weight,
            reps,
            tag: 'WORK',
            isCompleted: false,
          },
        })
      }
    }

    // Mark the planned slot as in-progress so the calendar/home reflect state.
    await tx.plannedWorkout.update({
      where: { id: plannedWorkoutId },
      data: { status: 'in_progress' },
    })

    return w.id
  })

  const full = await prisma.workout.findFirst({
    where: { id: workoutId, userId },
    include: {
      exercises: {
        include: { exercise: true, sets: { orderBy: { setIndex: 'asc' } } },
        orderBy: { position: 'asc' },
      },
    },
  })

  await prisma.analyticsEvent.create({
    data: {
      userId,
      eventName: 'workout_from_planned',
      props: {
        plannedWorkoutId,
        resolved: resolvedExercises.length,
        unresolvedCount: unresolvedNames.length,
      },
    },
  })

  return {
    workout: full,
    meta: {
      plannedWorkoutId,
      resolved: resolvedExercises.length,
      unresolved: unresolvedNames,
    },
  }
}

function clampInt(v: unknown, min: number, max: number, fallback: number): number {
  const n = typeof v === 'number' ? v : Number(v)
  if (!Number.isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.round(n)))
}
