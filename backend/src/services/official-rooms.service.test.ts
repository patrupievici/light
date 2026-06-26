import { describe, it, expect, vi, beforeEach } from 'vitest'

const userUpsert = vi.fn()
const profileUpsert = vi.fn()
const challengeUpsert = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    user: { upsert: (...a: unknown[]) => userUpsert(...a) },
    userProfile: { upsert: (...a: unknown[]) => profileUpsert(...a) },
    challenge: { upsert: (...a: unknown[]) => challengeUpsert(...a) },
  },
}))

import { seedOfficialChallenges, ZVELT_SYSTEM_USER_ID } from './official-rooms.service'

beforeEach(() => {
  userUpsert.mockReset().mockResolvedValue({})
  profileUpsert.mockReset().mockResolvedValue({})
  challengeUpsert.mockReset().mockResolvedValue({})
})

describe('seedOfficialChallenges', () => {
  it('upserts the system user + profile and every official room (all public + official)', async () => {
    await seedOfficialChallenges()

    // System user + profile keyed on the fixed sentinel id.
    expect(userUpsert).toHaveBeenCalledOnce()
    expect(userUpsert.mock.calls[0][0].where).toEqual({ id: ZVELT_SYSTEM_USER_ID })
    expect(profileUpsert.mock.calls[0][0].create).toMatchObject({
      userId: ZVELT_SYSTEM_USER_ID,
      displayName: 'Zvelt',
    })

    // Every room upsert is public + official + owned by the system user, and the
    // create path carries a far-future endsAt (permanent room).
    expect(challengeUpsert.mock.calls.length).toBeGreaterThanOrEqual(5)
    for (const call of challengeUpsert.mock.calls) {
      const arg = call[0]
      expect(arg.update).toMatchObject({ visibility: 'public', isOfficial: true })
      expect(arg.create).toMatchObject({
        creatorId: ZVELT_SYSTEM_USER_ID,
        visibility: 'public',
        isOfficial: true,
      })
      expect(arg.create.endsAt.getUTCFullYear()).toBeGreaterThan(2090)
    }
  })

  it('is idempotent: the system-user upsert uses an empty update (no field drift)', async () => {
    await seedOfficialChallenges()
    expect(userUpsert.mock.calls[0][0].update).toEqual({})
  })
})
