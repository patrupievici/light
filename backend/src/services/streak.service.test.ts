import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

const postFindMany = vi.fn()
vi.mock('../lib/prisma', () => ({
  prisma: { post: { findMany: (...a: unknown[]) => postFindMany(...a) } },
}))

import { updateStreak, getStreakStatus } from './streak.service'

/** Posts (desc) whose createdAt lands on the given UTC dates at noon. */
function postsOn(...isoDays: string[]) {
  return isoDays.map((d) => ({ createdAt: new Date(`${d}T12:00:00.000Z`) }))
}

beforeEach(() => {
  postFindMany.mockReset()
  vi.useFakeTimers()
})
afterEach(() => {
  vi.useRealTimers()
})

describe('updateStreak (day-based)', () => {
  it('counts multiple posts in one day as a single streak day', async () => {
    vi.setSystemTime(new Date('2026-07-02T20:00:00.000Z'))
    // 4 posts today, 1 yesterday, 1 the day before → 3-day streak (not 6).
    postFindMany.mockResolvedValueOnce([
      { createdAt: new Date('2026-07-02T09:00:00.000Z') },
      { createdAt: new Date('2026-07-02T10:00:00.000Z') },
      { createdAt: new Date('2026-07-02T11:00:00.000Z') },
      { createdAt: new Date('2026-07-02T12:00:00.000Z') },
      ...postsOn('2026-07-01', '2026-06-30'),
    ])

    const res = await updateStreak('u1')
    expect(res.currentStreak).toBe(3)
  })

  it('breaks the run at a gap of 3+ calendar days', async () => {
    vi.setSystemTime(new Date('2026-07-02T20:00:00.000Z'))
    // today, yesterday, then a 3-day jump → run stops at 2.
    postFindMany.mockResolvedValueOnce(postsOn('2026-07-02', '2026-07-01', '2026-06-28'))

    const res = await updateStreak('u1')
    expect(res.currentStreak).toBe(2)
  })
})

describe('getStreakStatus (day-based)', () => {
  it('dedupes same-day posts and reports days until break', async () => {
    vi.setSystemTime(new Date('2026-07-02T20:00:00.000Z'))
    postFindMany.mockResolvedValueOnce(postsOn('2026-07-02', '2026-07-02', '2026-07-01'))

    const res = await getStreakStatus('u1')
    expect(res.currentStreak).toBe(2)
    expect(res.daysUntilBreak).toBe(3) // last post today → gap 0
  })

  it('resets to a broken streak once the gap reaches 3 days', async () => {
    vi.setSystemTime(new Date('2026-07-05T20:00:00.000Z'))
    // last post 3 days ago → broken (gap >= 3): run is not counted, daysUntilBreak 0.
    postFindMany.mockResolvedValueOnce(postsOn('2026-07-02', '2026-07-01'))

    const res = await getStreakStatus('u1')
    expect(res.currentStreak).toBe(1)
    expect(res.daysUntilBreak).toBe(0)
  })
})
