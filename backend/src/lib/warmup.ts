import { roundToPlate } from './progressive-overload'

/**
 * Warm-up ramp generation for the weekly planner.
 *
 * The planner already picks a working LOAD per lift (progressive-overload.ts).
 * For heavy compound barbell lifts a single working set with no ramp is both a
 * safety hole (Zvelt principle #4 — safety guardrails) and a strength leak: the
 * literature is consistent that potentiation/ramp sets before a top set improve
 * the top set without meaningful fatigue when reps descend as load rises.
 *
 * This module is a PURE helper — no Prisma, no network — so the ramp math is
 * unit-testable in isolation. The caller (weekly-plan.service) decides which
 * exercises get a ramp and attaches the returned array to the planned
 * `exercisesJson` entry. Warm-up sets are marked `tag: 'WARMUP'` so the tracker
 * tags them WARMUP on log; the ranking algorithm already excludes non-WORK sets
 * from e1RM, so warm-ups never pollute a rank.
 *
 * Non-compound lifts (accessory / isolation) and non-weighted lifts (bodyweight,
 * timed) return an empty ramp: warming up an isolation curl off an empty bar is
 * noise, and a bodyweight movement has no external load to ramp.
 */

/** A single generated warm-up set, ready to drop into exercisesJson. */
export type WarmupSet = {
  /** Plate-rounded warm-up load in kg. */
  weightKg: number
  /** Prescribed reps for this warm-up step (descends as load rises). */
  reps: number
  /** Fraction of the working weight this step targets (0–1), pre-rounding. */
  percentOfWorking: number
  /** Always 'WARMUP' — lets the tracker tag the logged set so ranking skips it. */
  tag: 'WARMUP'
}

/**
 * Movement patterns that qualify as compound enough to deserve a ramp. Mirrors
 * the spirit of the planner's compound list (squat/hinge/presses/pulls) but is
 * defined here independently so this module owns its own classification.
 */
const RAMPABLE_PATTERNS = new Set([
  'squat',
  'hinge',
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
])

/**
 * Default ramp: ascending load, descending reps. The empty-bar primer is added
 * separately (see opts.barWeightKg). Percentages are of the working weight.
 * Tuned to be light enough not to fatigue and few enough not to bloat a session.
 */
const DEFAULT_RAMP: Array<{ percent: number; reps: number }> = [
  { percent: 0.4, reps: 5 },
  { percent: 0.6, reps: 3 },
  { percent: 0.8, reps: 2 },
]

export type WarmupOpts = {
  /** Movement pattern of the lift (Exercise.movementPattern). */
  movementPattern?: string | null
  /** Rank model (Exercise.rankModel): WEIGHTED | BW_REPS | TIME. */
  rankModel?: string | null
  /** Exercise.category: strength | explosive | bodyweight | cardio. */
  category?: string | null
  /**
   * Empty-bar / primer load in kg added as the first ramp step. Defaults to a
   * standard Olympic barbell (20kg). Set 0 to skip the empty-bar primer (e.g.
   * dumbbell or machine compounds where there's no bar to prime with).
   */
  barWeightKg?: number
  /** Override the ramp steps (percent of working weight + reps). */
  ramp?: Array<{ percent: number; reps: number }>
  /**
   * Minimum gap (kg) between the working weight and the top ramp step. If the
   * working weight is so light that the top ramp step rounds to (or above) it,
   * that step is dropped — warming up at the working weight is not a warm-up.
   */
  minGapKg?: number
}

const DEFAULT_BAR_KG = 20
const DEFAULT_MIN_GAP_KG = 2.5

/**
 * Should this lift get a warm-up ramp at all?
 *
 * True only for WEIGHTED compound lifts (a recognized compound movement pattern,
 * not bodyweight/timed, not the bodyweight/cardio category). Exported so the
 * caller can branch without duplicating the rule.
 */
export function isRampableLift(opts: WarmupOpts): boolean {
  const pattern = (opts.movementPattern ?? '').trim()
  if (!RAMPABLE_PATTERNS.has(pattern)) return false

  // Bodyweight / timed lifts carry no external barbell load to ramp.
  const rankModel = (opts.rankModel ?? 'WEIGHTED').trim().toUpperCase()
  if (rankModel === 'BW_REPS' || rankModel === 'TIME') return false

  const category = (opts.category ?? 'strength').trim().toLowerCase()
  if (category === 'bodyweight' || category === 'cardio') return false

  return true
}

/**
 * Generate an ascending warm-up ramp for a working set.
 *
 * Returns an empty array when:
 *  - the lift is not a weighted compound (see isRampableLift), or
 *  - the working weight is missing / non-positive, or
 *  - the working weight is so light no ramp step clears the empty bar + gap.
 *
 * Otherwise returns, in ascending load order:
 *  1. an optional empty-bar primer (opts.barWeightKg, default 20kg), then
 *  2. the percentage ramp steps that sit strictly below the working weight by
 *     at least `minGapKg`, plate-rounded, de-duplicated on rounded weight.
 *
 * The working set itself is NOT included — the caller already has it.
 */
export function generateWarmupSets(workingWeightKg: number, opts: WarmupOpts = {}): WarmupSet[] {
  if (!isRampableLift(opts)) return []
  if (!Number.isFinite(workingWeightKg) || workingWeightKg <= 0) return []

  const barWeightKg = opts.barWeightKg ?? DEFAULT_BAR_KG
  const minGapKg = opts.minGapKg ?? DEFAULT_MIN_GAP_KG
  const ramp = opts.ramp ?? DEFAULT_RAMP

  const ceilingKg = workingWeightKg - minGapKg
  const out: WarmupSet[] = []
  const seenWeights = new Set<number>()

  const push = (weightKg: number, reps: number, percentOfWorking: number) => {
    // A warm-up step must sit strictly below the working set (with the gap),
    // and we never emit two identical rounded loads.
    if (weightKg <= 0 || weightKg > ceilingKg) return
    if (seenWeights.has(weightKg)) return
    seenWeights.add(weightKg)
    out.push({ weightKg, reps, percentOfWorking, tag: 'WARMUP' })
  }

  // 1) Empty-bar primer (highest rep count — it's a movement primer, not load).
  if (barWeightKg > 0) {
    push(roundToPlate(barWeightKg), 8, roundFraction(barWeightKg / workingWeightKg))
  }

  // 2) Percentage ramp — ascending load, descending reps (DEFAULT_RAMP order).
  for (const step of ramp) {
    const target = workingWeightKg * step.percent
    push(roundToPlate(target), step.reps, step.percent)
  }

  // roundToPlate has a 5kg floor, so a very light working weight can collapse
  // several steps onto the same load — dedupe (done in push) keeps the ramp
  // strictly ascending. Final sort guarantees ascending order regardless of the
  // primer vs first ramp step ordering after rounding.
  out.sort((a, b) => a.weightKg - b.weightKg)
  return out
}

/** Round a fraction to 2 decimals for stable JSON output. */
function roundFraction(f: number): number {
  if (!Number.isFinite(f)) return 0
  return Math.round(f * 100) / 100
}
