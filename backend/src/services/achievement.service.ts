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
  // Anti-cheat "trusted tier" (CLAUDE.md): only accounts older than 30 days
  // count toward the seasonal leaderboard, so a throwaway account can't claim a
  // top-10 slot. Mirrors the filter in routes/ranks.ts.
  const trustedBefore = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)
  const top = await prisma.userSeasonStat.findMany({
    where: {
      seasonId: season.id,
      user: { createdAt: { lte: trustedBefore }, status: 'active' },
    },
    orderBy: { lpSeason: 'desc' },
    take: 10,
    select: { userId: true },
  })
  return top.some((t) => t.userId === userId)
}

export type CheckAndAwardOptions = {
  /** Pasii din ziua curentă (Health); dacă ≥ 10_000 → steps_10k */
  stepsToday?: number
}

/**
 * Evaluează progresul userului și acordă achievement-uri noi (după workout completat etc.).
 * Returnează cheile achievement-urilor tocmai acordate în acest apel.
 */
export async function checkAndAward(
  userId: string,
  opts?: CheckAndAwardOptions
): Promise<string[]> {
  const [workoutCount, setCount, earnedRows, ranks] = await Promise.all([
    prisma.workout.count({ where: { userId, status: { in: ['completed', 'posted'] } } }),
    prisma.workoutSet.count({
      where: { workoutExercise: { workout: { userId } }, tag: 'WORK' },
    }),
    prisma.userAchievement.findMany({
      where: { userId },
      include: { achievement: true },
    }),
    prisma.userExerciseRank.findMany({ where: { userId } }),
  ])

  const earnedKeys = new Set(earnedRows.map((u) => u.achievement.key))
  const toAward: string[] = []

  const check = (key: string, condition: boolean) => {
    if (condition && !earnedKeys.has(key)) toAward.push(key)
  }

  check('first_workout', workoutCount >= 1)
  check('workouts_10', workoutCount >= 10)
  check('workouts_50', workoutCount >= 50)
  check('workouts_200', workoutCount >= 200)

  check('sets_10', setCount >= 10)
  check('sets_100', setCount >= 100)
  check('sets_500', setCount >= 500)

  if (ranks.length > 0) {
    check('first_rank', true)
    const maxLp = Math.max(...ranks.map((r) => r.lpTotal))
    check('rank_bronze', maxLp >= 100)
    check('rank_gold', maxLp >= 300)
    check('rank_diamond', maxLp >= 500)
  }

  const distinctExercises = await prisma.workoutExercise.groupBy({
    by: ['exerciseId'],
    where: { workout: { userId } },
  })
  check('exercises_5', distinctExercises.length >= 5)

  const workoutStreak = await getWorkoutDayStreak(userId)
  check('streak_3', workoutStreak >= 3)
  check('streak_7', workoutStreak >= 7)
  check('streak_30', workoutStreak >= 30)
  check('streak_100', workoutStreak >= 100)

  check('rank_top10', await isUserInSeasonTop10(userId))

  const steps = opts?.stepsToday
  if (steps != null && Number.isFinite(steps) && steps >= 10_000) {
    check('steps_10k', true)
  }

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
