import { beforeEach, describe, expect, it, vi } from 'vitest'

const userProfileFindUnique = vi.fn()
const workoutFindUnique = vi.fn()
const workoutUpdate = vi.fn()
const rankFindMany = vi.fn()
const rankUpsert = vi.fn()
const seasonFindFirst = vi.fn()
const seasonStatUpsert = vi.fn()
const analyticsCreate = vi.fn()
const transaction = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    userProfile: { findUnique: (...args: unknown[]) => userProfileFindUnique(...args) },
    workout: {
      findUnique: (...args: unknown[]) => workoutFindUnique(...args),
      update: (...args: unknown[]) => workoutUpdate(...args),
    },
    userExerciseRank: {
      findMany: (...args: unknown[]) => rankFindMany(...args),
      upsert: (...args: unknown[]) => rankUpsert(...args),
    },
    season: { findFirst: (...args: unknown[]) => seasonFindFirst(...args) },
    userSeasonStat: { upsert: (...args: unknown[]) => seasonStatUpsert(...args) },
    analyticsEvent: { create: (...args: unknown[]) => analyticsCreate(...args) },
    $transaction: (...args: unknown[]) => transaction(...args),
  },
}))

import { computeRanks } from './ranking.service'

beforeEach(() => {
  userProfileFindUnique.mockReset().mockResolvedValue({ bodyweightKg: 80 })
  workoutFindUnique.mockReset().mockResolvedValue({
    id: 'workout-1',
    exercises: [
      {
        exerciseId: 'bench-1',
        exercise: {
          name: 'Bench Press',
          isRanked: true,
          rankModel: 'WEIGHTED',
          bwStrengthFraction: null,
        },
        sets: [{ weightKg: 80, reps: 5, tag: 'WORK', isCompleted: true }],
      },
    ],
  })
  rankFindMany.mockReset().mockResolvedValue([])
  rankUpsert.mockReset().mockReturnValue(Promise.resolve({ id: 'rank-1' }))
  workoutUpdate.mockReset().mockReturnValue(Promise.resolve({ id: 'workout-1', hasPr: true }))
  seasonFindFirst.mockReset().mockResolvedValue(null)
  seasonStatUpsert.mockReset()
  analyticsCreate.mockReset().mockReturnValue(Promise.resolve({ id: 'event-1' }))
  transaction.mockReset().mockImplementation((writes: Promise<unknown>[]) => Promise.all(writes))
})

describe('computeRanks batching and PR snapshot', () => {
  it('reads previous ranks once and persists the workout PR in the same batch', async () => {
    const result = await computeRanks('user-1', 'workout-1')

    expect(result.results).toHaveLength(1)
    expect(result.results[0].lpDelta).toBeGreaterThan(0)
    expect(rankFindMany).toHaveBeenCalledOnce()
    expect(rankUpsert).toHaveBeenCalledOnce()
    expect(workoutUpdate).toHaveBeenCalledWith({
      where: { id: 'workout-1' },
      data: { hasPr: true },
    })
    expect(transaction).toHaveBeenCalledOnce()
    expect(transaction.mock.calls[0][0]).toHaveLength(3)
  })
})
