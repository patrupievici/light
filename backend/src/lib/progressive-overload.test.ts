import { describe, it, expect } from 'vitest'

import {
  autoregulateLoad,
  bumpForLevel,
  roundToPlate,
  isDeloadWeek,
  applyBlockDeload,
  DEFAULT_DELOAD_CADENCE,
  BLOCK_DELOAD_MIN_SETS,
} from './progressive-overload'

// `computeProgressiveLoads` hits Prisma — these tests cover the pure decision
// helpers that drive the bump amount, which are the part most likely to
// regress accidentally.

describe('bumpForLevel — compound lifts', () => {
  it('beginners get +2.5kg flat per session', () => {
    expect(bumpForLevel('beginner', true, 100)).toBe(2.5)
    // Last weight doesn't matter for compound beginner progression
    expect(bumpForLevel('beginner', true, 200)).toBe(2.5)
  })

  it('intermediate lifters get +1.25kg flat', () => {
    expect(bumpForLevel('intermediate', true, 100)).toBe(1.25)
  })

  it('advanced lifters get 0 — they need block periodization, not linear bumps', () => {
    expect(bumpForLevel('advanced', true, 200)).toBe(0)
  })
})

describe('bumpForLevel — accessory lifts (percentage-based)', () => {
  it('beginners get 2.5% with a 1.25kg floor', () => {
    // 100kg * 2.5% = 2.5kg
    expect(bumpForLevel('beginner', false, 100)).toBe(2.5)
    // 20kg * 2.5% = 0.5 → clamped to 1.25
    expect(bumpForLevel('beginner', false, 20)).toBe(1.25)
    // 50kg * 2.5% = 1.25 (exactly at the floor)
    expect(bumpForLevel('beginner', false, 50)).toBe(1.25)
  })

  it('intermediate gets 1% with no floor', () => {
    expect(bumpForLevel('intermediate', false, 100)).toBe(1.0)
    expect(bumpForLevel('intermediate', false, 50)).toBe(0.5)
  })

  it('advanced gets 0 on accessories too', () => {
    expect(bumpForLevel('advanced', false, 100)).toBe(0)
  })
})

describe('roundToPlate', () => {
  it('rounds to nearest 2.5 kg step', () => {
    expect(roundToPlate(100)).toBe(100)
    expect(roundToPlate(101)).toBe(100)
    expect(roundToPlate(101.3)).toBe(102.5)
    expect(roundToPlate(103.75)).toBe(105) // halfway rounds up
  })

  it('enforces a 5 kg minimum (no "load the bar with 2.5kg")', () => {
    expect(roundToPlate(0)).toBe(5)
    expect(roundToPlate(2)).toBe(5)
    expect(roundToPlate(4.9)).toBe(5)
  })

  it('handles fractional inputs with float-precision safety', () => {
    // 102.5 + 0.0000001 should still come back as 102.5
    expect(roundToPlate(102.50000001)).toBe(102.5)
  })

  it('round trip: progressive bump → plate-safe weight', () => {
    // beginner compound, last weight 100 → +2.5 → 102.5 (exact plate, no rounding)
    const next = roundToPlate(100 + bumpForLevel('beginner', true, 100))
    expect(next).toBe(102.5)
    // intermediate compound, last 100 → +1.25 → 101.25, rounds UP to 102.5
    // (JS Math.round rounds 0.5 away from zero; 101.25/2.5 = 40.5 → 41 → 102.5).
    // This is the expected behavior: micro-plate progressions still land on a
    // standard 2.5kg step so the bar is loadable.
    const nextInt = roundToPlate(100 + bumpForLevel('intermediate', true, 100))
    expect(nextInt).toBe(102.5)
    // advanced compound — bump is 0, weight stays plate-safe at 100
    expect(roundToPlate(100 + bumpForLevel('advanced', true, 100))).toBe(100)
  })
})

describe('autoregulateLoad — RPE-gated progression', () => {
  const base = { level: 'beginner' as const, isCompound: true, lastWeight: 100, lastReps: 5 }

  it('no RPE logged → plain linear bump (preserves prior behavior)', () => {
    const d = autoregulateLoad({ ...base, lastRpe: null })
    expect(d.source).toBe('progression')
    expect(d.suggestedWeightKg).toBe(102.5) // 100 + 2.5 beginner compound
  })

  it('easy set (RPE ≤ 6) → accelerated jump (1.5×)', () => {
    const d = autoregulateLoad({ ...base, lastRpe: 6.0 })
    expect(d.source).toBe('progression')
    // 100 + 2.5*1.5 = 103.75 → roundToPlate → 105
    expect(d.suggestedWeightKg).toBe(105)
    expect(d.reason).toMatch(/bigger jump/i)
  })

  it('manageable set (6 < RPE ≤ 8) → normal bump', () => {
    const d = autoregulateLoad({ ...base, lastRpe: 7.5 })
    expect(d.source).toBe('progression')
    expect(d.suggestedWeightKg).toBe(102.5)
  })

  it('hard set (8 < RPE < 9.5) → hold, no load added', () => {
    const d = autoregulateLoad({ ...base, lastRpe: 8.5 })
    expect(d.source).toBe('hold')
    expect(d.suggestedWeightKg).toBe(100)
  })

  it('near failure (RPE ≥ 9.5) → deload −10%', () => {
    const d = autoregulateLoad({ ...base, lastRpe: 9.5 })
    expect(d.source).toBe('deload')
    expect(d.suggestedWeightKg).toBe(90) // 100 * 0.9
  })

  it('RPE 10 (true failure) also deloads', () => {
    const d = autoregulateLoad({ ...base, lastRpe: 10 })
    expect(d.source).toBe('deload')
    expect(d.suggestedWeightKg).toBe(90)
  })

  it('advanced compound never adds linear load, even when easy', () => {
    const d = autoregulateLoad({ ...base, level: 'advanced', lastRpe: 5.0 })
    expect(d.source).toBe('progression')
    expect(d.suggestedWeightKg).toBe(100) // held — no bump for advanced
  })

  it('accessory easy set accelerates off the percentage bump', () => {
    // intermediate accessory 100kg → base 1.0kg; easy → 1.5kg → 101.5 → plate 102.5
    const d = autoregulateLoad({ level: 'intermediate', isCompound: false, lastWeight: 100, lastReps: 12, lastRpe: 5.5 })
    expect(d.source).toBe('progression')
    expect(d.suggestedWeightKg).toBe(102.5)
  })

  it('deload rounds to a loadable plate (min 5kg)', () => {
    const d = autoregulateLoad({ ...base, lastWeight: 20, lastReps: 5, lastRpe: 9.8 })
    expect(d.source).toBe('deload')
    // 20 * 0.9 = 18 → roundToPlate → 17.5 (nearest 2.5 step)
    expect(d.suggestedWeightKg).toBe(17.5)
  })
})

describe('isDeloadWeek — block periodization cadence (numeric index)', () => {
  it('default cadence 4: weeks 0,1,2 train, week 3 deloads, then repeats', () => {
    expect(isDeloadWeek(0)).toBe(false)
    expect(isDeloadWeek(1)).toBe(false)
    expect(isDeloadWeek(2)).toBe(false)
    expect(isDeloadWeek(3)).toBe(true) // 4th training week
    expect(isDeloadWeek(4)).toBe(false)
    expect(isDeloadWeek(7)).toBe(true) // 8th
    expect(isDeloadWeek(11)).toBe(true) // 12th
  })

  it('exposes the default cadence as 4', () => {
    expect(DEFAULT_DELOAD_CADENCE).toBe(4)
  })

  it('honors a custom cadence (every 3rd week)', () => {
    expect(isDeloadWeek(2, 3)).toBe(true)
    expect(isDeloadWeek(5, 3)).toBe(true)
    expect(isDeloadWeek(3, 3)).toBe(false)
  })

  it('never opens a brand-new program on a deload (negative / pre-start index)', () => {
    expect(isDeloadWeek(-1)).toBe(false)
    expect(isDeloadWeek(-4)).toBe(false)
  })

  it('disables cadence < 2 (would deload every week or never) and non-finite', () => {
    expect(isDeloadWeek(3, 1)).toBe(false)
    expect(isDeloadWeek(3, 0)).toBe(false)
    expect(isDeloadWeek(3, Number.NaN)).toBe(false)
  })

  it('floors fractional indices to whole weeks', () => {
    expect(isDeloadWeek(3.9)).toBe(true) // floors to 3
    expect(isDeloadWeek(2.9)).toBe(false) // floors to 2
  })
})

describe('isDeloadWeek — date-pair derivation', () => {
  const start = new Date('2026-01-05T00:00:00Z')
  const plusWeeks = (n: number) => new Date(start.getTime() + n * 7 * 86_400_000)

  it('derives the whole-week index between start and current', () => {
    expect(isDeloadWeek({ start, current: start })).toBe(false) // week 0
    expect(isDeloadWeek({ start, current: plusWeeks(3) })).toBe(true) // week 3 → deload
    expect(isDeloadWeek({ start, current: plusWeeks(4) })).toBe(false)
    expect(isDeloadWeek({ start, current: plusWeeks(7) })).toBe(true)
  })

  it('floors partial weeks (6 days in is still week 0)', () => {
    const sixDays = new Date(start.getTime() + 6 * 86_400_000)
    expect(isDeloadWeek({ start, current: sixDays })).toBe(false)
    const fourWeeksMinusADay = new Date(plusWeeks(4).getTime() - 86_400_000)
    // 27 days → floor(27/7)=3 → deload
    expect(isDeloadWeek({ start, current: fourWeeksMinusADay })).toBe(true)
  })

  it('returns false for invalid dates', () => {
    expect(isDeloadWeek({ start: new Date('nope'), current: start })).toBe(false)
    expect(isDeloadWeek({ start, current: new Date('nope') })).toBe(false)
  })

  it('returns false when current is before start (negative index)', () => {
    expect(isDeloadWeek({ start, current: plusWeeks(-3) })).toBe(false)
  })
})

describe('applyBlockDeload — back-off transform', () => {
  const normal = {
    suggestedWeightKg: 100,
    sets: 4,
    reason: '+2.5kg progression',
    source: 'progression' as const,
  }

  it('is a no-op (behavior-preserving) when deload=false', () => {
    const r = applyBlockDeload(normal, false)
    expect(r).toEqual({
      suggestedWeightKg: 100,
      sets: 4,
      source: 'progression',
      reason: '+2.5kg progression',
    })
  })

  it('cuts load ~−12% (plate-rounded) on a deload week', () => {
    const r = applyBlockDeload(normal, true)
    // 100 * 0.88 = 88 → nearest 2.5 plate → 87.5
    expect(r.suggestedWeightKg).toBe(87.5)
    expect(r.suggestedWeightKg!).toBeGreaterThanOrEqual(100 * 0.85)
    expect(r.suggestedWeightKg!).toBeLessThanOrEqual(100 * 0.9)
  })

  it('trims one working set, floored at the minimum', () => {
    expect(applyBlockDeload({ ...normal, sets: 4 }, true).sets).toBe(3)
    expect(applyBlockDeload({ ...normal, sets: 2 }, true).sets).toBe(BLOCK_DELOAD_MIN_SETS)
    expect(applyBlockDeload({ ...normal, sets: 1 }, true).sets).toBe(BLOCK_DELOAD_MIN_SETS)
  })

  it('forces source=deload, suppressing the progression bump', () => {
    const r = applyBlockDeload(normal, true)
    expect(r.source).toBe('deload')
    expect(r.reason).toMatch(/Deload week/i)
  })

  it('suppresses even an advanced lifter who got 0 weekly bump (the key case)', () => {
    // Advanced lifter: progression held them at the same load (bump 0). Without a
    // scheduled deload they'd grind 120kg forever; the block deload backs it off.
    const advancedHeld = { suggestedWeightKg: 120, sets: 5, reason: 'held — advanced', source: 'progression' as const }
    const r = applyBlockDeload(advancedHeld, true)
    expect(r.source).toBe('deload')
    expect(r.suggestedWeightKg).toBeLessThan(120)
    expect(r.sets).toBe(4)
  })

  it('keeps null weight for bodyweight/no-history lifts but still deloads volume + reason', () => {
    const bw = { suggestedWeightKg: null, sets: 4, reason: 'bodyweight', source: 'no_history' as const }
    const r = applyBlockDeload(bw, true)
    expect(r.suggestedWeightKg).toBeNull()
    expect(r.sets).toBe(3)
    expect(r.source).toBe('deload')
    expect(r.reason).toMatch(/Deload week/i)
  })

  it('deloaded load stays a loadable plate (min 5kg)', () => {
    const light = { suggestedWeightKg: 6, sets: 3, reason: 'x', source: 'progression' as const }
    const r = applyBlockDeload(light, true)
    // 6 * 0.88 = 5.28 → plate 5
    expect(r.suggestedWeightKg).toBe(5)
  })
})
