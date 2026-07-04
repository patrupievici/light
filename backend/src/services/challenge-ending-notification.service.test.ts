import { describe, it, expect, vi, beforeEach } from 'vitest'

// ── Mocks ───────────────────────────────────────────────────────────────────
const challengeFindMany = vi.fn()
const participantFindMany = vi.fn()
const progressLogGroupBy = vi.fn()
vi.mock('../lib/prisma', () => ({
  prisma: {
    challenge: { findMany: (...a: unknown[]) => challengeFindMany(...a) },
    challengeParticipant: { findMany: (...a: unknown[]) => participantFindMany(...a) },
    challengeProgressLog: { groupBy: (...a: unknown[]) => progressLogGroupBy(...a) },
  },
}))

const createNotificationSafe = vi.fn()
const claimScheduledNotification = vi.fn()
vi.mock('./notification.service', () => ({
  createNotificationSafe: (...a: unknown[]) => createNotificationSafe(...a),
  claimScheduledNotification: (...a: unknown[]) => claimScheduledNotification(...a),
  NotificationType: {
    CHALLENGE_ENDING_SOON: 'challenge_ending_soon',
    CHALLENGE_ENDED: 'challenge_ended',
  },
}))

const recomputeChallenge = vi.fn()
vi.mock('./challenge-recalc.service', () => ({
  recomputeChallenge: (...a: unknown[]) => recomputeChallenge(...a),
}))

import { runChallengeEndingNotifications } from './challenge-ending-notification.service'

const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } as never

const HOUR = 3_600_000

beforeEach(() => {
  challengeFindMany.mockReset()
  participantFindMany.mockReset()
  createNotificationSafe.mockReset()
  claimScheduledNotification.mockReset()
  recomputeChallenge.mockReset()
  progressLogGroupBy.mockReset()
  claimScheduledNotification.mockResolvedValue(true)
  recomputeChallenge.mockResolvedValue(undefined)
  progressLogGroupBy.mockResolvedValue([])
})

describe('runChallengeEndingNotifications', () => {
  it('notifies every accepted participant of a challenge ending soon', async () => {
    challengeFindMany
      .mockResolvedValueOnce([
        { id: 'c1', kind: 'custom', customTitle: 'Push Week', endsAt: new Date(Date.now() + 12 * HOUR) },
      ]) // ending soon
      .mockResolvedValueOnce([]) // just ended
    participantFindMany.mockResolvedValueOnce([{ userId: 'u1' }, { userId: 'u2' }])

    const res = await runChallengeEndingNotifications(log)

    expect(res.endingSoon).toBe(2)
    expect(createNotificationSafe).toHaveBeenCalledTimes(2)
    expect(createNotificationSafe.mock.calls[0][0]).toMatchObject({
      type: 'challenge_ending_soon',
      payload: { challengeId: 'c1', title: 'Push Week' },
    })
  })

  it('recomputes scored ended challenges then announces the winner', async () => {
    challengeFindMany
      .mockResolvedValueOnce([]) // ending soon
      .mockResolvedValueOnce([
        {
          id: 'c2',
          kind: 'custom',
          customTitle: 'Volume Vol',
          endsAt: new Date(Date.now() - HOUR),
          scoringType: 'total_volume',
        },
      ]) // just ended
    participantFindMany.mockResolvedValueOnce([
      { userId: 'w', rank: 1, user: { profile: { displayName: 'Winner', username: 'win' } } },
      { userId: 'l', rank: 2, user: { profile: { displayName: 'Runner', username: 'run' } } },
    ])

    const res = await runChallengeEndingNotifications(log)

    expect(recomputeChallenge).toHaveBeenCalledWith('c2')
    expect(res.ended).toBe(2)
    const winnerCall = createNotificationSafe.mock.calls.find((c) => (c[0] as any).recipientId === 'w')![0] as any
    expect(winnerCall.payload).toMatchObject({ winnerName: 'Winner', youWon: true, myRank: 1 })
    const loserCall = createNotificationSafe.mock.calls.find((c) => (c[0] as any).recipientId === 'l')![0] as any
    expect(loserCall.payload).toMatchObject({ winnerName: 'Winner', youWon: false, myRank: 2 })
  })

  it('is idempotent: a claimed slot is not re-sent', async () => {
    challengeFindMany
      .mockResolvedValueOnce([
        { id: 'c1', kind: 'custom', customTitle: 'X', endsAt: new Date(Date.now() + HOUR) },
      ])
      .mockResolvedValueOnce([])
    participantFindMany.mockResolvedValueOnce([{ userId: 'u1' }])
    claimScheduledNotification.mockResolvedValue(false)

    const res = await runChallengeEndingNotifications(log)

    expect(res.endingSoon).toBe(0)
    expect(createNotificationSafe).not.toHaveBeenCalled()
  })

  it('does not recompute a legacy (non-scored) ended challenge', async () => {
    challengeFindMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        { id: 'c3', kind: 'custom', customTitle: 'Legacy', endsAt: new Date(Date.now() - HOUR), scoringType: null },
      ])
    participantFindMany.mockResolvedValueOnce([
      { userId: 'a', rank: null, user: { profile: { displayName: 'A', username: 'a' } } },
    ])

    await runChallengeEndingNotifications(log)

    expect(recomputeChallenge).not.toHaveBeenCalled()
  })

  it('legacy challenge: winner is the top progress-log total, not the earliest joiner', async () => {
    challengeFindMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        { id: 'c4', kind: 'custom', customTitle: 'Legacy Race', endsAt: new Date(Date.now() - HOUR), scoringType: null },
      ])
    // `early` joined first (rank null for everyone in legacy), `late` logged more.
    participantFindMany.mockResolvedValueOnce([
      { userId: 'early', rank: null, user: { profile: { displayName: 'Early', username: 'early' } } },
      { userId: 'late', rank: null, user: { profile: { displayName: 'Late', username: 'late' } } },
    ])
    progressLogGroupBy.mockResolvedValueOnce([
      { userId: 'early', _sum: { amount: 10 } },
      { userId: 'late', _sum: { amount: 42 } },
    ])

    const res = await runChallengeEndingNotifications(log)

    expect(res.ended).toBe(2)
    const lateCall = createNotificationSafe.mock.calls.find((c) => (c[0] as any).recipientId === 'late')![0] as any
    expect(lateCall.payload).toMatchObject({ winnerName: 'Late', youWon: true })
    const earlyCall = createNotificationSafe.mock.calls.find((c) => (c[0] as any).recipientId === 'early')![0] as any
    expect(earlyCall.payload).toMatchObject({ winnerName: 'Late', youWon: false })
  })

  it('legacy challenge with no logged scores announces no winner', async () => {
    challengeFindMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        { id: 'c5', kind: 'custom', customTitle: 'Empty', endsAt: new Date(Date.now() - HOUR), scoringType: null },
      ])
    participantFindMany.mockResolvedValueOnce([
      { userId: 'a', rank: null, user: { profile: { displayName: 'A', username: 'a' } } },
      { userId: 'b', rank: null, user: { profile: { displayName: 'B', username: 'b' } } },
    ])
    progressLogGroupBy.mockResolvedValueOnce([])

    await runChallengeEndingNotifications(log)

    const call = createNotificationSafe.mock.calls.find((c) => (c[0] as any).recipientId === 'a')![0] as any
    expect(call.payload.winnerName).toBeNull()
    expect(call.payload.youWon).toBe(false)
  })
})
