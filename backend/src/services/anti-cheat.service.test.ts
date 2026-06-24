import { describe, it, expect } from 'vitest'
import {
  evaluateEditLimit,
  isSrAnomaly,
  evaluateWeightJump,
  ANTI_CHEAT_CONSTANTS,
} from './anti-cheat.service'

const NOW = new Date('2026-06-20T12:00:00.000Z')
const minutesAgo = (n: number) => new Date(NOW.getTime() - n * 60_000)
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 24 * 60 * 60_000)

describe('evaluateEditLimit (max 3 / 24h per post)', () => {
  it('allows the first edit and starts the counter at 1', () => {
    const v = evaluateEditLimit({ editCount: 0, lastEditAt: null }, NOW)
    expect(v.allowed).toBe(true)
    expect(v.nextEditCount).toBe(1)
  })

  it('allows the 2nd and 3rd edits inside the window', () => {
    const second = evaluateEditLimit({ editCount: 1, lastEditAt: minutesAgo(10) }, NOW)
    expect(second.allowed).toBe(true)
    expect(second.nextEditCount).toBe(2)

    const third = evaluateEditLimit({ editCount: 2, lastEditAt: minutesAgo(5) }, NOW)
    expect(third.allowed).toBe(true)
    expect(third.nextEditCount).toBe(3)
  })

  it('rejects the 4th edit inside the 24h window', () => {
    const v = evaluateEditLimit({ editCount: 3, lastEditAt: minutesAgo(30) }, NOW)
    expect(v.allowed).toBe(false)
    expect(v.reason).toBe('EDIT_LIMIT')
    expect(v.nextEditCount).toBe(3) // unchanged
  })

  it('resets the counter once the last edit is older than 24h', () => {
    const v = evaluateEditLimit({ editCount: 3, lastEditAt: daysAgo(2) }, NOW)
    expect(v.allowed).toBe(true)
    expect(v.nextEditCount).toBe(1)
  })

  it('uses a strict < 24h boundary (exactly 24h ago resets)', () => {
    const exactly24h = new Date(NOW.getTime() - ANTI_CHEAT_CONSTANTS.DAY_MS)
    const v = evaluateEditLimit({ editCount: 3, lastEditAt: exactly24h }, NOW)
    expect(v.allowed).toBe(true)
    expect(v.nextEditCount).toBe(1)
  })
})

describe('isSrAnomaly (>20% jump vs best 30 days)', () => {
  it('flags a >20% jump', () => {
    expect(isSrAnomaly(1.21, 1.0)).toBe(true)
  })

  it('does NOT flag exactly +20% (boundary is strictly greater)', () => {
    expect(isSrAnomaly(1.2, 1.0)).toBe(false)
  })

  it('does not flag a modest improvement', () => {
    expect(isSrAnomaly(1.1, 1.0)).toBe(false)
  })

  it('never flags when there is no prior history (baseline <= 0)', () => {
    expect(isSrAnomaly(5.0, 0)).toBe(false)
    expect(isSrAnomaly(5.0, -1)).toBe(false)
  })

  it('returns false for non-finite inputs', () => {
    expect(isSrAnomaly(Number.NaN, 1.0)).toBe(false)
    expect(isSrAnomaly(1.5, Number.POSITIVE_INFINITY)).toBe(false)
  })
})

describe('evaluateWeightJump (>2x personal max within <7 days)', () => {
  const base = {
    personalMaxKg: 100,
    personalMaxAt: daysAgo(2), // recent
  }

  it('rejects a >2x jump with no note', () => {
    const v = evaluateWeightJump({ ...base, newWeightKg: 210, hasNote: false }, NOW)
    expect(v.requiresConfirmation).toBe(true)
    expect(v.rejected).toBe(true)
    expect(v.reason).toBe('WEIGHT_JUMP_REQUIRES_NOTE')
  })

  it('accepts a >2x jump WHEN a note is attached', () => {
    const v = evaluateWeightJump({ ...base, newWeightKg: 210, hasNote: true }, NOW)
    expect(v.requiresConfirmation).toBe(true)
    expect(v.rejected).toBe(false)
  })

  it('does not flag exactly 2x (boundary is strictly greater)', () => {
    const v = evaluateWeightJump({ ...base, newWeightKg: 200, hasNote: false }, NOW)
    expect(v.requiresConfirmation).toBe(false)
    expect(v.rejected).toBe(false)
  })

  it('does not flag a >2x jump when the personal max is OLD (>=7 days)', () => {
    const v = evaluateWeightJump(
      { personalMaxKg: 100, personalMaxAt: daysAgo(10), newWeightKg: 300, hasNote: false },
      NOW,
    )
    expect(v.requiresConfirmation).toBe(false)
    expect(v.rejected).toBe(false)
  })

  it('does nothing when there is no personal max yet', () => {
    const v = evaluateWeightJump(
      { personalMaxKg: null, personalMaxAt: null, newWeightKg: 999, hasNote: false },
      NOW,
    )
    expect(v.requiresConfirmation).toBe(false)
    expect(v.rejected).toBe(false)
  })
})
