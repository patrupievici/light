import { prisma } from '../lib/prisma'

/** Toleranță între zile consecutive de workout (aceeași idee ca streak pe postări). */
const WORKOUT_STREAK_GRACE_DAYS = 3

function utcDayKey(d: Date): string {
  const y = d.getUTCFullYear()
  const m = String(d.getUTCMonth() + 1).padStart(2, '0')
  const day = String(d.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function parseDayKey(key: string): Date {
  const [y, m, day] = key.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, day))
}

/** Zile unice cu workout completed/posted, ordonate desc; streak crește cât timp gap-ul între zile consecutive ≤ grace. */
async function getWorkoutDayStreak(userId: string): Promise<number> {
  const workouts = await prisma.workout.findMany({
    where: { userId, status: { in: ['completed', 'posted'] } },
    orderBy: { startedAt: 'desc' },
    select: { startedAt: true },
    take: 400,
  })
  if (workouts.length === 0) return 0

  const daySet = new Set<string>()
  for (const w of workouts) {
    daySet.add(utcDayKey(w.startedAt))
  }
  const days = Array.from(daySet).sort((a, b) => b.localeCompare(a))
  let streak = 1
  for (let i = 1; i < days.length; i++) {
    const prev = parseDayKey(days[i - 1])
    const curr = parseDayKey(days[i])
    const gapDays = Math.round((prev.getTime() - curr.getTime()) / 86_400_000)
    if (gapDays <= WORKOUT_STREAK_GRACE_DAYS) streak++
    else break
  }
  return streak
}

async function isUserInSeasonTop10(userId: string): Promise<boolean> {
  const now = new Date()
  const season = await prisma.season.findFirst({
    where: { startsAt: { lte: now }, endsAt: { gte: now } },
  })
  if (!season) return false
  const top = await prisma.userSeasonStat.findMany({
    where: { seasonId: season.id },
    orderBy: { lpSeason: 'desc' },
    take: 10,
    select: { userId: true },
  })
  return top.some((t) => t.userId === userId)
}

export type CheckAndAwardOptions = {
  /** Pasii din ziua curentă (Health); dacă ≥ 10_000 → steps_10k */
  stepsToday?: number
  /** Fresh LP from a rank calculation running alongside the snapshot load. */
  rankLpFloor?: number
}

export type AchievementProgressSnapshot = {
  workoutCount: number
  setCount: number
  earnedKeys: Set<string>
  maxLp: number
  distinctExerciseCount: number
  workoutStreak: number
  isSeasonTop10: boolean
}

/** Load all independent achievement inputs concurrently. */
export async function loadAchievementProgress(
  userId: string,
): Promise<AchievementProgressSnapshot> {
  const [
    workoutCount,
    setCount,
    earnedRows,
    ranks,
    distinctExercises,
    workoutStreak,
    isSeasonTop10,
  ] = await Promise.all([
    prisma.workout.count({ where: { userId, status: { in: ['completed', 'posted'] } } }),
    prisma.workoutSet.count({
      where: { workoutExercise: { workout: { userId } }, tag: 'WORK' },
    }),
    prisma.userAchievement.findMany({
      where: { userId },
      include: { achievement: true },
    }),
    prisma.userExerciseRank.findMany({
      where: { userId },
      select: { lpTotal: true },
    }),
    prisma.workoutExercise.groupBy({
      by: ['exerciseId'],
      where: { workout: { userId } },
    }),
    getWorkoutDayStreak(userId),
    isUserInSeasonTop10(userId),
  ])

  return {
    workoutCount,
    setCount,
    earnedKeys: new Set(earnedRows.map((u) => u.achievement.key)),
    maxLp: ranks.length > 0 ? Math.max(...ranks.map((r) => r.lpTotal)) : 0,
    distinctExerciseCount: distinctExercises.length,
    workoutStreak,
    isSeasonTop10,
  }
}

/** Pure threshold evaluation, shared by the fast completion path and tests. */
export function achievementKeysForProgress(
  progress: AchievementProgressSnapshot,
  opts?: CheckAndAwardOptions,
): string[] {
  const toAward: string[] = []
  const check = (key: string, condition: boolean) => {
    if (condition && !progress.earnedKeys.has(key)) toAward.push(key)
  }

  check('first_workout', progress.workoutCount >= 1)
  check('workouts_10', progress.workoutCount >= 10)
  check('workouts_50', progress.workoutCount >= 50)
  check('workouts_200', progress.workoutCount >= 200)
  check('sets_10', progress.setCount >= 10)
  check('sets_100', progress.setCount >= 100)
  check('sets_500', progress.setCount >= 500)

  const maxLp = Math.max(progress.maxLp, opts?.rankLpFloor ?? 0)
  if (maxLp > 0) {
    check('first_rank', true)
    check('rank_bronze', maxLp >= 100)
    check('rank_gold', maxLp >= 300)
    check('rank_diamond', maxLp >= 500)
  }

  check('exercises_5', progress.distinctExerciseCount >= 5)
  check('streak_3', progress.workoutStreak >= 3)
  check('streak_7', progress.workoutStreak >= 7)
  check('streak_30', progress.workoutStreak >= 30)
  check('streak_100', progress.workoutStreak >= 100)
  check('rank_top10', progress.isSeasonTop10)

  const steps = opts?.stepsToday
  if (steps != null && Number.isFinite(steps) && steps >= 10_000) {
    check('steps_10k', true)
  }
  return toAward
}

export async function awardAchievementProgress(
  userId: string,
  progress: AchievementProgressSnapshot,
  opts?: CheckAndAwardOptions,
): Promise<string[]> {
  const toAward = achievementKeysForProgress(progress, opts)
  if (toAward.length > 0) {
    const achievements = await prisma.achievement.findMany({
      where: { key: { in: toAward } },
    })
    await prisma.userAchievement.createMany({
      data: achievements.map((a) => ({ userId, achievementId: a.id })),
      skipDuplicates: true,
    })
  }
  return toAward
}

/**
 * Evaluează progresul userului și acordă achievement-uri noi (după workout completat etc.).
 * Returnează cheile achievement-urilor tocmai acordate în acest apel.
 */
export async function checkAndAward(
  userId: string,
  opts?: CheckAndAwardOptions
): Promise<string[]> {
  const progress = await loadAchievementProgress(userId)
  return awardAchievementProgress(userId, progress, opts)
}
