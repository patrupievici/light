import { describe, it, expect, vi, beforeEach } from 'vitest'

// Idempotency guard for POST /programs/:id/start-day (#43): the client re-fires
// start-day whenever the tracker exits uncompleted, which previously minted a
// duplicate 'planned' calendar row + an orphan draft workout every call. These
// tests pin reuseExistingProgramDay — the lookup that reuses today's still-open
// planned session + its draft instead of creating new rows.

const plannedFindFirst = vi.fn()
const plannedCreate = vi.fn()
const workoutFindFirst = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    plannedWorkout: {
      findFirst: (...a: unknown[]) => plannedFindFirst(...a),
      create: (...a: unknown[]) => plannedCreate(...a),
    },
    workout: { findFirst: (...a: unknown[]) => workoutFindFirst(...a) },
  },
}))

import { reuseExistingProgramDay } from './program.service'

beforeEach(() => {
  plannedFindFirst.mockReset()
  plannedCreate.mockReset()
  workoutFindFirst.mockReset()
})

describe('reuseExistingProgramDay', () => {
  it('returns null when there is no open planned for today (caller creates fresh)', async () => {
    plannedFindFirst.mockResolvedValue(null)

    const r = await reuseExistingProgramDay('u1', '2026-07-04', 'StrongLifts 5×5 — Day A')

    expect(r).toBeNull()
    // No draft lookup and no create when there is nothing to reuse.
    expect(workoutFindFirst).not.toHaveBeenCalled()
    expect(plannedCreate).not.toHaveBeenCalled()

    // The reuse lookup is scoped to this user+day+title and to not-yet-completed
    // rows only — that scoping is what prevents duplicate calendar entries.
    const where = (plannedFindFirst.mock.calls[0][0] as { where: Record<string, unknown> }).where
    expect(where).toMatchObject({
      userId: 'u1',
      day: '2026-07-04',
      title: 'StrongLifts 5×5 — Day A',
      status: { in: ['pending', 'in_progress'] },
    })
  })

  it('reuses the existing planned + its draft workout (no new rows created)', async () => {
    plannedFindFirst.mockResolvedValue({ id: 'pw1' })
    workoutFindFirst.mockResolvedValue({ id: 'w1', _count: { exercises: 5 } })

    const r = await reuseExistingProgramDay('u1', '2026-07-04', 'StrongLifts 5×5 — Day A')

    expect(r).toEqual({ workoutId: 'w1', plannedWorkoutId: 'pw1', resolved: 5 })
    expect(plannedCreate).not.toHaveBeenCalled()
    // The draft is located by the converter's `From plan: <title>` notes convention.
    const where = (workoutFindFirst.mock.calls[0][0] as { where: Record<string, unknown> }).where
    expect(where).toMatchObject({
      userId: 'u1',
      status: 'draft',
      notes: 'From plan: StrongLifts 5×5 — Day A',
    })
  })
})
