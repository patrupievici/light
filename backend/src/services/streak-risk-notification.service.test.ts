import { describe, it, expect, vi, beforeEach } from 'vitest'

// ── Mocks ───────────────────────────────────────────────────────────────────
const postGroupBy = vi.fn()
vi.mock('../lib/prisma', () => ({
  prisma: {
    post: { groupBy: (...a: unknown[]) => postGroupBy(...a) },
  },
}))

const createNotificationSafe = vi.fn()
const claimScheduledNotification = vi.fn()
vi.mock('./notification.service', () => ({
  createNotificationSafe: (...a: unknown[]) => createNotificationSafe(...a),
  claimScheduledNotification: (...a: unknown[]) => claimScheduledNotification(...a),
  NotificationType: { STREAK_RISK: 'streak_risk' },
}))

import { runStreakRiskNotifications } from './streak-risk-notification.service'

const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } as never

const DAY = 86_400_000
const daysAgo = (n: number) => new Date(Date.now() - n * DAY)

beforeEach(() => {
  postGroupBy.mockReset()
  createNotificationSafe.mockReset()
  claimScheduledNotification.mockReset()
  claimScheduledNotification.mockResolvedValue(true)
})

describe('runStreakRiskNotifications', () => {
  it('notifies only users whose last post was 2–3 days ago', async () => {
    postGroupBy.mockResolvedValue([
      { userId: 'at-risk', _max: { createdAt: daysAgo(2.5) } }, // in window → notify
      { userId: 'posted-today', _max: { createdAt: daysAgo(0.2) } }, // too recent
      { userId: 'already-broken', _max: { createdAt: daysAgo(5) } }, // past the break
    ])

    const res = await runStreakRiskNotifications(log)

    expect(res.sent).toBe(1)
    expect(createNotificationSafe).toHaveBeenCalledOnce()
    expect(createNotificationSafe.mock.calls[0][0]).toMatchObject({
      recipientId: 'at-risk',
      type: 'streak_risk',
    })
  })

  it('is idempotent: skips a slot already claimed today', async () => {
    postGroupBy.mockResolvedValue([{ userId: 'at-risk', _max: { createdAt: daysAgo(2.5) } }])
    claimScheduledNotification.mockResolvedValue(false)

    const res = await runStreakRiskNotifications(log)

    expect(res.sent).toBe(0)
    expect(createNotificationSafe).not.toHaveBeenCalled()
  })

  it('claims with a UTC-date dedupe key (one warning per day)', async () => {
    postGroupBy.mockResolvedValue([{ userId: 'at-risk', _max: { createdAt: daysAgo(2.5) } }])
    await runStreakRiskNotifications(log)

    const [, type, dedupeKey] = claimScheduledNotification.mock.calls[0]
    expect(type).toBe('streak_risk')
    expect(dedupeKey).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  })

  it('only scans engaged users (groupBy filters recent posts)', async () => {
    postGroupBy.mockResolvedValue([])
    await runStreakRiskNotifications(log)

    const where = postGroupBy.mock.calls[0][0].where
    expect(where.createdAt).toHaveProperty('gt')
    expect(where.createdAt.gt).toBeInstanceOf(Date)
  })
})
