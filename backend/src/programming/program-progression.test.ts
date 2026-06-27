import { describe, it, expect } from 'vitest'
import {
  fiveThreeOneMainWave,
  bbbSupplemental,
  resolveWave,
  percentSetsFromTM,
  trainingMaxFromOneRm,
  incrementTrainingMax,
  NSUNS_T1,
  NSUNS_T2,
} from './program-progression'

describe('5/3/1 main wave', () => {
  it('week 1 is the 5s wave with a top AMRAP', () => {
    const w = fiveThreeOneMainWave(1)
    expect(w.map((s) => s.pct)).toEqual([0.65, 0.75, 0.85])
    expect(w.map((s) => s.reps)).toEqual([5, 5, 5])
    expect(w[2].amrap).toBe(true)
  })

  it('week 3 tops at 95% × 1+', () => {
    const w = fiveThreeOneMainWave(3)
    expect(w[2]).toMatchObject({ pct: 0.95, reps: 1, amrap: true })
  })

  it('week 4 is a deload — no AMRAP, light loads', () => {
    const w = fiveThreeOneMainWave(4)
    expect(w.some((s) => s.amrap)).toBe(false)
    expect(Math.max(...w.map((s) => s.pct))).toBeLessThanOrEqual(0.6)
  })

  it('cycles every 4 weeks (week 5 === week 1)', () => {
    expect(fiveThreeOneMainWave(5)).toEqual(fiveThreeOneMainWave(1))
    expect(fiveThreeOneMainWave(8)).toEqual(fiveThreeOneMainWave(4))
  })
})

describe('BBB supplemental', () => {
  it('is 5×10 at 50% by default', () => {
    const s = bbbSupplemental()
    expect(s).toHaveLength(5)
    expect(s.every((x) => x.pct === 0.5 && x.reps === 10)).toBe(true)
  })
})

describe('nSuns set shapes', () => {
  it('T1 has 9 sets with two AMRAP sets', () => {
    expect(NSUNS_T1).toHaveLength(9)
    expect(NSUNS_T1.filter((s) => s.amrap)).toHaveLength(2)
    expect(NSUNS_T1[2]).toMatchObject({ pct: 0.95, reps: 1, amrap: true })
  })

  it('T2 has 8 sets ending in an AMRAP', () => {
    expect(NSUNS_T2).toHaveLength(8)
    expect(NSUNS_T2[7].amrap).toBe(true)
  })

  it('resolveWave maps names to schemes', () => {
    expect(resolveWave('nsuns_t1', 1)).toEqual(NSUNS_T1)
    expect(resolveWave('531_main', 3)).toEqual(fiveThreeOneMainWave(3))
    expect(resolveWave('unknown', 1)).toEqual([])
  })
})

describe('percentSetsFromTM', () => {
  it('rounds each set to a plate from the training max', () => {
    // TM 100kg, 5/3/1 week 1 → 65/75/85 → plate-rounded.
    const sets = percentSetsFromTM(100, fiveThreeOneMainWave(1))
    expect(sets.map((s) => s.weightKg)).toEqual([65, 75, 85])
    expect(sets[2]).toMatchObject({ tag: 'WORK', amrap: true, pctOfTM: 0.85 })
  })

  it('returns null weights when TM is unknown', () => {
    const sets = percentSetsFromTM(null, NSUNS_T2)
    expect(sets.every((s) => s.weightKg === null)).toBe(true)
    expect(sets).toHaveLength(8)
  })

  it('plate-rounds awkward fractions (TM 102.5 × 0.63)', () => {
    const sets = percentSetsFromTM(102.5, [{ pct: 0.63, reps: 5 }])
    // 102.5 * 0.63 = 64.575 → nearest 2.5 = 65
    expect(sets[0].weightKg).toBe(65)
  })
})

describe('training max lifecycle', () => {
  it('seeds TM at 90% of 1RM, plate-rounded', () => {
    expect(trainingMaxFromOneRm(100)).toBe(90)
    expect(trainingMaxFromOneRm(0)).toBe(0)
  })

  it('increments +5kg lower / +2.5kg upper per cycle', () => {
    expect(incrementTrainingMax(100, true)).toBe(105)
    expect(incrementTrainingMax(100, false)).toBe(102.5)
  })
})
