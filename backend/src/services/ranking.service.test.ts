import { describe, it, expect } from 'vitest'

import {
  calcE1RM,
  calcStrengthRatio,
  srToLP,
  lpToTier,
  inferBwStrengthFraction,
  resolveBwStrengthFraction,
  bestWorkSetForRank,
} from './ranking.service'

// These tests cover the pure-function core of the ranking pipeline. Anything
// here breaking means user ranks will silently shift — high blast radius, so
// keep these guarded.

describe('calcE1RM (Epley)', () => {
  it('returns weight × (1 + reps/30) within the valid rep range', () => {
    // Hand-computed: 100 * (1 + 5/30) = 100 * 1.16666... ≈ 116.67
    expect(calcE1RM(100, 5)).toBeCloseTo(116.667, 2)
    // Epley at reps=1: 150 * (1 + 1/30) ≈ 155. (The formula is an *estimate*
    // of 1RM from any rep count; it doesn't collapse to identity at reps=1.)
    expect(calcE1RM(150, 1)).toBeCloseTo(155, 2)
    // 12 reps (top of valid range): 80 * (1 + 12/30) = 80 * 1.4 = 112
    expect(calcE1RM(80, 12)).toBeCloseTo(112, 4)
  })

  it('returns null for reps outside [1..12]', () => {
    expect(calcE1RM(100, 0)).toBeNull()
    expect(calcE1RM(100, 13)).toBeNull()
    expect(calcE1RM(100, 20)).toBeNull()
  })

  it('returns null for non-positive weight', () => {
    expect(calcE1RM(0, 5)).toBeNull()
    expect(calcE1RM(-10, 5)).toBeNull()
  })
})

describe('calcStrengthRatio', () => {
  it('is e1RM divided by bodyweight', () => {
    expect(calcStrengthRatio(120, 80)).toBeCloseTo(1.5, 4)
    expect(calcStrengthRatio(100, 100)).toBeCloseTo(1.0, 4)
  })
})

describe('srToLP', () => {
  it('returns 0 when SR is below the first threshold', () => {
    // WEIGHTED thresholds start at 0.4. SR=0.1 → tier 0, very low LP
    expect(srToLP(0.1, 'Curl')).toBe(0)
  })

  it('places mid-tier values inside the correct 100-LP band', () => {
    // WEIGHTED thresholds: [0.4, 0.6, 0.85, 1.2, 1.6, 2.0, 2.5]
    // SR=0.5 sits between tier 0 (0.4) and tier 1 (0.6) → LP in [0..99]
    const lp = srToLP(0.5, 'Curl')
    expect(lp).toBeGreaterThanOrEqual(0)
    expect(lp).toBeLessThan(100)
  })

  it('uses HEAVY thresholds for squat/deadlift/hip thrust', () => {
    // HEAVY thresholds: [0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0]
    // SR=2.0 (HEAVY tier 4) maps to LP in [400..499]
    const lpHeavy = srToLP(2.0, 'Back Squat')
    expect(lpHeavy).toBeGreaterThanOrEqual(400)
    expect(lpHeavy).toBeLessThan(500)
    // Same SR on a non-heavy lift should land in a higher tier
    const lpDefault = srToLP(2.0, 'Curl')
    expect(lpDefault).toBeGreaterThan(lpHeavy)
  })

  it('caps at 699 even when SR exceeds the top threshold', () => {
    expect(srToLP(10, 'Curl')).toBeLessThanOrEqual(699)
  })
})

describe('lpToTier', () => {
  it('maps every 100-LP band to the next tier', () => {
    expect(lpToTier(0)).toBe('Iron')
    expect(lpToTier(99)).toBe('Iron')
    expect(lpToTier(100)).toBe('Bronze')
    expect(lpToTier(200)).toBe('Silver')
    expect(lpToTier(300)).toBe('Gold')
    expect(lpToTier(400)).toBe('Platinum')
    expect(lpToTier(500)).toBe('Diamond')
    expect(lpToTier(600)).toBe('Olympian')
  })

  it('clamps overflow to the last tier (no array out-of-bounds)', () => {
    expect(lpToTier(10000)).toBe('Olympian')
  })
})

describe('inferBwStrengthFraction', () => {
  it('returns 1.0 for full-bodyweight lifts (pull-up, chin-up)', () => {
    expect(inferBwStrengthFraction('Pull Up')).toBe(1.0)
    expect(inferBwStrengthFraction('Chin Up')).toBe(1.0)
  })

  it('returns 0.64 for push-ups (standard biomechanics estimate)', () => {
    expect(inferBwStrengthFraction('Push Up')).toBe(0.64)
    expect(inferBwStrengthFraction('Pushup')).toBeCloseTo(0.64, 2)
  })

  it('falls back to 0.7 for unknown bodyweight movement', () => {
    expect(inferBwStrengthFraction('Random Move')).toBe(0.7)
  })
})

describe('resolveBwStrengthFraction', () => {
  it('returns 1 for non-BW_REPS exercises (weight is the load)', () => {
    expect(resolveBwStrengthFraction('Back Squat', 'WEIGHTED', null)).toBe(1)
  })

  it('uses the DB value when present and within [0, 2.5]', () => {
    expect(resolveBwStrengthFraction('Pull Up', 'BW_REPS', 0.95)).toBe(0.95)
  })

  it('falls back to name-inferred fraction when DB value is missing or invalid', () => {
    expect(resolveBwStrengthFraction('Push Up', 'BW_REPS', null)).toBe(0.64)
    expect(resolveBwStrengthFraction('Push Up', 'BW_REPS', -1)).toBe(0.64)
    expect(resolveBwStrengthFraction('Push Up', 'BW_REPS', 999)).toBe(0.64)
  })

  it('unwraps Prisma Decimal-like objects via toNumber()', () => {
    const decimalLike = { toNumber: () => 1.2 }
    expect(resolveBwStrengthFraction('Pull Up', 'BW_REPS', decimalLike)).toBe(1.2)
  })
})

describe('bestWorkSetForRank', () => {
  const exercise = {
    name: 'Back Squat',
    rankModel: 'WEIGHTED',
    isRanked: true,
    bwStrengthFraction: null,
  }

  it('ignores warmup sets and incomplete sets', () => {
    const sets = [
      { weightKg: 60, reps: 5, tag: 'WARMUP', isCompleted: true },
      { weightKg: 100, reps: 5, tag: 'WORK', isCompleted: false },
      { weightKg: 80, reps: 5, tag: 'WORK', isCompleted: true },
    ]
    const best = bestWorkSetForRank(exercise, 80, sets)
    expect(best).not.toBeNull()
    expect(best!.weightKg).toBe(80)
    expect(best!.reps).toBe(5)
  })

  it('picks the set with the highest e1RM, not the highest weight', () => {
    const sets = [
      // 100×3 → e1RM 110; 90×8 → e1RM 114 (higher!)
      { weightKg: 100, reps: 3, tag: 'WORK', isCompleted: true },
      { weightKg: 90, reps: 8, tag: 'WORK', isCompleted: true },
    ]
    const best = bestWorkSetForRank(exercise, 80, sets)
    expect(best!.weightKg).toBe(90)
    expect(best!.reps).toBe(8)
  })

  it('returns null for non-ranked exercises', () => {
    const sets = [{ weightKg: 100, reps: 5, tag: 'WORK', isCompleted: true }]
    expect(bestWorkSetForRank({ ...exercise, isRanked: false }, 80, sets)).toBeNull()
  })

  it('computes BW_REPS load as bodyweight×fraction + added weight', () => {
    // Pull-up at bw=80, fraction=1.0, +20kg added, 5 reps
    // loadKg = 80*1 + 20 = 100; e1RM = 100*(1+5/30) ≈ 116.67
    const pullUp = {
      name: 'Pull Up',
      rankModel: 'BW_REPS',
      isRanked: true,
      bwStrengthFraction: null,
    }
    const sets = [{ weightKg: 20, reps: 5, tag: 'WORK', isCompleted: true }]
    const best = bestWorkSetForRank(pullUp, 80, sets)
    expect(best).not.toBeNull()
    expect(best!.e1rm).toBeCloseTo(116.667, 2)
  })

  it('returns null when no valid WORK set exists', () => {
    expect(bestWorkSetForRank(exercise, 80, [])).toBeNull()
    expect(
      bestWorkSetForRank(exercise, 80, [
        { weightKg: 100, reps: 5, tag: 'WARMUP', isCompleted: true },
      ]),
    ).toBeNull()
  })
})
