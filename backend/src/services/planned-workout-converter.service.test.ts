import { describe, expect, it } from 'vitest'
import { buildPlannedSeedSets } from './planned-workout-converter.service'

describe('buildPlannedSeedSets', () => {
  it('places warmups before uniform work sets', () => {
    expect(buildPlannedSeedSets({
      sets: 2,
      reps: 8,
      suggestedWeightKg: 40,
      warmups: [{ weightKg: 20, reps: 5 }],
    })).toEqual([
      { weightKg: 20, reps: 5, tag: 'WARMUP' },
      { weightKg: 40, reps: 8, tag: 'WORK' },
      { weightKg: 40, reps: 8, tag: 'WORK' },
    ])
  })

  it('preserves explicit percentage-wave targets', () => {
    expect(buildPlannedSeedSets({
      sets: 5,
      reps: 10,
      suggestedWeightKg: 100,
      setsDetail: [{ weightKg: 60, reps: 5 }, { weightKg: 70, reps: 3 }],
    })).toEqual([
      { weightKg: 60, reps: 5, tag: 'WORK' },
      { weightKg: 70, reps: 3, tag: 'WORK' },
    ])
  })

  it('sanitizes invalid values before writing set rows', () => {
    expect(buildPlannedSeedSets({ sets: 99, reps: -2, suggestedWeightKg: -10 })).toHaveLength(12)
    expect(buildPlannedSeedSets({ sets: 1, reps: -2, suggestedWeightKg: -10 })[0]).toEqual({
      weightKg: 0,
      reps: 1,
      tag: 'WORK',
    })
  })
})
