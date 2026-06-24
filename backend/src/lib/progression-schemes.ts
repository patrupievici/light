/**
 * Configurable progression schemes — the user-chosen strategy that decides the
 * NEXT working load for one lift from how the last prescribed session actually
 * went.
 *
 * This sits ABOVE the existing RPE autoregulation in progressive-overload.ts:
 *  - `auto`     → the exact current behavior (RPE autoregulation). Dispatching to
 *                 it is a no-op wrapper so `progressionScheme === 'auto'`
 *                 reproduces today bit-for-bit.
 *  - `linear`   → fixed add-on-success / back-off-on-fail. Add the level bump
 *                 when the prescription was met; hold (or deload after repeated
 *                 misses) when it wasn't.
 *  - `double`   → double progression: climb reps within a [min,max] band at a
 *                 fixed load, then add load and reset to the bottom of the band.
 *  - `reps_sum` → volume progression: add load once the TOTAL working reps for
 *                 the session cross a threshold; otherwise hold and accumulate.
 *
 * ADHERENCE GATE (Zvelt safety principle #4 + explainability #3): every non-auto
 * scheme only progresses when the user MET the prescription last time — hit the
 * target reps at or under the target RPE. If they fell short we HOLD instead of
 * blindly bumping. The gate compares the prescribed slot (from a planned
 * workout's exercisesJson) against what was actually logged.
 *
 * Pure + unit-testable: no Prisma, no Date.now(). The caller resolves history and
 * passes plain numbers in. Clean-room — these curves are Zvelt's own, derived
 * from the existing bumpForLevel ladder, not copied from any reference project.
 */

import {
  autoregulateLoad,
  bumpForLevel,
  roundToPlate,
  type AutoregInput,
  type AutoregResult,
  type ProgressionLevel,
} from './progressive-overload'

/** The four supported schemes. Unknown/empty strings normalise to 'auto'. */
export type ProgressionScheme = 'auto' | 'linear' | 'double' | 'reps_sum'

const VALID_SCHEMES: ReadonlySet<string> = new Set(['auto', 'linear', 'double', 'reps_sum'])

/**
 * Coerce a raw column value (UserTrainingProfile.progressionScheme) to a known
 * scheme. Anything unrecognised — null, '', a typo, a future value — falls back
 * to 'auto' so the planner never breaks on bad data and the default stays the
 * current behavior.
 */
export function normalizeProgressionScheme(raw: unknown): ProgressionScheme {
  if (typeof raw === 'string' && VALID_SCHEMES.has(raw)) return raw as ProgressionScheme
  return 'auto'
}

/** What the user was told to do last session (from the planned workout slot). */
export type Prescription = {
  /** Target reps the slot prescribed (per working set). */
  targetReps: number
  /** Target RPE ceiling, if the slot carried one; null = no RPE prescribed. */
  targetRpe: number | null
  /** Prescribed working load in kg; null for bodyweight / no-history slots. */
  targetWeightKg: number | null
}

/** What the user actually did last session for that lift (best/working set). */
export type ActualPerformance = {
  /** Reps achieved on the working set the gate evaluates. */
  reps: number
  /** Max RPE logged across the session's WORK sets; null if unlogged. */
  rpe: number | null
  /** Working load lifted in kg; null for bodyweight. */
  weightKg: number | null
  /** Sum of reps across all WORK sets this session (drives reps_sum). */
  totalWorkReps?: number
}

export type SchemeInput = {
  scheme: ProgressionScheme
  level: ProgressionLevel
  isCompound: boolean
  /** The autoreg inputs — used verbatim by the 'auto' scheme. */
  autoreg: AutoregInput
  /** Last prescription, when known (drives the adherence gate + double/reps_sum). */
  prescription?: Prescription | null
  /** Last actual performance, when known. */
  actual?: ActualPerformance | null
}

export type SchemeResult = {
  suggestedWeightKg: number
  /** Optional rep-target override (double progression climbs reps within a band). */
  suggestedReps?: number
  source: 'progression' | 'hold' | 'deload'
  reason: string
  /** Echoed back so the caller can attribute the decision in the UI. */
  scheme: ProgressionScheme
}

// ── Double-progression rep band ──────────────────────────────────────────────
// Climb from MIN to MAX reps at a fixed load; once MAX is hit, add load and
// reset to MIN. A band keeps hypertrophy/strength work in a productive rep range.
export const DOUBLE_REP_MIN = 8
export const DOUBLE_REP_MAX = 12

// ── reps_sum volume threshold ────────────────────────────────────────────────
// "Add load when the session's total working reps cross this" — derived from a
// typical 3×8 prescription (24 reps). Hitting >= threshold means the load is
// owned for the whole session, so it's earned the bump.
export const REPS_SUM_THRESHOLD = 25

/**
 * Did the user MEET the last prescription? Met = hit target reps AND stayed at or
 * under the target RPE ceiling (when one was prescribed). Missing either holds.
 *
 * When there's no prescription or no actual data the gate is permissive (returns
 * true) so a first-ever or untracked session behaves like the simple schemes did
 * before this gate existed — the schemes still fall back to their own no-history
 * paths upstream.
 */
export function metPrescription(
  prescription: Prescription | null | undefined,
  actual: ActualPerformance | null | undefined,
): boolean {
  if (!prescription || !actual) return true
  if (actual.reps < prescription.targetReps) return false
  if (prescription.targetRpe != null && actual.rpe != null && actual.rpe > prescription.targetRpe) {
    return false
  }
  return true
}

/**
 * Dispatch to the chosen scheme. `auto` delegates verbatim to autoregulateLoad
 * (current behavior, preserved exactly). All non-auto schemes run the adherence
 * gate first and HOLD when the last prescription wasn't met.
 */
export function applyProgressionScheme(inp: SchemeInput): SchemeResult {
  const scheme = normalizeProgressionScheme(inp.scheme)

  if (scheme === 'auto') {
    const r = autoregulateLoad(inp.autoreg)
    return { ...r, scheme }
  }

  // Adherence gate: every non-auto scheme holds when the user fell short of the
  // last prescription, regardless of how the specific scheme would otherwise add.
  const lastWeight = inp.autoreg.lastWeight
  if (!metPrescription(inp.prescription, inp.actual)) {
    return {
      suggestedWeightKg: roundToPlate(lastWeight),
      source: 'hold',
      reason: heldReason(inp.prescription, inp.actual),
      scheme,
    }
  }

  switch (scheme) {
    case 'linear':
      return { ...linearScheme(inp), scheme }
    case 'double':
      return { ...doubleScheme(inp), scheme }
    case 'reps_sum':
      return { ...repsSumScheme(inp), scheme }
    /* c8 ignore next 2 — normalize() guarantees one of the above */
    default:
      return { ...{ ...autoregulateLoad(inp.autoreg) }, scheme: 'auto' }
  }
}

/** Linear: fixed add-on-success (gate already passed), no-op for advanced. */
function linearScheme(inp: SchemeInput): Omit<SchemeResult, 'scheme'> {
  const { level, isCompound } = inp.autoreg
  const lastWeight = inp.autoreg.lastWeight
  const bump = bumpForLevel(level, isCompound, lastWeight)
  if (bump <= 0) {
    return {
      suggestedWeightKg: roundToPlate(lastWeight),
      source: 'progression',
      reason: `Linear progression: target met but ${level} lifters hold load — progress on reps/volume, not weight each session.`,
    }
  }
  const next = roundToPlate(lastWeight + bump)
  return {
    suggestedWeightKg: next,
    source: 'progression',
    reason: `Linear progression: hit the prescription → +${bump.toFixed(2)}kg to ${next}kg.`,
  }
}

/**
 * Double progression: climb reps within [MIN, MAX] at the same load, then add
 * load and reset to MIN once the top of the band is reached.
 *
 * Reads the last ACTUAL reps to decide where in the band the lifter is. The gate
 * already confirmed they met the prescription, so:
 *  - reps >= MAX → top of band reached → add load, reset rep target to MIN.
 *  - reps <  MAX → same load, climb the rep target by +1 (capped at MAX).
 */
function doubleScheme(inp: SchemeInput): Omit<SchemeResult, 'scheme'> {
  const { level, isCompound } = inp.autoreg
  const lastWeight = inp.autoreg.lastWeight
  const lastReps = inp.actual?.reps ?? inp.autoreg.lastReps

  if (lastReps >= DOUBLE_REP_MAX) {
    const bump = bumpForLevel(level, isCompound, lastWeight)
    if (bump <= 0) {
      // Advanced: no linear bump — keep climbing reps instead of stalling.
      return {
        suggestedWeightKg: roundToPlate(lastWeight),
        suggestedReps: DOUBLE_REP_MAX,
        source: 'progression',
        reason: `Double progression: top of the ${DOUBLE_REP_MIN}–${DOUBLE_REP_MAX} band at ${lastWeight}kg — advanced lifters hold load and keep reps high.`,
      }
    }
    const next = roundToPlate(lastWeight + bump)
    return {
      suggestedWeightKg: next,
      suggestedReps: DOUBLE_REP_MIN,
      source: 'progression',
      reason: `Double progression: cleared ${DOUBLE_REP_MAX} reps → +${bump.toFixed(2)}kg to ${next}kg, reset to ${DOUBLE_REP_MIN} reps.`,
    }
  }

  const nextReps = Math.min(DOUBLE_REP_MAX, lastReps + 1)
  return {
    suggestedWeightKg: roundToPlate(lastWeight),
    suggestedReps: nextReps,
    source: 'progression',
    reason: `Double progression: same ${lastWeight}kg, climb reps ${lastReps} → ${nextReps} (toward ${DOUBLE_REP_MAX} before adding load).`,
  }
}

/**
 * reps_sum: add load once the session's TOTAL working reps cross a threshold.
 * The gate already confirmed the per-set target was met; this layer additionally
 * checks accumulated session volume so load only climbs when the whole session
 * (not a single set) is owned.
 */
function repsSumScheme(inp: SchemeInput): Omit<SchemeResult, 'scheme'> {
  const { level, isCompound } = inp.autoreg
  const lastWeight = inp.autoreg.lastWeight
  // Fall back to the single working set's reps when total volume wasn't supplied.
  const totalReps = inp.actual?.totalWorkReps ?? inp.actual?.reps ?? inp.autoreg.lastReps

  if (totalReps < REPS_SUM_THRESHOLD) {
    return {
      suggestedWeightKg: roundToPlate(lastWeight),
      source: 'hold',
      reason: `Volume progression: ${totalReps} total reps < ${REPS_SUM_THRESHOLD} target — hold ${lastWeight}kg and add reps before load.`,
    }
  }

  const bump = bumpForLevel(level, isCompound, lastWeight)
  if (bump <= 0) {
    return {
      suggestedWeightKg: roundToPlate(lastWeight),
      source: 'progression',
      reason: `Volume progression: ${totalReps} reps cleared the bar but ${level} lifters hold load — keep accumulating volume.`,
    }
  }
  const next = roundToPlate(lastWeight + bump)
  return {
    suggestedWeightKg: next,
    source: 'progression',
    reason: `Volume progression: ${totalReps} total reps ≥ ${REPS_SUM_THRESHOLD} → +${bump.toFixed(2)}kg to ${next}kg.`,
  }
}

/** Explanation when the adherence gate holds load. */
function heldReason(
  prescription: Prescription | null | undefined,
  actual: ActualPerformance | null | undefined,
): string {
  if (prescription && actual) {
    if (actual.reps < prescription.targetReps) {
      return `Held: hit ${actual.reps}/${prescription.targetReps} target reps last time — clear the prescription before adding load.`
    }
    if (prescription.targetRpe != null && actual.rpe != null && actual.rpe > prescription.targetRpe) {
      return `Held: last set RPE ${actual.rpe.toFixed(1)} above the ${prescription.targetRpe.toFixed(1)} target — consolidate before adding load.`
    }
  }
  return 'Held: prescription not fully met last time — repeat before adding load.'
}

// Keep the AutoregResult import live for editor goto-def / future typing.
export type _SchemeAutoreg = AutoregResult
