import { prisma } from '../lib/prisma'

const STREAK_GRACE_DAYS = 3

export async function updateStreak(userId: string): Promise<{
  currentStreak: number
  isAtRisk: boolean
}> {
  const status = await getStreakStatus(userId)
  return {
    currentStreak: status.currentStreak || 1,
    isAtRisk: status.isAtRisk,
  }
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

  const now = new Date()
  const last = new Date(posts[0].createdAt)
  const daysSinceLast = Math.floor((now.getTime() - last.getTime()) / (1000 * 60 * 60 * 24))
  const daysUntilBreak = Math.max(0, STREAK_GRACE_DAYS - daysSinceLast)

  // Mirror updateStreak: streak resets to 1 once the last post is past the grace window
  let currentStreak = 1
  if (daysSinceLast <= STREAK_GRACE_DAYS) {
    for (let i = 1; i < posts.length; i++) {
      const curr = new Date(posts[i - 1].createdAt)
      const prev = new Date(posts[i].createdAt)
      const diff = Math.floor((curr.getTime() - prev.getTime()) / (1000 * 60 * 60 * 24))
      if (diff <= STREAK_GRACE_DAYS) {
        currentStreak++
      } else {
        break
      }
    }
  }

  return {
    currentStreak,
    daysUntilBreak,
    isAtRisk: daysUntilBreak <= 1 && currentStreak > 0,
  }
}
