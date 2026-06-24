/**
 * Exercise substitution ranking — "swap this lift for a similar one".
 *
 * Pure + unit-testable (no Prisma): the route fetches the source exercise plus a
 * candidate pool and hands them here. We score each candidate against the source
 * on ZVELT-specific signals and emit a human-readable "why this alternative"
 * string for the Explainability principle (#3).
 *
 * Scoring signals (descending weight):
 *  - Movement pattern: same primary pattern is the strongest match. A candidate
 *    whose secondary patterns include the source's primary (or vice-versa)
 *    counts as a partial pattern match.
 *  - Muscle overlap: the more canonical muscles the two lifts share (primary +
 *    secondary), the stronger the signal that the swap trains the same thing.
 *    Sharing the primary mover is weighted heaviest; shared secondaries add
 *    diminishing credit. Free-text muscle names are normalised to a controlled
 *    vocabulary first so "Hamstrings" and "hams" compare equal.
 *  - Equipment availability: candidates the user can actually perform with their
 *    equipment rank above ones they can't (but we still surface the latter,
 *    flagged, so the list isn't empty for a kitted-out home gym).
 *  - rankModel compatibility: a WEIGHTED→WEIGHTED swap preserves how the lift is
 *    ranked/progressed; a WEIGHTED→BW_REPS swap changes the whole load model.
 *  - Fatigue proximity: prefer alternatives with a similar systemic cost so the
 *    session's overall demand doesn't spike.
 *
 * Deliberately does NOT copy any reference project's similarity algorithm or
 * muscle-distance table — weights below are our own and tuned to ZVELT's fields.
 */

import { muscleLabel, normalizeMuscleSet, type Muscle } from '../constants/muscles'

/** Minimal Exercise shape this ranker reads — a subset of the Prisma row. */
export type SubstitutionExercise = {
  id: string
  name: string
  primaryMuscle: string | null
  equipment: string | null
  rankModel: string
  category: string
  movementPattern: string
  /** Prisma stores this as JSON; we accept the parsed value defensively. */
  secondaryPatterns: unknown
  /**
   * Structured secondary muscles (controlled vocabulary, JSON array). Optional
   * so existing callers/fixtures that predate the field keep working — when
   * absent or empty the ranker falls back to the primary muscle alone.
   */
  secondaryMuscles?: unknown
  fatigueScore: number
}

export type SubstitutionCandidate<T extends SubstitutionExercise = SubstitutionExercise> = {
  /** The candidate row — preserves the caller's richer type (e.g. full Prisma row). */
  exercise: T
  /** 0–100 overall match score (higher = closer substitute). */
  score: number
  /** Whether the user's equipment can perform this candidate. */
  equipmentAvailable: boolean
  /** Human-readable explanation surfaced in the swap UI. */
  reason: string
}

export type RankSubstitutesOptions = {
  /** When provided, used only to tag/sort by equipment availability. */
  isEquipmentAvailable?: (equipment: string | null) => boolean
  /** Max number of alternatives to return (default 8). */
  limit?: number
}

// ─── Signal weights (sum of the positive maxima = 100) ───────────────────────
const W_PATTERN_SAME = 45
const W_PATTERN_PARTIAL = 22
const W_MUSCLE = 25
const W_RANK_MODEL = 12
const W_FATIGUE_MAX = 10
const W_CATEGORY = 8

/** Coerce the JSON secondaryPatterns field to a clean string[]. */
function toPatternList(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.filter((v): v is string => typeof v === 'string')
}

/** Human label for a movement pattern token (squat → "squat", horizontal_push → "horizontal push"). */
function patternLabel(pattern: string): string {
  return pattern.replace(/_/g, ' ')
}

// Relative importance of a muscle within an exercise for overlap scoring: the
// primary mover counts double a secondary one. Used to weight both how much
// credit a shared muscle earns and to normalise against the source's profile so
// a primary↔primary match still earns the full muscle weight.
const PRIMARY_WEIGHT = 1
const SECONDARY_WEIGHT = 0.5

/**
 * Score muscle overlap between two exercises on a 0..W_MUSCLE scale and list the
 * shared muscles for the reason string.
 *
 * Both sides are normalised onto the controlled vocabulary first. The source's
 * primary mover counts double a secondary, and we measure how much of the
 * source's total muscle "weight" the candidate also trains — so a swap that
 * keeps the primary mover and some secondaries scores higher than one that only
 * shares a minor secondary. With no secondaryMuscles on either side this reduces
 * to the original all-or-nothing primary match (full weight or zero).
 */
function scoreMuscleOverlap(
  source: SubstitutionExercise,
  candidate: SubstitutionExercise,
): { points: number; shared: Muscle[] } {
  const srcPrimary = normalizeMuscleSet(source.primaryMuscle)
  const srcAll = normalizeMuscleSet(source.primaryMuscle, source.secondaryMuscles)
  const candAll = normalizeMuscleSet(candidate.primaryMuscle, candidate.secondaryMuscles)

  if (srcAll.size === 0 || candAll.size === 0) {
    return { points: 0, shared: [] }
  }

  // Importance of a source muscle: primary mover weighted heavier than secondaries.
  const importance = (m: Muscle): number => (srcPrimary.has(m) ? PRIMARY_WEIGHT : SECONDARY_WEIGHT)

  let total = 0
  let matched = 0
  const shared: Muscle[] = []
  for (const m of srcAll) {
    const w = importance(m)
    total += w
    if (candAll.has(m)) {
      matched += w
      shared.push(m)
    }
  }

  if (total === 0 || matched === 0) {
    return { points: 0, shared }
  }

  // Primary mover first in the shared list for a readable reason.
  shared.sort((a, b) => importance(b) - importance(a))

  return { points: W_MUSCLE * (matched / total), shared }
}

/**
 * Score one candidate against the source. Exported for direct unit testing of
 * the curve without building a full candidate list.
 */
export function scoreSubstitute(
  source: SubstitutionExercise,
  candidate: SubstitutionExercise,
  equipmentAvailable: boolean,
): { score: number; reason: string } {
  let score = 0
  const reasons: string[] = []

  // ── Movement pattern (primary signal) ─────────────────────────────────────
  const srcSecondary = toPatternList(source.secondaryPatterns)
  const candSecondary = toPatternList(candidate.secondaryPatterns)

  if (candidate.movementPattern === source.movementPattern) {
    score += W_PATTERN_SAME
    reasons.push(`Same ${patternLabel(source.movementPattern)} pattern`)
  } else if (
    candSecondary.includes(source.movementPattern) ||
    srcSecondary.includes(candidate.movementPattern)
  ) {
    score += W_PATTERN_PARTIAL
    reasons.push(`Overlapping ${patternLabel(source.movementPattern)} pattern`)
  }

  // ── Muscle overlap (normalised primary + secondary muscles) ───────────────
  const { points: musclePoints, shared } = scoreMuscleOverlap(source, candidate)
  if (musclePoints > 0) {
    score += musclePoints
    const labels = shared.map(muscleLabel)
    const list =
      labels.length <= 2
        ? labels.join(' and ')
        : `${labels.slice(0, 2).join(', ')} +${labels.length - 2} more`
    reasons.push(`shares ${list}`)
  }

  // ── rankModel compatibility ───────────────────────────────────────────────
  if (candidate.rankModel === source.rankModel) {
    score += W_RANK_MODEL
  } else {
    reasons.push(`different load model (${candidate.rankModel.toLowerCase()})`)
  }

  // ── Category match (strength vs explosive vs bodyweight vs cardio) ─────────
  if (candidate.category === source.category) {
    score += W_CATEGORY
  }

  // ── Fatigue proximity (closer systemic cost ranks higher) ─────────────────
  const fatigueGap = Math.abs(candidate.fatigueScore - source.fatigueScore)
  // fatigueScore is 1–5, so gap is 0–4. Linear decay to 0 at gap 4.
  const fatigueScore = W_FATIGUE_MAX * Math.max(0, 1 - fatigueGap / 4)
  score += fatigueScore
  if (fatigueGap === 0) {
    reasons.push('matched effort cost')
  } else if (candidate.fatigueScore < source.fatigueScore) {
    reasons.push('lower fatigue')
  } else if (candidate.fatigueScore > source.fatigueScore) {
    reasons.push('higher fatigue')
  }

  // ── Equipment availability — does not add score, but flags the reason ──────
  const equipLabel = candidate.equipment ?? 'bodyweight'
  if (equipmentAvailable) {
    reasons.push(`${equipLabel} variation`)
  } else {
    reasons.push(`needs ${equipLabel} (not in your kit)`)
  }

  // Round so the score is stable/legible; cap at 100.
  const rounded = Math.min(100, Math.round(score * 10) / 10)

  // Build a tidy sentence: capitalize the first reason, comma-join the rest.
  const reason = sentenceFromReasons(reasons)

  return { score: rounded, reason }
}

/**
 * A candidate is only a meaningful substitute if it shares the source's
 * movement pattern (primary or secondary) or at least one canonical muscle
 * (primary or secondary, normalised). Exported so the cutoff is unit-testable
 * independently of the score curve.
 */
export function sharesPatternOrMuscle(
  source: SubstitutionExercise,
  candidate: SubstitutionExercise,
): boolean {
  const srcSecondary = toPatternList(source.secondaryPatterns)
  const candSecondary = toPatternList(candidate.secondaryPatterns)
  const patternMatch =
    candidate.movementPattern === source.movementPattern ||
    candSecondary.includes(source.movementPattern) ||
    srcSecondary.includes(candidate.movementPattern)

  const muscleMatch = scoreMuscleOverlap(source, candidate).shared.length > 0

  return patternMatch || muscleMatch
}

/** Compose a single readable sentence from the collected reason fragments. */
function sentenceFromReasons(reasons: string[]): string {
  if (reasons.length === 0) return 'Alternative movement'
  const [first, ...rest] = reasons
  const head = first.charAt(0).toUpperCase() + first.slice(1)
  return rest.length ? `${head}, ${rest.join(', ')}.` : `${head}.`
}

/**
 * Rank a candidate pool as substitutes for `source`. The source itself is
 * filtered out. Sorting is: equipment-available first, then score desc, then
 * name asc for a stable order. Returns at most `limit` candidates.
 */
export function rankSubstitutes<T extends SubstitutionExercise>(
  source: SubstitutionExercise,
  candidates: T[],
  options: RankSubstitutesOptions = {},
): SubstitutionCandidate<T>[] {
  const { isEquipmentAvailable, limit = 8 } = options

  const scored: SubstitutionCandidate<T>[] = []
  for (const candidate of candidates) {
    if (candidate.id === source.id) continue

    const equipmentAvailable = isEquipmentAvailable
      ? isEquipmentAvailable(candidate.equipment)
      : true

    // Drop candidates that share neither movement pattern nor primary muscle —
    // they are not meaningful substitutes for the source movement, regardless of
    // how close their rankModel/category/fatigue happen to be.
    if (!sharesPatternOrMuscle(source, candidate)) continue

    const { score, reason } = scoreSubstitute(source, candidate, equipmentAvailable)
    scored.push({ exercise: candidate, score, equipmentAvailable, reason })
  }

  scored.sort((a, b) => {
    if (a.equipmentAvailable !== b.equipmentAvailable) {
      return a.equipmentAvailable ? -1 : 1
    }
    if (b.score !== a.score) return b.score - a.score
    return a.exercise.name.localeCompare(b.exercise.name)
  })

  return scored.slice(0, limit)
}

// ─── Substitution load carry-over ────────────────────────────────────────────
//
// When a user swaps lift A for lift B, B usually has no history so the planner
// returns `no_history` and the user is left guessing a working weight. That's a
// regression from the slot they just had a load for. Instead we SEED B's load
// from a conservative fraction of A's best e1RM, so the swap arrives with a
// sensible starting weight on day one.
//
// The fraction is intentionally < 1.0: the substitute is rarely a 1:1 strength
// match (a different bar path, grip, or stability demand means you can't move
// the same absolute load), and starting light leaves reps in reserve — aligned
// with Zvelt's safety guardrails (#4). Same-pattern swaps carry over a higher
// fraction than cross-pattern ones, and a load-model change (WEIGHTED → BW)
// can't carry a barbell number at all.

/** Default carry-over fraction for a close (same-pattern) substitute. */
export const CARRYOVER_SAME_PATTERN = 0.9
/** Carry-over fraction for a looser (partial-pattern / muscle-only) substitute. */
export const CARRYOVER_PARTIAL = 0.75

export type CarryOverInput = {
  /** The lift being replaced. */
  source: SubstitutionExercise
  /** The chosen substitute. */
  substitute: SubstitutionExercise
  /** Source lift's best e1RM in kg (from UserExerciseRank); null if unknown. */
  sourceBestE1rmKg: number | null
}

export type CarryOverResult = {
  /** Seeded working load in kg for the substitute, plate-rounded; null when it
   *  can't be carried (no source e1RM, or a WEIGHTED → bodyweight swap). */
  suggestedWeightKg: number | null
  /** Fraction of source e1RM applied (0 when not carried). */
  fraction: number
  /** Explanation for the "why this load?" panel. */
  reason: string
}

/**
 * Round to the nearest 2.5 kg plate step (min 5 kg) — mirrors progressive-
 * overload's plate rounding without importing it (keeps this lib Prisma-free and
 * dependency-light). Duplicated deliberately so the two libs stay decoupled.
 */
function roundToPlateStep(kg: number): number {
  const rounded = Math.round(kg / 2.5) * 2.5
  return Math.max(5, Math.round(rounded * 10) / 10)
}

/**
 * Seed a substitute lift's starting load from a fraction of the original lift's
 * e1RM, so a swap is NOT reported as `no_history`.
 *
 * Returns null weight (caller keeps the existing no-history path) when:
 *  - the source has no e1RM to carry from, or
 *  - the substitute is bodyweight-ranked (BW_REPS) — a barbell number is
 *    meaningless there.
 *
 * The fraction scales with how close the swap is: a same-pattern substitute
 * carries 90% of e1RM, a looser one 75%. e1RM (a 1-rep estimate) is then taken
 * straight as the seeded WORKING load fraction, which already lands well below a
 * true 1RM working weight — conservative by construction.
 */
export function seedSubstituteLoad(inp: CarryOverInput): CarryOverResult {
  const { source, substitute, sourceBestE1rmKg } = inp

  if (substitute.rankModel === 'BW_REPS') {
    return {
      suggestedWeightKg: null,
      fraction: 0,
      reason: 'Bodyweight substitute — pick a rep target you can hit with clean form.',
    }
  }

  if (sourceBestE1rmKg == null || !Number.isFinite(sourceBestE1rmKg) || sourceBestE1rmKg <= 0) {
    return {
      suggestedWeightKg: null,
      fraction: 0,
      reason: 'No history on the original lift to carry over — start light and leave 2–3 reps in reserve.',
    }
  }

  const samePattern = substitute.movementPattern === source.movementPattern
  const fraction = samePattern ? CARRYOVER_SAME_PATTERN : CARRYOVER_PARTIAL
  const seeded = roundToPlateStep(sourceBestE1rmKg * fraction)
  const pct = Math.round(fraction * 100)

  return {
    suggestedWeightKg: seeded,
    fraction,
    reason: samePattern
      ? `Carried from your ${source.name} (~${pct}% of its ${sourceBestE1rmKg.toFixed(1)}kg e1RM) — same movement pattern, start here and adjust.`
      : `Carried from your ${source.name} (~${pct}% of its ${sourceBestE1rmKg.toFixed(1)}kg e1RM) — different pattern, so start conservative.`,
  }
}
