import { prisma } from './prisma'
import {
  applyProgressionScheme,
  normalizeProgressionScheme,
  type ProgressionScheme,
  type Prescription,
} from './progression-schemes'

/**
 * Deterministic progressive overload: AI picks the EXERCISES, this picks the
 * LOAD. Keeps progression predictable, explainable (Zvelt principle #3), and
 * safe (no AI hallucinated 200kg squat for a beginner).
 *
 * Rules:
 *  - Compound lifts (squat/bench/deadlift/OHP/row): +2.5kg per training session
 *    for beginners, +1.25kg for intermediate, +0kg for advanced (linear
 *    progression doesn't hold past intermediate — they need block periodization
 *    which is beyond scope here, so we keep last weight).
 *  - Accessory lifts: +2.5% / +1% / +0% by level, rounded to 2.5kg step.
 *  - Bodyweight-only (rankModel=BW_REPS): no load bump, instead bump prescribed
 *    reps by +1 (capped at 15) — the caller decides whether to apply.
 *  - Stalled lifts (no progress in 30 days): hold weight instead of forcing a
 *    bump that won't move. Marked `progression: 'hold'` so AI/UI can react.
 *  - No history: returns null; caller should use heuristic from bodyweight.
 *
 * Returns one decision per input exercise; preserves order.
 */

export type ProgressionLevel = 'beginner' | 'intermediate' | 'advanced'

export type OverloadInput = {
  /** Real Exercise.id (when name resolved); null for AI-invented names. */
  exerciseId: string | null
  /** AI's suggested rep count for this slot (drives bw rep-bump). */
  prescribedReps: number
  /**
   * What the user was LAST told to do for this lift (from a prior planned
   * workout slot), used by the adherence gate in non-`auto` schemes. Optional:
   * absent → the gate is permissive and schemes behave like first-run.
   */
  lastPrescription?: Prescription | null
}

export type ComputeProgressiveLoadsOpts = {
  /**
   * Progression strategy from UserTrainingProfile.progressionScheme. Defaults to
   * `auto` (RPE autoregulation) which reproduces the prior behavior EXACTLY —
   * the scheme layer is only consulted for non-auto values.
   */
  progressionScheme?: ProgressionScheme | string | null
}

export type OverloadDecision = {
  /** Suggested working weight in kg, rounded to gym plate step. */
  suggestedWeightKg: number | null
  /** Updated rep target — usually unchanged; bumped for bodyweight progressions. */
  suggestedReps: number
  /** Where the number came from — surfaced to UI for "why this load?" tooltip. */
  source: 'progression' | 'hold' | 'no_history' | 'deload'
  /** Free-text explanation for the explainability panel. */
  reason: string
}

const COMPOUND_PATTERNS = new Set([
  'squat',
  'hinge',
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
])

const STALL_THRESHOLD_DAYS = 30
const STALL_E1RM_DELTA_KG = 1.0

/**
 * Compute a load decision per exercise, given the user's recent history.
 * Input `inputs` is the AI-returned exercise list (after name resolution).
 */
export async function computeProgressiveLoads(
  userId: string,
  inputs: OverloadInput[],
  level: ProgressionLevel,
  opts: ComputeProgressiveLoadsOpts = {},
): Promise<OverloadDecision[]> {
  if (inputs.length === 0) return []

  // `auto` (the default) keeps the exact prior code path; only non-auto schemes
  // route the earned-jump decision through the configurable scheme dispatcher.
  const scheme = normalizeProgressionScheme(opts.progressionScheme)

  const ids = inputs.map((i) => i.exerciseId).filter((x): x is string => !!x)
  if (ids.length === 0) {
    return inputs.map<OverloadDecision>((i) => ({
      suggestedWeightKg: null,
      suggestedReps: i.prescribedReps,
      source: 'no_history',
      reason: 'Exercise not in catalog; use form-first warmups and pick a working weight on feel.',
    }))
  }

  const [exercises, recentSets, ranks, progress] = await Promise.all([
    prisma.exercise.findMany({
      where: { id: { in: ids } },
      select: { id: true, rankModel: true, movementPattern: true },
    }),
    prisma.workoutSet.findMany({
      where: {
        tag: 'WORK',
        isCompleted: true,
        weightKg: { gt: 0 },
        workoutExercise: {
          exerciseId: { in: ids },
          workout: { userId, status: { in: ['completed', 'posted'] } },
        },
      },
      select: {
        weightKg: true,
        reps: true,
        rpe: true,
        createdAt: true,
        workoutExercise: { select: { exerciseId: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: 300,
    }),
    prisma.userExerciseRank.findMany({
      where: { userId, exerciseId: { in: ids } },
      select: { exerciseId: true, bestE1rmKg: true, updatedAt: true },
    }),
    // Durable autoregulation decision recorded on the last workout complete
    // (recordWorkoutProgress). Reading it back here closes the write-only loop:
    // log → complete → stored next-load decision → this plan.
    prisma.userExerciseProgress.findMany({
      where: { userId, exerciseId: { in: ids } },
      select: { exerciseId: true, nextWeightKg: true, nextSource: true, nextReason: true },
    }),
  ])

  type ExMeta = { rankModel: string; movementPattern: string }
  const exMeta = new Map<string, ExMeta>(
    exercises.map((e) => [e.id, { rankModel: e.rankModel, movementPattern: e.movementPattern }]),
  )

  type LastSet = { weight: number; reps: number; rpe: number | null; createdAt: Date }
  const lastSetByEx = new Map<string, LastSet>()
  for (const s of recentSets) {
    const eid = s.workoutExercise.exerciseId
    if (!lastSetByEx.has(eid)) {
      lastSetByEx.set(eid, {
        weight: Number(s.weightKg),
        reps: s.reps,
        rpe: s.rpe == null ? null : Number(s.rpe),
        createdAt: s.createdAt,
      })
    }
  }

  const rankByEx = new Map(ranks.map((r) => [r.exerciseId, r]))
  const progressByEx = new Map(progress.map((p) => [p.exerciseId, p]))

  return inputs.map<OverloadDecision>((inp) => {
    if (!inp.exerciseId) {
      return {
        suggestedWeightKg: null,
        suggestedReps: inp.prescribedReps,
        source: 'no_history',
        reason: 'Exercise not in catalog; use form-first warmups and pick a working weight on feel.',
      }
    }
    const meta = exMeta.get(inp.exerciseId)
    const last = lastSetByEx.get(inp.exerciseId)
    const rank = rankByEx.get(inp.exerciseId)
    const prog = progressByEx.get(inp.exerciseId)

    // Prefer the durable decision recorded at the last workout complete — it was
    // already autoregulated from that session's RPE/reps (single source of truth,
    // and it carries deload/hold state the raw last-set recompute below can't see).
    // BW lifts have null nextWeightKg, so they fall through to the rep-based path.
    if (prog && prog.nextWeightKg != null && prog.nextSource) {
      return {
        suggestedWeightKg: Number(prog.nextWeightKg),
        suggestedReps: inp.prescribedReps,
        source: prog.nextSource as OverloadDecision['source'],
        reason: prog.nextReason ?? `Carried from your last session (${prog.nextSource}).`,
      }
    }

    // Bodyweight: bump reps instead of weight.
    if (meta?.rankModel === 'BW_REPS') {
      const reps = Math.min(15, inp.prescribedReps + (last ? 1 : 0))
      return {
        suggestedWeightKg: null,
        suggestedReps: reps,
        source: last ? 'progression' : 'no_history',
        reason: last
          ? `Bodyweight progression: +1 rep over last (${last.reps} → ${reps}).`
          : 'Bodyweight: pick a rep target you can hit with clean form.',
      }
    }

    if (!last) {
      return {
        suggestedWeightKg: null,
        suggestedReps: inp.prescribedReps,
        source: 'no_history',
        reason: 'First time on this lift — start light, focus on form, leave 2-3 reps in reserve.',
      }
    }

    // Stall check: little or no e1RM progress in 30 days → hold weight.
    if (rank) {
      const ageDays = (Date.now() - rank.updatedAt.getTime()) / 86_400_000
      const e1rmTrend = Number(rank.bestE1rmKg)
      if (ageDays > STALL_THRESHOLD_DAYS && e1rmTrend > 0) {
        // Heuristic stall: e1RM hasn't moved enough recently — hold weight.
        // (A richer check would compare to historical samples; we approximate.)
        const lastEpley = last.weight * (1 + last.reps / 30)
        if (Math.abs(e1rmTrend - lastEpley) < STALL_E1RM_DELTA_KG) {
          return {
            suggestedWeightKg: roundToPlate(last.weight),
            suggestedReps: inp.prescribedReps,
            source: 'hold',
            reason: `Stalled near ${e1rmTrend.toFixed(1)}kg e1RM for ~${Math.round(ageDays)}d — hold and try +1 rep before adding load.`,
          }
        }
      }
    }

    const isCompound = COMPOUND_PATTERNS.has(meta?.movementPattern ?? '')
    // RPE-gated autoregulation: progress only when the last set was manageable,
    // hold when it was hard, deload when it was at/near failure. Falls back to a
    // plain linear bump when no RPE was logged (preserves prior behavior).
    // Kill-switch: ZVELT_AUTOREG=off forces the old always-bump path.
    const lastRpe = process.env.ZVELT_AUTOREG === 'off' ? null : last.rpe
    // Dispatch through the configurable scheme. With scheme='auto' (default)
    // this delegates verbatim to autoregulateLoad — identical to before.
    const decision = applyProgressionScheme({
      scheme,
      level,
      isCompound,
      autoreg: {
        level,
        isCompound,
        lastWeight: last.weight,
        lastReps: last.reps,
        lastRpe,
      },
      prescription: inp.lastPrescription ?? null,
      actual: {
        reps: last.reps,
        rpe: last.rpe,
        weightKg: last.weight,
      },
    })
    return {
      suggestedWeightKg: decision.suggestedWeightKg,
      // Schemes (e.g. double progression) may override the rep target; auto
      // returns undefined so the prescribed reps are kept (prior behavior).
      suggestedReps: decision.suggestedReps ?? inp.prescribedReps,
      source: decision.source,
      reason: decision.reason,
    }
  })
}

/** RPE thresholds for autoregulation (1.0–10.0 scale). */
const DELOAD_RPE = 9.5 // at/near failure → back off
const HOLD_RPE = 8.0 // hard (≤2 reps in reserve) → repeat, don't add load
const EASY_RPE = 6.0 // easy (≥4 reps in reserve) → accelerate the jump
const DELOAD_FACTOR = 0.9 // −10% on a deload
const ACCEL_MULTIPLIER = 1.5 // bigger jump when the last set was easy

export type AutoregInput = {
  level: ProgressionLevel
  isCompound: boolean
  lastWeight: number
  lastReps: number
  /** Max RPE across the last session's WORK sets for this lift; null if unlogged. */
  lastRpe: number | null
}

export type AutoregResult = {
  suggestedWeightKg: number
  source: 'progression' | 'hold' | 'deload'
  reason: string
}

/**
 * Decide the next working load for ONE lift from how the last set actually went.
 * Pure + unit-testable (no Prisma). The autoregulation layer the old open-loop
 * `bumpForLevel`-every-session lacked: it reads RPE (collected but previously
 * never consumed by any planner) and only progresses when the set was earned.
 *
 *  - no RPE logged → plain linear bump (identical to prior behavior).
 *  - RPE ≥ 9.5     → deload −10% (rebuild with clean reps).
 *  - RPE > 8.0     → hold (repeat to consolidate before adding load).
 *  - RPE ≤ 6.0     → accelerate (1.5× the normal bump — the set was easy).
 *  - otherwise     → normal bump.
 */
export function autoregulateLoad(inp: AutoregInput): AutoregResult {
  const { level, isCompound, lastWeight, lastReps, lastRpe } = inp
  const kind = isCompound ? 'compound' : 'accessory'

  // No RPE → fall back to the deterministic linear bump (prior behavior).
  if (lastRpe == null) {
    const bump = bumpForLevel(level, isCompound, lastWeight)
    const next = roundToPlate(lastWeight + bump)
    return {
      suggestedWeightKg: next,
      source: 'progression',
      reason:
        bump > 0
          ? `Last ${lastWeight}kg×${lastReps} → +${bump.toFixed(2)}kg (${level} ${kind}).`
          : `Last ${lastWeight}kg×${lastReps} held — advanced lifters progress on volume / reps, not weight every session.`,
    }
  }

  // At/near failure → back off to rebuild (the deload that never existed before).
  if (lastRpe >= DELOAD_RPE) {
    const next = roundToPlate(lastWeight * DELOAD_FACTOR)
    return {
      suggestedWeightKg: next,
      source: 'deload',
      reason: `Last set near failure (RPE ${lastRpe.toFixed(1)}) — back off to ${next}kg (−10%) and rebuild with clean reps.`,
    }
  }

  // Hard but not failing → repeat to consolidate (replaces the blind bump).
  if (lastRpe > HOLD_RPE) {
    const held = roundToPlate(lastWeight)
    return {
      suggestedWeightKg: held,
      source: 'hold',
      reason: `Hard last time (RPE ${lastRpe.toFixed(1)}) — repeat ${held}kg to consolidate before adding load.`,
    }
  }

  // Earned the jump. If it was easy (lots in reserve), accelerate it.
  const baseBump = bumpForLevel(level, isCompound, lastWeight)
  if (baseBump <= 0) {
    // Advanced lifters: no linear bump regardless of how easy it felt.
    return {
      suggestedWeightKg: roundToPlate(lastWeight),
      source: 'progression',
      reason: `Last ${lastWeight}kg×${lastReps} @RPE${lastRpe.toFixed(1)} held — advanced lifters progress on volume / reps, not weight every session.`,
    }
  }
  const accelerate = lastRpe <= EASY_RPE
  const bump = accelerate ? baseBump * ACCEL_MULTIPLIER : baseBump
  const next = roundToPlate(lastWeight + bump)
  return {
    suggestedWeightKg: next,
    source: 'progression',
    reason: accelerate
      ? `Easy at RPE ${lastRpe.toFixed(1)} (reps in reserve) → bigger jump +${bump.toFixed(2)}kg to ${next}kg.`
      : `Solid at RPE ${lastRpe.toFixed(1)} → +${bump.toFixed(2)}kg to ${next}kg (${level} ${kind}).`,
  }
}

/**
 * How much weight to add per session for a given user level + lift kind.
 * Exported for direct unit testing of the progression curve without needing
 * to mock the whole prisma call graph.
 */
export function bumpForLevel(level: ProgressionLevel, isCompound: boolean, lastWeight: number): number {
  if (isCompound) {
    if (level === 'beginner') return 2.5
    if (level === 'intermediate') return 1.25
    return 0
  }
  // Accessory: percentage-based
  if (level === 'beginner') return Math.max(1.25, lastWeight * 0.025)
  if (level === 'intermediate') return Math.max(0, lastWeight * 0.01)
  return 0
}

/** Round to nearest 2.5 kg plate step; minimum 5 kg. Exported for unit tests. */
export function roundToPlate(kg: number): number {
  const rounded = Math.round(kg / 2.5) * 2.5
  return Math.max(5, Math.round(rounded * 10) / 10)
}

// ---------------------------------------------------------------------------
// Block-level DELOAD weeks (periodization cadence)
// ---------------------------------------------------------------------------
//
// Distinct from the per-set RPE deload in `autoregulateLoad`. That one reacts to
// a single hard session. THIS one is planned, structural: every Nth training
// week the whole block backs off so accumulated fatigue can dissipate. It is the
// piece linear progression alone can't give — and it matters MOST for advanced
// lifters, where `bumpForLevel` already returns 0 (no weekly bump to back off
// from), so without a scheduled deload they'd just grind the same load forever.
//
// Cadence is computed from a week index relative to program start — no schema
// change, the caller derives the index from an existing anchor date (first
// workout) and the plan's weekStart.

/** Default periodization cadence: deload every 4th training week (3 on, 1 off). */
export const DEFAULT_DELOAD_CADENCE = 4

/** Block deload load reduction (−12%): mid-point of the ~−10..−15% range. */
export const BLOCK_DELOAD_FACTOR = 0.88

/** On a deload week, also trim one top set of volume (floor of 2 working sets). */
export const BLOCK_DELOAD_MIN_SETS = 2

const MS_PER_WEEK = 7 * 86_400_000

/**
 * Is the given training week a scheduled deload week?
 *
 * Accepts EITHER a zero-based week index since program start (a `number`) OR a
 * `{ start, current }` date pair from which the index is derived (whole weeks
 * elapsed, floored). Returns false for anything before/at the first week so a
 * brand-new program never opens on a deload.
 *
 * Cadence N means: weeks 0..N-2 are normal, week N-1 is a deload, then it
 * repeats. With the default cadence of 4 the deload lands on week index 3, 7,
 * 11, … (i.e. the 4th, 8th, 12th training week).
 *
 * Pure + deterministic — no Date.now(), the "current" date is always passed in.
 */
export function isDeloadWeek(
  weekIndexOrDate: number | { start: Date; current: Date },
  cadence: number = DEFAULT_DELOAD_CADENCE,
): boolean {
  // A cadence < 2 would make every week (or no week) a deload — disable instead.
  if (!Number.isFinite(cadence) || cadence < 2) return false

  const index = weekIndexFor(weekIndexOrDate)
  if (index == null || index < 0) return false

  // Deload on the last week of each block: index ≡ cadence-1 (mod cadence).
  return index % cadence === cadence - 1
}

/** Normalize the union arg into a zero-based whole-week index, or null. */
function weekIndexFor(arg: number | { start: Date; current: Date }): number | null {
  if (typeof arg === 'number') {
    return Number.isFinite(arg) ? Math.floor(arg) : null
  }
  const { start, current } = arg
  const a = start?.getTime?.()
  const b = current?.getTime?.()
  if (a == null || b == null || Number.isNaN(a) || Number.isNaN(b)) return null
  return Math.floor((b - a) / MS_PER_WEEK)
}

export type DeloadTransformInput = {
  /** Working load decided by normal progression for this lift; null = bodyweight/no-history. */
  suggestedWeightKg: number | null
  /** Prescribed working sets for this lift (top-set volume to trim). */
  sets: number
  /** Original reason string, surfaced when NOT a deload week. */
  reason: string
  /** Original load source, preserved when NOT a deload week. */
  source: OverloadDecision['source']
}

export type DeloadTransformResult = {
  suggestedWeightKg: number | null
  sets: number
  source: OverloadDecision['source']
  reason: string
}

/**
 * Apply the block-deload back-off to ONE lift's prescription. Behavior-preserving
 * when `deload` is false (returns the inputs untouched). On a deload week it:
 *
 *  - cuts prescribed load ~−12% (within the ~−10..−15% target), plate-rounded;
 *  - trims one working set of volume (floored at BLOCK_DELOAD_MIN_SETS);
 *  - forces source to 'deload' so any progression bump this week is SUPPRESSED —
 *    crucial for advanced lifters whose normal bump is already 0 and who would
 *    otherwise never get a scheduled recovery week.
 *
 * Bodyweight / no-history lifts (null weight) keep null but still get the volume
 * trim + the deload reason, so the whole session reads as a back-off week.
 *
 * Pure + unit-testable (no Prisma, no Date).
 */
export function applyBlockDeload(inp: DeloadTransformInput, deload: boolean): DeloadTransformResult {
  if (!deload) {
    return {
      suggestedWeightKg: inp.suggestedWeightKg,
      sets: inp.sets,
      source: inp.source,
      reason: inp.reason,
    }
  }

  const sets = Math.max(BLOCK_DELOAD_MIN_SETS, inp.sets - 1)
  const reason = 'Deload week — back off to recover (planned periodization). Suppressing this week’s progression so fatigue can clear.'

  if (inp.suggestedWeightKg == null) {
    return { suggestedWeightKg: null, sets, source: 'deload', reason }
  }

  const reduced = roundToPlate(inp.suggestedWeightKg * BLOCK_DELOAD_FACTOR)
  return { suggestedWeightKg: reduced, sets, source: 'deload', reason }
}
