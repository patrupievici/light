import { describe, it, expect } from 'vitest'
import { svgSlugForMuscle, computeMuscleLevel, SVG_SLUGS, MUSCLE_TO_SVG_SLUG } from './muscle-levels'

describe('svgSlugForMuscle bridge', () => {
  it('maps canonical + free-text muscles to Flutter SVG slugs', () => {
    expect(svgSlugForMuscle('chest')).toBe('chest')
    expect(svgSlugForMuscle('shoulders')).toBe('deltoids') // shoulders → side_delts → deltoids
    expect(svgSlugForMuscle('Rear Delts')).toBe('deltoids')
    expect(svgSlugForMuscle('quads')).toBe('quadriceps')
    expect(svgSlugForMuscle('back')).toBe('upper-back') // back → upper_back → upper-back
    expect(svgSlugForMuscle('lats')).toBe('upper-back')
    expect(svgSlugForMuscle('hamstrings')).toBe('hamstring')
    expect(svgSlugForMuscle('glutes')).toBe('gluteal')
    expect(svgSlugForMuscle('traps')).toBe('trapezius')
    expect(svgSlugForMuscle('forearm')).toBe('forearm')
  })

  it('returns null for muscles with no SVG region or garbage', () => {
    expect(svgSlugForMuscle('abductors')).toBeNull()
    expect(svgSlugForMuscle('neck')).toBeNull()
    expect(svgSlugForMuscle('not a muscle')).toBeNull()
    expect(svgSlugForMuscle(null)).toBeNull()
  })

  it('renders exactly the 15 SVG slugs the Flutter map draws', () => {
    expect(SVG_SLUGS).toHaveLength(15)
    expect(SVG_SLUGS).toEqual(
      expect.arrayContaining([
        'chest', 'deltoids', 'triceps', 'upper-back', 'lower-back', 'biceps',
        'forearm', 'trapezius', 'abs', 'obliques', 'quadriceps', 'hamstring',
        'gluteal', 'calves', 'adductors',
      ]),
    )
    // every canonical muscle maps to a slug or null (no missing keys)
    expect(Object.keys(MUSCLE_TO_SVG_SLUG)).toContain('hip_flexors')
  })
})

describe('computeMuscleLevel', () => {
  it('is 0 for an untrained muscle', () => {
    expect(computeMuscleLevel(0, 0)).toEqual({ level: 0, volumeLevel: 0, strengthBonus: 0 })
    expect(computeMuscleLevel(0, 500).level).toBe(0)
  })

  it('climbs on a sqrt volume curve', () => {
    expect(computeMuscleLevel(2000, 0)).toMatchObject({ volumeLevel: 1, level: 1 })
    expect(computeMuscleLevel(8000, 0).volumeLevel).toBe(2)
    expect(computeMuscleLevel(50000, 0).volumeLevel).toBe(5)
  })

  it('adds a strength bonus from the muscle LP (capped at 6)', () => {
    const r = computeMuscleLevel(50000, 350) // vol 5 + bonus 3
    expect(r.strengthBonus).toBe(3)
    expect(r.level).toBe(8)
    expect(computeMuscleLevel(2000, 700).strengthBonus).toBe(6) // clamp
  })

  it('a freshly-trained muscle is at least level 1', () => {
    expect(computeMuscleLevel(500, 0).level).toBe(1) // sqrt(0.25)=0 → max(1, 0)
  })
})
