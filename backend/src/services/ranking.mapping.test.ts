import { describe, it, expect, vi } from 'vitest'

// computeRanks pulls in prisma at import time; stub it so this pure-helper suite
// never touches a DB.
vi.mock('../lib/prisma', () => ({ prisma: {} }))

import {
  resolveByKeyword,
  getSRThresholds,
  getSRThresholdsBw,
  inferBwStrengthFraction,
  srToLP,
  type KeywordRule,
} from './ranking.service'

// ─── Threshold constants (must match ranking.service) ──────────────────────────
const HEAVY = [0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0]
const UPPER = [0.3, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
const DEFAULT_W = [0.4, 0.6, 0.85, 1.2, 1.6, 2.0, 2.5]

const BW_VERTICAL = [0.52, 0.68, 0.82, 0.95, 1.08, 1.22, 1.38]
const BW_HORIZONTAL = [0.36, 0.46, 0.54, 0.62, 0.7, 0.78, 0.88]
const BW_LOWER = [0.42, 0.55, 0.68, 0.8, 0.93, 1.05, 1.18]

describe('resolveByKeyword (generic data-driven matcher)', () => {
  const rules: KeywordRule<string>[] = [
    { match: ['alpha', 'a1'], value: 'A' },
    { match: ['beta'], value: 'B' },
  ]

  it('returns the first matching rule (precedence preserved)', () => {
    // contains both 'alpha' and 'beta' → first rule wins
    expect(resolveByKeyword('alpha beta combo', rules, 'FALLBACK')).toBe('A')
  })

  it('matches case-insensitively on substring', () => {
    expect(resolveByKeyword('Some BETA thing', rules, 'FALLBACK')).toBe('B')
  })

  it('returns the fallback when nothing matches', () => {
    expect(resolveByKeyword('gamma', rules, 'FALLBACK')).toBe('FALLBACK')
  })
})

describe('getSRThresholds — WEIGHTED bands (behavior-preserving)', () => {
  it.each([
    ['Squat', HEAVY],
    ['Front Squat', HEAVY],
    ['Deadlift', HEAVY],
    ['Romanian Deadlift', HEAVY],
    ['Hip Thrust', HEAVY],
    ['Bench Press', UPPER],
    ['Overhead Press', UPPER],
    ['Barbell Row', UPPER],
    ['Leg Press', UPPER], // 'press' substring → UPPER (same as old chain)
    ['Dumbbell Curl', DEFAULT_W],
    ['Lateral Raise', DEFAULT_W],
    ['Leg Curl', DEFAULT_W],
  ])('%s → expected band', (name, expected) => {
    expect(getSRThresholds(name)).toEqual(expected)
  })

  it('heavy takes precedence over upper when both keywords present', () => {
    // contains 'squat' (heavy) and would-be nothing else; precedence covered.
    expect(getSRThresholds('Box Squat')).toEqual(HEAVY)
  })
})

describe('getSRThresholdsBw — BW_REPS kinds (behavior-preserving)', () => {
  it.each([
    ['Pull-up', BW_VERTICAL],
    ['Chin-up', BW_VERTICAL],
    ['Dip', BW_VERTICAL],
    ['Bodyweight Squat', BW_LOWER],
    ['Reverse Lunge', BW_LOWER],
    ['Box Jump', BW_LOWER],
    ['Depth Jump', BW_LOWER],
    ['Sprint 40m', BW_LOWER],
    ['Burpee', BW_LOWER],
    ['Push-up', BW_HORIZONTAL],
    ['Inverted Row', BW_HORIZONTAL],
    ['Plank', BW_HORIZONTAL],
  ])('%s → expected kind', (name, expected) => {
    expect(getSRThresholdsBw(name)).toEqual(expected)
  })

  it('vertical takes precedence over lower (pull beats squat-family)', () => {
    // 'pull' matches before the lower-body rule — matches old ordering.
    expect(getSRThresholdsBw('Pull-up')).toEqual(BW_VERTICAL)
  })
})

describe('inferBwStrengthFraction — name fallback (behavior-preserving)', () => {
  it.each([
    ['Pull-up', 1.0],
    ['Chin-up', 1.0],
    ['Dip', 0.95],
    ['Push-up', 0.64],
    ['Inverted Row', 0.65],
    ['Australian Pull', 1.0], // 'pull' wins before 'australian' (old order)
    ['Inverted Row Australian', 0.65],
    ['Bodyweight Squat', 1.0], // squat && !jump
    ['Pistol Squat', 1.0], // squat && !jump
    ['Jump Squat', 1.0], // squat && jump → falls to jump rule → 1.0
    ['Good Morning', 0.45],
    ['Reverse Lunge', 0.88],
    ['Box Jump', 1.0],
    ['Lateral Bound', 1.0],
    ['Depth Jump', 1.0],
    ['Burpee', 0.72],
    ['Sprint 40m', 0.85],
    ['Bear Crawl', 0.7], // nothing matches → fallback
    ['Glute Bridge', 0.7], // fallback
  ])('%s → fraction %d', (name, expected) => {
    expect(inferBwStrengthFraction(name)).toBeCloseTo(expected, 5)
  })

  it('squat compound branch: pistol squat stays 1.0, jump squat routes to jump', () => {
    expect(inferBwStrengthFraction('Pistol Squat')).toBe(1.0)
    expect(inferBwStrengthFraction('Jump Squat')).toBe(1.0)
  })
})

describe('srToLP wiring still selects the data-driven bands', () => {
  it('uses WEIGHTED bands for a default weighted exercise', () => {
    // SR exactly at a band boundary → deterministic LP via the chosen table.
    const lp = srToLP(0.85, 'Dumbbell Curl', 'WEIGHTED')
    expect(lp).toBe(200) // DEFAULT_W[2] = 0.85 → tier index 2, 0 progress
  })

  it('uses BW vertical bands for a pull-up under BW_REPS', () => {
    const lp = srToLP(0.82, 'Pull-up', 'BW_REPS')
    expect(lp).toBe(200) // BW_VERTICAL[2] = 0.82 → tier index 2
  })
})
