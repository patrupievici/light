import { describe, expect, it } from 'vitest'
import { heuristicWeightKg } from './workout-generator.service'

describe('heuristicWeightKg', () => {
  it('uses the canonical movement-pattern vocabulary', () => {
    expect(heuristicWeightKg({
      pattern: 'horizontal_push',
      equipment: 'barbell',
      bodyweightKg: 80,
      trainingLevel: 'beginner',
    })).toBe(32.5)
    expect(heuristicWeightKg({
      pattern: 'vertical_pull',
      equipment: 'cable',
      bodyweightKg: 80,
      trainingLevel: 'beginner',
    })).toBe(17.5)
  })

  it('returns zero for bodyweight and no-load exercises', () => {
    expect(heuristicWeightKg({
      pattern: 'vertical_pull',
      equipment: 'bodyweight',
      bodyweightKg: 80,
      trainingLevel: 'intermediate',
    })).toBe(0)
    expect(heuristicWeightKg({
      pattern: 'core_anti_extension',
      equipment: 'none',
      bodyweightKg: 80,
      trainingLevel: 'intermediate',
    })).toBe(0)
  })
})
