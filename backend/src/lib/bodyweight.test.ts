import { describe, it, expect, vi, beforeEach } from 'vitest'

const userProfileFindUnique = vi.fn()

vi.mock('./prisma', () => ({
  prisma: {
    userProfile: { findUnique: (...a: unknown[]) => userProfileFindUnique(...a) },
  },
}))

import { getCanonicalBodyweightKg, getUserBodyweightKg } from './bodyweight'

beforeEach(() => {
  userProfileFindUnique.mockReset()
})

describe('getCanonicalBodyweightKg', () => {
  it('returns the number for a plain number column', () => {
    expect(getCanonicalBodyweightKg({ bodyweightKg: 82.5 })).toBe(82.5)
  })

  it('parses a string (Decimal serialized as string)', () => {
    expect(getCanonicalBodyweightKg({ bodyweightKg: '74.3' })).toBe(74.3)
  })

  it('calls toNumber() on a Prisma Decimal-like object', () => {
    const decimal = { toNumber: () => 91 }
    expect(getCanonicalBodyweightKg({ bodyweightKg: decimal })).toBe(91)
  })

  it('returns 0 for a stored zero (finite, not missing)', () => {
    expect(getCanonicalBodyweightKg({ bodyweightKg: 0 })).toBe(0)
  })

  it('returns null for null / undefined column', () => {
    expect(getCanonicalBodyweightKg({ bodyweightKg: null })).toBeNull()
    expect(getCanonicalBodyweightKg({ bodyweightKg: undefined })).toBeNull()
  })

  it('returns null for a missing profile row', () => {
    expect(getCanonicalBodyweightKg(null)).toBeNull()
    expect(getCanonicalBodyweightKg(undefined)).toBeNull()
  })

  it('returns null for an unparseable string', () => {
    expect(getCanonicalBodyweightKg({ bodyweightKg: 'not-a-number' })).toBeNull()
  })

  it('returns null for NaN', () => {
    expect(getCanonicalBodyweightKg({ bodyweightKg: NaN })).toBeNull()
  })
})

describe('getUserBodyweightKg', () => {
  it('reads userProfile.bodyweightKg as the single source', async () => {
    userProfileFindUnique.mockResolvedValue({ bodyweightKg: 80 })
    await expect(getUserBodyweightKg('u1')).resolves.toBe(80)
    expect(userProfileFindUnique).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      select: { bodyweightKg: true },
    })
  })

  it('returns null when there is no profile row', async () => {
    userProfileFindUnique.mockResolvedValue(null)
    await expect(getUserBodyweightKg('nobody')).resolves.toBeNull()
  })

  it('returns null when the column is empty', async () => {
    userProfileFindUnique.mockResolvedValue({ bodyweightKg: null })
    await expect(getUserBodyweightKg('u2')).resolves.toBeNull()
  })
})
