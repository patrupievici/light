import { normalizeMuscle, type Muscle } from '../constants/muscles'

/**
 * Per-muscle LEVEL math + the canonical→Flutter-SVG slug bridge.
 *
 * Level blends two signals (user's pick): VOLUME-RPG (steady progress from
 * accumulated training volume) + STRENGTH (a bonus from the muscle's e1RM tier).
 * PURE + unit-testable — the route resolves history and passes plain numbers in.
 */

/** Volume needed for the first volume level; the curve is sqrt so it slows. */
export const VOLUME_BASE = 2000

export const PRIMARY_CONTRIB = 1.0
export const SECONDARY_CONTRIB = 0.5

/**
 * Canonical muscle (muscles.ts, 22 snake_case tags) → the Flutter muscle-map SVG
 * slug (15 rendered regions). Several canonical tags MERGE onto one SVG region
 * (the three delts → "deltoids", lats + upper_back → "upper-back"); muscles the
 * SVG has no region for map to null and are dropped from the map response.
 */
export const MUSCLE_TO_SVG_SLUG: Record<Muscle, string | null> = {
  chest: 'chest',
  front_delts: 'deltoids',
  side_delts: 'deltoids',
  rear_delts: 'deltoids',
  triceps: 'triceps',
  lats: 'upper-back',
  upper_back: 'upper-back',
  lower_back: 'lower-back',
  biceps: 'biceps',
  forearms: 'forearm',
  traps: 'trapezius',
  abs: 'abs',
  obliques: 'obliques',
  quads: 'quadriceps',
  hamstrings: 'hamstring',
  glutes: 'gluteal',
  calves: 'calves',
  adductors: 'adductors',
  abductors: null,
  hip_flexors: null,
  neck: null,
}

/** The 15 SVG slugs the Flutter muscle map actually renders. */
export const SVG_SLUGS: readonly string[] = Array.from(
  new Set(Object.values(MUSCLE_TO_SVG_SLUG).filter((s): s is string => s != null)),
)

/** Map any free-text / canonical muscle to a Flutter SVG slug, or null. */
export function svgSlugForMuscle(raw: unknown): string | null {
  const canon = normalizeMuscle(raw)
  if (!canon) return null
  return MUSCLE_TO_SVG_SLUG[canon]
}

export type MuscleLevelParts = { level: number; volumeLevel: number; strengthBonus: number }

/**
 * Per-muscle level from accumulated volume XP + the muscle's best strength (LP).
 *  - volumeLevel = floor(sqrt(volumeXp / VOLUME_BASE)) — steady RPG climb.
 *  - strengthBonus = floor(bestLp / 100), clamped 0..6 (LP is 0–699 across 7 tiers).
 *  - level = max(1, volumeLevel + strengthBonus) when trained, else 0 (untrained).
 */
export function computeMuscleLevel(volumeXp: number, bestLp: number): MuscleLevelParts {
  if (!Number.isFinite(volumeXp) || volumeXp <= 0) {
    return { level: 0, volumeLevel: 0, strengthBonus: 0 }
  }
  const volumeLevel = Math.floor(Math.sqrt(volumeXp / VOLUME_BASE))
  const lp = Number.isFinite(bestLp) && bestLp > 0 ? bestLp : 0
  const strengthBonus = Math.max(0, Math.min(6, Math.floor(lp / 100)))
  return { level: Math.max(1, volumeLevel + strengthBonus), volumeLevel, strengthBonus }
}
