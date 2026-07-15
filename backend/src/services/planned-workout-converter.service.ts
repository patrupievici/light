import { randomUUID } from 'node:crypto'
import type { PlannedWorkout } from '@prisma/client'
import { prisma } from '../lib/prisma'

/**
 * Convert a PlannedWorkout into a tracker-ready draft workout.
 * Rows are prebuilt and inserted in batches so large program days do not cause
 * one database round trip per exercise and set.
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

type SeedDetail = { weightKg?: number | null; reps?: number }

export type PlannedExercise = {
  name?: string
  sets?: number
  reps?: number
  restSeconds?: number
  exerciseId?: string | null
  suggestedWeightKg?: number | null
  notes?: string
  setsDetail?: SeedDetail[]
  warmups?: SeedDetail[]
}

export type PlannedSeedSet = {
  weightKg: number
  reps: number
  tag: 'WORK' | 'WARMUP'
}

/** Pure expansion used by both uniform and percentage-based program slots. */
export function buildPlannedSeedSets(exercise: PlannedExercise): PlannedSeedSet[] {
  const cleanWeight = (weight: unknown): number =>
    typeof weight === 'number' && Number.isFinite(weight) && weight >= 0 ? weight : 0
  const seedSets: PlannedSeedSet[] = []

  if (Array.isArray(exercise.warmups)) {
    for (const warmup of exercise.warmups) {
      seedSets.push({
        weightKg: cleanWeight(warmup?.weightKg),
        reps: clampInt(warmup?.reps, 1, 50, 5),
        tag: 'WARMUP',
      })
    }
  }

  if (Array.isArray(exercise.setsDetail) && exercise.setsDetail.length > 0) {
    for (const detail of exercise.setsDetail) {
      seedSets.push({
        weightKg: cleanWeight(detail?.weightKg),
        reps: clampInt(detail?.reps, 1, 50, 8),
        tag: 'WORK',
      })
    }
  } else {
    const setCount = clampInt(exercise.sets, 1, 12, 3)
    const reps = clampInt(exercise.reps, 1, 50, 8)
    const weightKg = cleanWeight(exercise.suggestedWeightKg)
    for (let index = 0; index < setCount; index++) {
      seedSets.push({ weightKg, reps, tag: 'WORK' })
    }
  }

  return seedSets
}

export async function createWorkoutFromPlanned(
  userId: string,
  plannedWorkoutId: string,
  plannedInput?: PlannedWorkout,
): Promise<ConvertResult> {
  const planned =
    plannedInput?.id === plannedWorkoutId && plannedInput.userId === userId
      ? plannedInput
      : await prisma.plannedWorkout.findFirst({
          where: { id: plannedWorkoutId, userId },
        })
  if (!planned) throw new PlannedConvertError('NOT_FOUND', 'Planned workout not found')

  const rawExercises = Array.isArray(planned.exercisesJson) ? planned.exercisesJson : []
  if (rawExercises.length === 0) {
    throw new PlannedConvertError('NO_EXERCISES', 'Planned workout has no exercises (likely a rest day)')
  }

  const exercises = rawExercises
    .filter((exercise): exercise is PlannedExercise => !!exercise && typeof exercise === 'object')
    .map((exercise) => exercise as PlannedExercise)
  const resolvedExercises = exercises.filter(
    (exercise) => typeof exercise.exerciseId === 'string' && exercise.exerciseId.length > 0,
  )
  const unresolvedNames = exercises
    .filter((exercise) => !exercise.exerciseId)
    .map((exercise) => exercise.name ?? 'Unknown')

  if (resolvedExercises.length === 0) {
    throw new PlannedConvertError('NO_EXERCISES', 'None of the AI exercise names resolved to catalog rows')
  }

  const workoutId = randomUUID()
  const exerciseRows = resolvedExercises.map((exercise, position) => ({
    id: randomUUID(),
    workoutId,
    exerciseId: exercise.exerciseId!,
    position,
    restSecondsDefault: clampInt(exercise.restSeconds, 30, 600, 90),
    repRangeHint: exercise.reps ? String(exercise.reps) : null,
    exercise,
  }))
  const setRows = exerciseRows.flatMap(({ id: workoutExerciseId, exercise }) =>
    buildPlannedSeedSets(exercise).map((set, setIndex) => ({
      id: randomUUID(),
      workoutExerciseId,
      setIndex,
      weightKg: set.weightKg,
      reps: set.reps,
      tag: set.tag,
      isCompleted: false,
    })),
  )

  await prisma.$transaction([
    prisma.workout.create({
      data: {
        id: workoutId,
        userId,
        status: 'draft',
        notes: `From plan: ${planned.title}`,
      },
    }),
    prisma.workoutExercise.createMany({
      data: exerciseRows.map(({ exercise: _exercise, ...row }) => row),
    }),
    prisma.workoutSet.createMany({ data: setRows }),
    prisma.plannedWorkout.update({
      where: { id: plannedWorkoutId },
      data: { status: 'in_progress' },
    }),
  ])

  const [full] = await Promise.all([
    prisma.workout.findFirst({
      where: { id: workoutId, userId },
      include: {
        exercises: {
          include: { exercise: true, sets: { orderBy: { setIndex: 'asc' } } },
          orderBy: { position: 'asc' },
        },
      },
    }),
    prisma.analyticsEvent.create({
      data: {
        userId,
        eventName: 'workout_from_planned',
        props: {
          plannedWorkoutId,
          resolved: resolvedExercises.length,
          unresolvedCount: unresolvedNames.length,
        },
      },
    }),
  ])

  return {
    workout: full,
    meta: {
      plannedWorkoutId,
      resolved: resolvedExercises.length,
      unresolved: unresolvedNames,
    },
  }
}

function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  const number = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(number)) return fallback
  return Math.max(min, Math.min(max, Math.round(number)))
}
