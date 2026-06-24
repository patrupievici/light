import { prisma } from '../lib/prisma'
import { autoregulateLoad, type ProgressionLevel } from '../lib/progressive-overload'

// Same compound set the overload engine uses (mirrors progressive-overload.ts).
const COMPOUND_PATTERNS = new Set([
  'squat',
  'hinge',
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
])

type CompletedWorkout = {
  exercises: Array<{
    exerciseId: string
    exercise: { rankModel: string; movementPattern: string }
    sets: Array<{
      weightKg: unknown
      reps: number
      rpe: unknown
      tag: string
      isCompleted: boolean
      setIndex: number
    }>
  }>
}

/**
 * On workout complete: persist durable per-lift autoregulation state — what the
 * user actually logged (last weight/reps + the hardest RPE of the session) and
 * the engine's decision for next time (autoregulateLoad). Foundation for the
 * next-session reconcile + the "next session" UI; nothing here mutates a plan.
 *
 * Best-effort and idempotent (upsert per (user, lift)). Returns how many lifts
 * were recorded. Caller wraps in try/catch — never block workout completion.
 */
export async function recordWorkoutProgress(
  userId: string,
  workout: CompletedWorkout,
  level: ProgressionLevel,
): Promise<number> {
  const now = new Date()
  const ops: ReturnType<typeof prisma.userExerciseProgress.upsert>[] = []

  for (const we of workout.exercises) {
    if (!we.exerciseId) continue
    const workSets = we.sets.filter((s) => s.tag === 'WORK' && s.isCompleted)
    if (workSets.length === 0) continue

    // Last logged WORK set drives "achieved"; hardest RPE of the session is the
    // autoregulation signal (the most fatiguing set).
    const lastSet = workSets.reduce((a, b) => (b.setIndex > a.setIndex ? b : a))
    const lastWeight = Number(lastSet.weightKg)
    const lastReps = lastSet.reps
    const rpes = workSets
      .map((s) => (s.rpe == null ? null : Number(s.rpe)))
      .filter((x): x is number => x != null && Number.isFinite(x))
    const lastRpe = rpes.length ? Math.max(...rpes) : null

    let nextSource: string | null = null
    let nextWeightKg: number | null = null
    let nextReason: string | null = null
    // Weighted lifts only — bodyweight progression is rep-based, handled
    // elsewhere; we still store the raw evidence for it below.
    if (we.exercise.rankModel !== 'BW_REPS' && lastWeight > 0) {
      const isCompound = COMPOUND_PATTERNS.has(we.exercise.movementPattern ?? '')
      const decision = autoregulateLoad({ level, isCompound, lastWeight, lastReps, lastRpe })
      nextSource = decision.source
      nextWeightKg = decision.suggestedWeightKg
      nextReason = decision.reason
    }

    ops.push(
      prisma.userExerciseProgress.upsert({
        where: { userId_exerciseId: { userId, exerciseId: we.exerciseId } },
        create: {
          userId,
          exerciseId: we.exerciseId,
          lastWeightKg: lastWeight,
          lastReps,
          lastRpe,
          lastWorkoutAt: now,
          nextSource,
          nextWeightKg,
          nextReason,
        },
        update: {
          lastWeightKg: lastWeight,
          lastReps,
          lastRpe,
          lastWorkoutAt: now,
          nextSource,
          nextWeightKg,
          nextReason,
        },
      }),
    )
  }

  if (ops.length > 0) await prisma.$transaction(ops)
  return ops.length
}
