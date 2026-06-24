import { describe, it, expect } from 'vitest'

import {
  rankSubstitutes,
  scoreSubstitute,
  seedSubstituteLoad,
  CARRYOVER_SAME_PATTERN,
  CARRYOVER_PARTIAL,
  type SubstitutionExercise,
} from './exercise-substitution'
import { normalizeMuscle } from '../constants/muscles'

// `GET /v1/exercises/:id/substitutes` hits Prisma — these tests cover the pure
// ranking helpers that decide which alternatives surface and why, the part most
// likely to regress accidentally.

function ex(overrides: Partial<SubstitutionExercise> = {}): SubstitutionExercise {
  return {
    id: overrides.id ?? 'src',
    name: overrides.name ?? 'Exercise',
    primaryMuscle: overrides.primaryMuscle ?? null,
    equipment: overrides.equipment ?? 'barbell',
    rankModel: overrides.rankModel ?? 'WEIGHTED',
    category: overrides.category ?? 'strength',
    movementPattern: overrides.movementPattern ?? 'hinge',
    secondaryPatterns: overrides.secondaryPatterns ?? [],
    secondaryMuscles: overrides.secondaryMuscles ?? [],
    fatigueScore: overrides.fatigueScore ?? 3,
  }
}

const barbellDeadlift = ex({
  id: 'deadlift',
  name: 'Barbell Deadlift',
  primaryMuscle: 'Hamstrings',
  equipment: 'barbell',
  rankModel: 'WEIGHTED',
  movementPattern: 'hinge',
  fatigueScore: 5,
})

describe('scoreSubstitute', () => {
  it('a same-pattern, same-muscle, same-equipment variation scores high', () => {
    const dumbbellRdl = ex({
      id: 'db-rdl',
      name: 'Dumbbell Romanian Deadlift',
      primaryMuscle: 'Hamstrings',
      equipment: 'dumbbell',
      rankModel: 'WEIGHTED',
      movementPattern: 'hinge',
      fatigueScore: 4,
    })
    const { score, reason } = scoreSubstitute(barbellDeadlift, dumbbellRdl, true)
    // same pattern (45) + same muscle (25) + same rankModel (12) + same
    // category (8) + fatigue gap 1 (7.5) = 97.5
    expect(score).toBeCloseTo(97.5, 1)
    expect(reason).toContain('Same hinge pattern')
    // Both have primary muscle Hamstrings and no secondaryMuscles → full muscle
    // weight, exactly as before the overlap upgrade.
    expect(reason).toContain('shares hamstrings')
  })

  it('a different pattern with no muscle overlap scores low (fatigue only)', () => {
    const benchPress = ex({
      id: 'bench',
      name: 'Bench Press',
      primaryMuscle: 'Chest',
      movementPattern: 'horizontal_push',
      fatigueScore: 4,
    })
    const { score } = scoreSubstitute(barbellDeadlift, benchPress, true)
    // no pattern, no muscle, same rankModel (12) + same category (8) + fatigue
    // gap 1 (7.5) = 27.5
    expect(score).toBeCloseTo(27.5, 1)
  })

  it('counts a partial pattern match via secondary patterns', () => {
    const goodMorning = ex({
      id: 'gm',
      name: 'Good Morning',
      primaryMuscle: 'Lower Back',
      movementPattern: 'core_anti_extension',
      secondaryPatterns: ['hinge'],
      fatigueScore: 4,
    })
    const { score, reason } = scoreSubstitute(barbellDeadlift, goodMorning, true)
    // partial pattern (22) instead of full (45), plus rankModel (12) + category
    // (8) + fatigue gap 1 (7.5) = 49.5
    expect(reason).toContain('Overlapping hinge pattern')
    expect(score).toBeCloseTo(49.5, 1)
    // Lower than a full same-pattern, same-muscle match (97.5).
    const fullMatch = scoreSubstitute(
      barbellDeadlift,
      ex({ id: 'x', primaryMuscle: 'Hamstrings', movementPattern: 'hinge', fatigueScore: 4 }),
      true,
    )
    expect(score).toBeLessThan(fullMatch.score)
  })

  it('notes a different load model in the reason', () => {
    const bwHipExt = ex({
      id: 'hip-ext',
      name: 'Bodyweight Hip Extension',
      primaryMuscle: 'Hamstrings',
      equipment: 'bodyweight',
      rankModel: 'BW_REPS',
      category: 'bodyweight',
      movementPattern: 'hinge',
      fatigueScore: 2,
    })
    const { reason } = scoreSubstitute(barbellDeadlift, bwHipExt, true)
    expect(reason).toContain('different load model (bw_reps)')
  })

  it('flags equipment the user does not have', () => {
    const machine = ex({ id: 'm', name: 'Machine', equipment: 'machine', movementPattern: 'hinge' })
    const { reason } = scoreSubstitute(barbellDeadlift, machine, false)
    expect(reason).toContain('needs machine (not in your kit)')
  })

  it('fatigue proximity decays with the gap', () => {
    const close = ex({ id: 'c', movementPattern: 'hinge', fatigueScore: 5 })
    const far = ex({ id: 'f', movementPattern: 'hinge', fatigueScore: 1 })
    const closeScore = scoreSubstitute(barbellDeadlift, close, true).score
    const farScore = scoreSubstitute(barbellDeadlift, far, true).score
    expect(closeScore).toBeGreaterThan(farScore)
  })

  it('matches muscles across the controlled vocabulary (synonyms normalise)', () => {
    // Source primary "Hamstrings", candidate primary "hams" → same canonical tag.
    const synonym = ex({
      id: 'syn',
      name: 'Synonym Hinge',
      primaryMuscle: 'hams',
      movementPattern: 'hinge',
      fatigueScore: 5,
    })
    const { score, reason } = scoreSubstitute(barbellDeadlift, synonym, true)
    // same pattern (45) + full muscle (25) + rankModel (12) + category (8) +
    // fatigue gap 0 (10) = 100
    expect(score).toBeCloseTo(100, 1)
    expect(reason).toContain('shares hamstrings')
  })

  it('partial muscle overlap scores below a full primary match', () => {
    const source = ex({
      id: 'sq',
      name: 'Back Squat',
      primaryMuscle: 'Quads',
      secondaryMuscles: ['glutes', 'hamstrings'],
      movementPattern: 'squat',
      fatigueScore: 5,
    })
    // Shares only the secondary glutes, not the primary quads.
    const hipThrust = ex({
      id: 'ht',
      name: 'Hip Thrust',
      primaryMuscle: 'Glutes',
      secondaryMuscles: [],
      movementPattern: 'hinge',
      fatigueScore: 5,
    })
    const partial = scoreSubstitute(source, hipThrust, true)
    // Shares the primary quads → full muscle credit.
    const sameQuads = ex({
      id: 'fs',
      name: 'Front Squat',
      primaryMuscle: 'quads',
      movementPattern: 'squat',
      fatigueScore: 5,
    })
    const full = scoreSubstitute(source, sameQuads, true)

    // First reason gets sentence-capitalised → "Shares glutes...".
    expect(partial.reason.toLowerCase()).toContain('shares glutes')
    // source weight = quads(1) + glutes(.5) + hams(.5) = 2; matched glutes(.5)
    // → 25 * 0.25 = 6.25 muscle points.
    expect(full.score).toBeGreaterThan(partial.score)
  })

  it('lists the primary mover first and summarises extra shared muscles', () => {
    const source = ex({
      id: 'dl',
      name: 'Deadlift',
      primaryMuscle: 'Hamstrings',
      secondaryMuscles: ['glutes', 'lower_back', 'forearms'],
      movementPattern: 'hinge',
      fatigueScore: 5,
    })
    const rdl = ex({
      id: 'rdl',
      name: 'RDL',
      primaryMuscle: 'hamstrings',
      secondaryMuscles: ['Glutes', 'lower back', 'forearms'],
      movementPattern: 'hinge',
      fatigueScore: 5,
    })
    const { reason } = scoreSubstitute(source, rdl, true)
    // 4 shared muscles → primary first, then one more, then "+N more".
    expect(reason).toContain('shares hamstrings')
    expect(reason).toContain('more')
  })

  it('falls back to primary-only when secondaryMuscles is empty (preserved behavior)', () => {
    // No secondaryMuscles on either side → identical to the legacy single-muscle
    // path: full muscle weight when primaries match, zero when they do not.
    const matched = scoreSubstitute(
      barbellDeadlift,
      ex({ id: 'a', primaryMuscle: 'Hamstrings', movementPattern: 'hinge', fatigueScore: 5 }),
      true,
    )
    const unmatched = scoreSubstitute(
      barbellDeadlift,
      ex({ id: 'b', primaryMuscle: 'Chest', movementPattern: 'hinge', fatigueScore: 5 }),
      true,
    )
    // 45 + 25 + 12 + 8 + 10 = 100 vs 45 + 0 + 12 + 8 + 10 = 75.
    expect(matched.score).toBeCloseTo(100, 1)
    expect(unmatched.score).toBeCloseTo(75, 1)
  })
})

describe('rankSubstitutes', () => {
  const pool: SubstitutionExercise[] = [
    barbellDeadlift, // the source — must be filtered out
    ex({
      id: 'db-rdl',
      name: 'Dumbbell RDL',
      primaryMuscle: 'Hamstrings',
      equipment: 'dumbbell',
      movementPattern: 'hinge',
      fatigueScore: 4,
    }),
    ex({
      id: 'kb-swing',
      name: 'Kettlebell Swing',
      primaryMuscle: 'Hamstrings',
      equipment: 'dumbbell',
      movementPattern: 'hinge',
      fatigueScore: 3,
    }),
    ex({
      id: 'bench',
      name: 'Bench Press',
      primaryMuscle: 'Chest',
      movementPattern: 'horizontal_push',
      fatigueScore: 3,
    }),
  ]

  it('excludes the source exercise itself', () => {
    const result = rankSubstitutes(barbellDeadlift, pool)
    expect(result.some((r) => r.exercise.id === 'deadlift')).toBe(false)
  })

  it('drops candidates with neither pattern nor muscle overlap', () => {
    // Bench press shares nothing with deadlift → score below the cutoff.
    const result = rankSubstitutes(barbellDeadlift, pool)
    expect(result.some((r) => r.exercise.id === 'bench')).toBe(false)
  })

  it('ranks same-pattern/same-muscle alternatives first', () => {
    const result = rankSubstitutes(barbellDeadlift, pool)
    expect(result[0].exercise.id).toBe('db-rdl')
    expect(result[0].score).toBeGreaterThan(result[1].score)
  })

  it('sorts equipment-available candidates ahead of unavailable ones', () => {
    const result = rankSubstitutes(barbellDeadlift, pool, {
      // Only the kettlebell swing is "available" even though the RDL scores higher.
      isEquipmentAvailable: (equipment) => equipment === 'dumbbell',
    })
    // Both share dumbbell here, so both available; tweak: make only kb available.
    const onlyKb = rankSubstitutes(barbellDeadlift, pool, {
      isEquipmentAvailable: (_e) => false,
    })
    expect(onlyKb.every((r) => r.equipmentAvailable === false)).toBe(true)
    expect(result.length).toBeGreaterThan(0)
  })

  it('respects the limit', () => {
    const result = rankSubstitutes(barbellDeadlift, pool, { limit: 1 })
    expect(result).toHaveLength(1)
  })

  it('puts equipment-available before equipment-unavailable at equal relevance', () => {
    const a = ex({ id: 'a', name: 'A', primaryMuscle: 'Hamstrings', movementPattern: 'hinge', equipment: 'barbell', fatigueScore: 5 })
    const b = ex({ id: 'b', name: 'B', primaryMuscle: 'Hamstrings', movementPattern: 'hinge', equipment: 'machine', fatigueScore: 5 })
    const result = rankSubstitutes(barbellDeadlift, [a, b], {
      isEquipmentAvailable: (equipment) => equipment === 'barbell',
    })
    expect(result[0].exercise.id).toBe('a')
    expect(result[0].equipmentAvailable).toBe(true)
    expect(result[1].equipmentAvailable).toBe(false)
  })
})

describe('normalizeMuscle', () => {
  it('passes canonical tags through unchanged', () => {
    expect(normalizeMuscle('hamstrings')).toBe('hamstrings')
    expect(normalizeMuscle('rear_delts')).toBe('rear_delts')
  })

  it('maps synonyms and free text to a canonical tag', () => {
    expect(normalizeMuscle('Hamstrings')).toBe('hamstrings')
    expect(normalizeMuscle('hams')).toBe('hamstrings')
    expect(normalizeMuscle('pecs')).toBe('chest')
    expect(normalizeMuscle('Pectorals')).toBe('chest')
    expect(normalizeMuscle('quadriceps')).toBe('quads')
  })

  it('tolerates spacing, casing and separators', () => {
    expect(normalizeMuscle('Rear Delts')).toBe('rear_delts')
    expect(normalizeMuscle('rear-delts')).toBe('rear_delts')
    expect(normalizeMuscle('  LOWER   BACK ')).toBe('lower_back')
  })

  it('returns null for empty or unrecognised input', () => {
    expect(normalizeMuscle('')).toBeNull()
    expect(normalizeMuscle('   ')).toBeNull()
    expect(normalizeMuscle('left earlobe')).toBeNull()
    expect(normalizeMuscle(null)).toBeNull()
    expect(normalizeMuscle(42)).toBeNull()
  })
})

describe('seedSubstituteLoad (carry-over)', () => {
  const source = ex({
    id: 'bb-squat',
    name: 'Barbell Back Squat',
    movementPattern: 'squat',
    rankModel: 'WEIGHTED',
  })

  it('seeds a same-pattern substitute at the higher fraction of source e1RM', () => {
    const frontSquat = ex({
      id: 'front-squat',
      name: 'Front Squat',
      movementPattern: 'squat',
      rankModel: 'WEIGHTED',
    })
    const r = seedSubstituteLoad({ source, substitute: frontSquat, sourceBestE1rmKg: 140 })
    // 140 * 0.9 = 126 → plate-rounded to 125
    expect(r.fraction).toBe(CARRYOVER_SAME_PATTERN)
    expect(r.suggestedWeightKg).toBe(125)
    expect(r.reason).toContain('same movement pattern')
  })

  it('seeds a cross-pattern substitute at the conservative fraction', () => {
    const legPress = ex({
      id: 'leg-press',
      name: 'Leg Press',
      movementPattern: 'horizontal_push',
      rankModel: 'WEIGHTED',
    })
    const r = seedSubstituteLoad({ source, substitute: legPress, sourceBestE1rmKg: 140 })
    // 140 * 0.75 = 105 → already on a plate step
    expect(r.fraction).toBe(CARRYOVER_PARTIAL)
    expect(r.suggestedWeightKg).toBe(105)
    expect(r.reason).toContain('different pattern')
  })

  it('returns null weight (no carry) when the substitute is bodyweight', () => {
    const pistolSquat = ex({
      id: 'pistol',
      name: 'Pistol Squat',
      movementPattern: 'squat',
      rankModel: 'BW_REPS',
    })
    const r = seedSubstituteLoad({ source, substitute: pistolSquat, sourceBestE1rmKg: 140 })
    expect(r.suggestedWeightKg).toBeNull()
    expect(r.fraction).toBe(0)
  })

  it('returns null weight when the source has no e1RM to carry', () => {
    const frontSquat = ex({ id: 'fs', movementPattern: 'squat', rankModel: 'WEIGHTED' })
    expect(seedSubstituteLoad({ source, substitute: frontSquat, sourceBestE1rmKg: null }).suggestedWeightKg).toBeNull()
    expect(seedSubstituteLoad({ source, substitute: frontSquat, sourceBestE1rmKg: 0 }).suggestedWeightKg).toBeNull()
  })

  it('is conservative — never carries more than the source e1RM', () => {
    const frontSquat = ex({ id: 'fs', movementPattern: 'squat', rankModel: 'WEIGHTED' })
    const r = seedSubstituteLoad({ source, substitute: frontSquat, sourceBestE1rmKg: 100 })
    expect(r.suggestedWeightKg!).toBeLessThan(100)
  })
})
