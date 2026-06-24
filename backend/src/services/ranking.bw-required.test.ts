import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock the prisma client so computeRanks can run without a DB. We only need to
// drive the bodyweight branch of the function.
const userProfileFindUnique = vi.fn()
const workoutFindUnique = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    userProfile: { findUnique: (...a: unknown[]) => userProfileFindUnique(...a) },
    workout: { findUnique: (...a: unknown[]) => workoutFindUnique(...a) },
  },
}))

import { computeRanks } from './ranking.service'

beforeEach(() => {
  userProfileFindUnique.mockReset()
  workoutFindUnique.mockReset()
})

describe('computeRanks — bodyweight is mandatory (no silent fallback)', () => {
  it('throws BW_REQUIRED when the profile has no bodyweight', async () => {
    userProfileFindUnique.mockResolvedValue({ userId: 'u1', bodyweightKg: null })
    await expect(computeRanks('u1', 'w1')).rejects.toThrow('BW_REQUIRED')
    // Must NOT proceed to load the workout / fabricate a 70-80kg fallback.
    expect(workoutFindUnique).not.toHaveBeenCalled()
  })

  it('throws BW_REQUIRED when there is no profile row at all', async () => {
    userProfileFindUnique.mockResolvedValue(null)
    await expect(computeRanks('u1', 'w1')).rejects.toThrow('BW_REQUIRED')
  })

  it('throws BW_INVALID when bodyweight is out of the 30..250 range', async () => {
    userProfileFindUnique.mockResolvedValue({ userId: 'u1', bodyweightKg: 5 })
    await expect(computeRanks('u1', 'w1')).rejects.toThrow('BW_INVALID')

    userProfileFindUnique.mockResolvedValue({ userId: 'u1', bodyweightKg: 999 })
    await expect(computeRanks('u1', 'w1')).rejects.toThrow('BW_INVALID')
  })

  it('proceeds past the bodyweight guard for a valid bodyweight', async () => {
    userProfileFindUnique.mockResolvedValue({ userId: 'u1', bodyweightKg: 80 })
    // Workout not found → a DIFFERENT, later error proves we passed the BW guard.
    workoutFindUnique.mockResolvedValue(null)
    await expect(computeRanks('u1', 'w1')).rejects.toThrow('WORKOUT_NOT_FOUND')
    expect(workoutFindUnique).toHaveBeenCalledOnce()
  })
})
