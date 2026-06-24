import { describe, it, expect } from 'vitest'

import { generateWarmupSets, isRampableLift } from './warmup'

const COMPOUND = { movementPattern: 'squat', rankModel: 'WEIGHTED', category: 'strength' }

describe('isRampableLift', () => {
  it('accepts weighted compound movement patterns', () => {
    expect(isRampableLift({ movementPattern: 'squat', rankModel: 'WEIGHTED' })).toBe(true)
    expect(isRampableLift({ movementPattern: 'hinge', rankModel: 'WEIGHTED' })).toBe(true)
    expect(isRampableLift({ movementPattern: 'horizontal_push' })).toBe(true)
    expect(isRampableLift({ movementPattern: 'vertical_pull' })).toBe(true)
  })

  it('rejects accessory / isolation patterns', () => {
    expect(isRampableLift({ movementPattern: 'elbow_flexion', rankModel: 'WEIGHTED' })).toBe(false)
    expect(isRampableLift({ movementPattern: 'skill_stability' })).toBe(false)
    expect(isRampableLift({ movementPattern: '' })).toBe(false)
    expect(isRampableLift({})).toBe(false)
  })

  it('rejects bodyweight / timed lifts even on a compound pattern', () => {
    expect(isRampableLift({ movementPattern: 'vertical_pull', rankModel: 'BW_REPS' })).toBe(false)
    expect(isRampableLift({ movementPattern: 'squat', rankModel: 'TIME' })).toBe(false)
    expect(isRampableLift({ movementPattern: 'squat', category: 'bodyweight' })).toBe(false)
    expect(isRampableLift({ movementPattern: 'squat', category: 'cardio' })).toBe(false)
  })
})

describe('generateWarmupSets — skipping', () => {
  it('returns [] for non-compound lifts', () => {
    expect(generateWarmupSets(100, { movementPattern: 'elbow_flexion' })).toEqual([])
  })

  it('returns [] for bodyweight lifts', () => {
    expect(generateWarmupSets(80, { movementPattern: 'vertical_pull', rankModel: 'BW_REPS' })).toEqual([])
  })

  it('returns [] for missing / non-positive working weight', () => {
    expect(generateWarmupSets(0, COMPOUND)).toEqual([])
    expect(generateWarmupSets(-50, COMPOUND)).toEqual([])
    expect(generateWarmupSets(Number.NaN, COMPOUND)).toEqual([])
  })
})

describe('generateWarmupSets — ramp shape', () => {
  it('produces an ascending load ramp with descending reps for a heavy squat', () => {
    const sets = generateWarmupSets(100, COMPOUND)
    // empty bar (20) + 40% + 60% + 80% = 4 steps
    expect(sets).toHaveLength(4)
    expect(sets.map((s) => s.weightKg)).toEqual([20, 40, 60, 80])
    // every step tagged WARMUP
    expect(sets.every((s) => s.tag === 'WARMUP')).toBe(true)
    // ascending load
    const weights = sets.map((s) => s.weightKg)
    expect([...weights].sort((a, b) => a - b)).toEqual(weights)
    // reps: primer high, percentage steps descend 5/3/2
    expect(sets.map((s) => s.reps)).toEqual([8, 5, 3, 2])
  })

  it('plate-rounds every step to the 2.5kg gym step', () => {
    // 142.5kg working: 40%=57 -> 57.5, 60%=85.5 -> 85, 80%=114 -> 115
    const sets = generateWarmupSets(142.5, COMPOUND)
    for (const s of sets) {
      expect(Math.round((s.weightKg / 2.5) * 1000) / 1000 % 1).toBe(0)
    }
    expect(sets.map((s) => s.weightKg)).toEqual([20, 57.5, 85, 115])
  })

  it('honors a custom empty-bar weight and dropping the primer', () => {
    const withBar = generateWarmupSets(100, { ...COMPOUND, barWeightKg: 15 })
    expect(withBar[0].weightKg).toBe(15)
    const noBar = generateWarmupSets(100, { ...COMPOUND, barWeightKg: 0 })
    expect(noBar.map((s) => s.weightKg)).toEqual([40, 60, 80])
  })

  it('records the working-weight fraction each step targets', () => {
    const sets = generateWarmupSets(100, { ...COMPOUND, barWeightKg: 0 })
    expect(sets.map((s) => s.percentOfWorking)).toEqual([0.4, 0.6, 0.8])
  })
})

describe('generateWarmupSets — low-weight edge cases', () => {
  it('drops ramp steps that meet/exceed the working weight (no warming up at the work load)', () => {
    // 25kg working: 80% = 20 -> rounds to 20, but gap (2.5) means ceiling 22.5,
    // so 20 is allowed; 60% = 15, 40% = 10; empty bar 20. Dedup keeps unique.
    const sets = generateWarmupSets(25, COMPOUND)
    // none may be >= working weight (with the gap)
    expect(sets.every((s) => s.weightKg <= 25 - 2.5)).toBe(true)
  })

  it('dedupes when plate rounding collapses several steps onto one load', () => {
    // Very light working weight: roundToPlate floor is 5kg, so multiple low
    // percentages can collapse. Result must have strictly unique ascending loads.
    const sets = generateWarmupSets(12, COMPOUND)
    const weights = sets.map((s) => s.weightKg)
    expect(new Set(weights).size).toBe(weights.length)
    expect([...weights].sort((a, b) => a - b)).toEqual(weights)
    // none at or above the working weight minus gap
    expect(weights.every((w) => w <= 12 - 2.5)).toBe(true)
  })

  it('can return an empty ramp when the working weight is too light to ramp', () => {
    // working 6kg: ceiling 3.5; roundToPlate floor is 5 -> every candidate >3.5
    const sets = generateWarmupSets(6, COMPOUND)
    expect(sets).toEqual([])
  })
})
