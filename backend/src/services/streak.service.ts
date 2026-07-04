import { prisma } from '../lib/prisma'

// Day-based streak (spec): posting on 3 consecutive days keeps the streak; a
// gap of 3+ calendar days without posting breaks it. Multiple posts on the same
// UTC day count once — the streak is measured in distinct days, not raw posts.
const STREAK_BREAK_GAP_DAYS = 3

function utcDayKey(d: Date): string {
  const y = d.getUTCFullYear()
  const m = String(d.getUTCMonth() + 1).padStart(2, '0')
  const day = String(d.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/** Whole-day gap between two UTC day keys (YYYY-MM-DD), newer − older. */
function dayKeyGap(newerKey: string, olderKey: string): number {
  const [y1, m1, d1] = newerKey.split('-').map(Number)
  const [y2, m2, d2] = olderKey.split('-').map(Number)
  return Math.round((Date.UTC(y1, m1 - 1, d1) - Date.UTC(y2, m2 - 1, d2)) / 86_400_000)
}

/** Distinct UTC day keys with a post, most-recent first. */
function distinctPostDaysDesc(posts: { createdAt: Date }[]): string[] {
  // posts already ordered desc → Set preserves that order for the keys.
  return [...new Set(posts.map((p) => utcDayKey(new Date(p.createdAt))))]
}

/** Consecutive-day run from the most recent day, breaking at a gap ≥ 3 days. */
function consecutiveDayRun(dayKeys: string[]): number {
  if (dayKeys.length === 0) return 0
  let streak = 1
  for (let i = 1; i < dayKeys.length; i++) {
    const gap = dayKeyGap(dayKeys[i - 1], dayKeys[i])
    if (gap < STREAK_BREAK_GAP_DAYS) streak++
    else break
  }
  return streak
}

/** Shared streak core for a non-empty, desc-ordered post list. Streak resets to
 *  1 once the last post is past the break window, otherwise it's the
 *  consecutive-day run from the most recent post. */
function computeStreak(posts: { createdAt: Date }[]): {
  currentStreak: number
  daysUntilBreak: number
  gapSinceLast: number
} {
  const dayKeys = distinctPostDaysDesc(posts)
  const nowKey = utcDayKey(new Date())
  const gapSinceLast = dayKeyGap(nowKey, dayKeys[0])
  const daysUntilBreak = Math.max(0, STREAK_BREAK_GAP_DAYS - gapSinceLast)
  const currentStreak =
    gapSinceLast < STREAK_BREAK_GAP_DAYS ? consecutiveDayRun(dayKeys) : 1
  return { currentStreak, daysUntilBreak, gapSinceLast }
}

export async function updateStreak(userId: string): Promise<{
  currentStreak: number
  isAtRisk: boolean
}> {
  const posts = await prisma.post.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: 100,
  })

  if (posts.length === 0) {
    return { currentStreak: 1, isAtRisk: false }
  }

  const { currentStreak, daysUntilBreak, gapSinceLast } = computeStreak(posts)

  if (gapSinceLast >= STREAK_BREAK_GAP_DAYS) {
    // Streak broken — this post starts a fresh one.
    return { currentStreak: 1, isAtRisk: false }
  }

  return { currentStreak, isAtRisk: daysUntilBreak <= 1 }
}

export async function getStreakStatus(userId: string): Promise<{
  currentStreak: number
  daysUntilBreak: number
  isAtRisk: boolean
}> {
  const posts = await prisma.post.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: 100,
  })

  if (posts.length === 0) {
    return { currentStreak: 0, daysUntilBreak: 0, isAtRisk: false }
  }

  const { currentStreak, daysUntilBreak } = computeStreak(posts)

  return {
    currentStreak,
    daysUntilBreak,
    isAtRisk: daysUntilBreak <= 1 && currentStreak > 0,
  }
}
