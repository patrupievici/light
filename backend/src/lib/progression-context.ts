import { prisma } from './prisma'

/**
 * Snapshot of a user's recent progression on the lifts they actually do.
 * Used to brief the AI before plan generation so prescribed loads and exercise
 * picks reflect where the user currently is, not just their goal/profile.
 */

export type ProgressionEntry = {
  exerciseId: string
  exerciseName: string
  bestE1rmKg: number
  lastWeightKg: number
  lastSets: number
  lastReps: number
  /** Days since the most recent WORK set on this exercise. */
  daysSinceLast: number
  /** Change in best e1RM over the last ~30 days (kg). Positive = improving. */
  deltaE1rm30dKg: number
}

const TOP_N = 12
const E1RM_WINDOW_DAYS = 30
const LOOKBACK_DAYS = 90

/**
 * Pull the user's top-N most recently worked exercises with their current
 * best e1RM, last weight×reps, and 30-day e1RM delta. Returns [] when the
 * user has no completed lift history yet.
 */
export async function getRecentProgression(userId: string): Promise<ProgressionEntry[]> {
  const since = new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000)

  // Last WORK set per exercise in the lookback window — also tells us which
  // exercises the user is "actively" doing.
  const recentSets = await prisma.workoutSet.findMany({
    where: {
      tag: 'WORK',
      isCompleted: true,
      weightKg: { gt: 0 },
      createdAt: { gte: since },
      workoutExercise: {
        workout: { userId, status: { in: ['completed', 'posted'] } },
      },
    },
    select: {
      weightKg: true,
      reps: true,
      createdAt: true,
      workoutExercise: {
        select: {
          exerciseId: true,
          exercise: { select: { name: true } },
        },
      },
    },
    orderBy: { createdAt: 'desc' },
    take: 800,
  })

  type Acc = {
    exerciseId: string
    name: string
    lastWeight: number
    lastReps: number
    lastAt: Date
    setCount: number
  }
  const perEx = new Map<string, Acc>()
  for (const s of recentSets) {
    const eid = s.workoutExercise.exerciseId
    const existing = perEx.get(eid)
    if (!existing) {
      perEx.set(eid, {
        exerciseId: eid,
        name: s.workoutExercise.exercise.name,
        lastWeight: Number(s.weightKg),
        lastReps: s.reps,
        lastAt: s.createdAt,
        setCount: 1,
      })
    } else {
      existing.setCount++
    }
  }

  if (perEx.size === 0) return []

  // Rank by set count (proxy for "user cares about this lift").
  const ranked = Array.from(perEx.values())
    .sort((a, b) => b.setCount - a.setCount)
    .slice(0, TOP_N)

  const ids = ranked.map((r) => r.exerciseId)

  // Current best e1RM per (user, exercise).
  const ranks = await prisma.userExerciseRank.findMany({
    where: { userId, exerciseId: { in: ids } },
    select: { exerciseId: true, bestE1rmKg: true, updatedAt: true },
  })
  const rankMap = new Map(ranks.map((r) => [r.exerciseId, r]))

  // For the 30-day delta we approximate: best e1RM among sets older than the
  // 30-day window. Cheaper than recomputing from raw sets.
  const cutoff = new Date(Date.now() - E1RM_WINDOW_DAYS * 24 * 60 * 60 * 1000)
  const oldSets = await prisma.workoutSet.findMany({
    where: {
      tag: 'WORK',
      isCompleted: true,
      weightKg: { gt: 0 },
      reps: { gte: 1, lte: 12 },
      createdAt: { lt: cutoff },
      workoutExercise: {
        exerciseId: { in: ids },
        workout: { userId, status: { in: ['completed', 'posted'] } },
      },
    },
    select: {
      weightKg: true,
      reps: true,
      workoutExercise: { select: { exerciseId: true } },
    },
    take: 2000,
  })
  const bestOldE1rm = new Map<string, number>()
  for (const s of oldSets) {
    const eid = s.workoutExercise.exerciseId
    // Epley
    const e1rm = Number(s.weightKg) * (1 + s.reps / 30)
    const cur = bestOldE1rm.get(eid)
    if (cur == null || e1rm > cur) bestOldE1rm.set(eid, e1rm)
  }

  const now = Date.now()
  return ranked.map<ProgressionEntry>((r) => {
    const currentBest = Number(rankMap.get(r.exerciseId)?.bestE1rmKg ?? 0)
    const oldBest = bestOldE1rm.get(r.exerciseId) ?? currentBest
    const daysSinceLast = Math.max(0, Math.round((now - r.lastAt.getTime()) / 86_400_000))
    return {
      exerciseId: r.exerciseId,
      exerciseName: r.name,
      bestE1rmKg: round1(currentBest),
      lastWeightKg: round1(r.lastWeight),
      lastSets: 1, // not tracked here; AI just needs weight x reps shape
      lastReps: r.lastReps,
      daysSinceLast,
      deltaE1rm30dKg: round1(currentBest - oldBest),
    }
  })
}

function round1(n: number): number {
  return Math.round(n * 10) / 10
}

/**
 * Render a progression block ready to drop inside an AI prompt. Returns an
 * empty string when the user has no history (so the prompt stays clean).
 */
export function formatProgressionForPrompt(entries: ProgressionEntry[]): string {
  if (entries.length === 0) return ''
  const lines = entries.map(
    (e) =>
      `  - ${e.exerciseName}: bestE1RM=${e.bestE1rmKg}kg, last=${e.lastWeightKg}kg×${e.lastReps} ${
        e.daysSinceLast === 0 ? 'today' : `${e.daysSinceLast}d ago`
      }, Δe1RM_30d=${e.deltaE1rm30dKg >= 0 ? '+' : ''}${e.deltaE1rm30dKg}kg`,
  )
  return `RECENT_PROGRESSION (top ${entries.length} actively trained):
${lines.join('\n')}
Use this to (a) pick exercises the user is already moving on, (b) prescribe loads that respect their current e1RM, and (c) avoid stalling — if Δe1RM_30d is near 0 on a lift, consider a small rep-range or variant change.`
}
