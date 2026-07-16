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

  it('caps a four-set prescription plus warmups at five total rows', () => {
    const sets = buildPlannedSeedSets({
      sets: 4,
      reps: 8,
      suggestedWeightKg: 60,
      warmups: [
        { weightKg: 20, reps: 8 },
        { weightKg: 25, reps: 5 },
        { weightKg: 35, reps: 3 },
        { weightKg: 47.5, reps: 2 },
      ],
    })

    expect(sets).toHaveLength(5)
    expect(sets.filter((set) => set.tag === 'WARMUP')).toEqual([
      { weightKg: 47.5, reps: 2, tag: 'WARMUP' },
    ])
    expect(sets.filter((set) => set.tag === 'WORK')).toHaveLength(4)
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

  it('samples oversized percentage waves without dropping the final set', () => {
    const setsDetail = Array.from({ length: 9 }, (_, index) => ({
      weightKg: 50 + index * 2.5,
      reps: index + 1,
    }))
    const sets = buildPlannedSeedSets({ setsDetail })

    expect(sets).toHaveLength(5)
    expect(sets.map((set) => set.reps)).toEqual([1, 3, 5, 7, 9])
  })

  it('sanitizes invalid values before writing set rows', () => {
    expect(buildPlannedSeedSets({ sets: 99, reps: -2, suggestedWeightKg: -10 })).toHaveLength(5)
    expect(buildPlannedSeedSets({ sets: 1, reps: -2, suggestedWeightKg: -10 })[0]).toEqual({
      weightKg: 0,
      reps: 1,
      tag: 'WORK',
    })
  })
})
