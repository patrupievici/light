import { roundToPlate } from '../lib/progressive-overload'

/**
 * Percentage / training-max progression math for multi-week programs.
 *
 * This is the piece the history-driven `progression-schemes.ts` (linear/double/
 * reps_sum/auto for FREE workouts) does NOT cover: percentage-of-training-max
 * waves used by 5/3/1 and nSuns, where the prescribed load for a set is a % of a
 * stored Training Max (TM = 90% of 1RM), and TM climbs per cycle/week.
 *
 * PURE: no Prisma, no Date.now() — the program service resolves TM state and
 * passes plain numbers in, so every wave + rounding is unit-testable in isolation.
 *
 * Clean-room: 5/3/1 percentages are Wendler's published scheme; the nSuns set
 * shape mirrors the widely-published nSuns LP encoding (see docs/BUILD_SPEC_GYM).
 * No code/data copied from any AGPL project.
 */

export type MaterializedSet = {
  /** Plate-rounded working load in kg; null when TM is unknown (user hasn't set a 1RM). */
  weightKg: number | null
  /** Target reps for this set. */
  reps: number
  /** WORK vs WARMUP — warmups are generated separately and excluded from ranking. */
  tag: 'WORK' | 'WARMUP'
  /** AMRAP set (the "+" set) — drives TM progression on nSuns / explains effort on 5/3/1. */
  amrap?: boolean
  /** Fraction of training max this set targets (0–1), surfaced for the "why this weight" UI. */
  pctOfTM?: number
}

/** One step in a percentage wave: % of training max × target reps. */
export type PctStep = { pct: number; reps: number; amrap?: boolean }

export const TM_FRACTION = 0.9

// ── 5/3/1 (Wendler) main work, by week-in-cycle (1..4) ───────────────────────
// Week 4 is the planned deload. Cadence is 4 weeks; the wave itself carries the
// deload, so no separate deload transform is needed for percentage programs.
export function fiveThreeOneMainWave(weekInCycle: number): PctStep[] {
  const w = ((Math.max(1, Math.floor(weekInCycle)) - 1) % 4) + 1
  switch (w) {
    case 1:
      return [
        { pct: 0.65, reps: 5 },
        { pct: 0.75, reps: 5 },
        { pct: 0.85, reps: 5, amrap: true },
      ]
    case 2:
      return [
        { pct: 0.7, reps: 3 },
        { pct: 0.8, reps: 3 },
        { pct: 0.9, reps: 3, amrap: true },
      ]
    case 3:
      return [
        { pct: 0.75, reps: 5 },
        { pct: 0.85, reps: 3 },
        { pct: 0.95, reps: 1, amrap: true },
      ]
    default:
      // Week 4 — deload (no AMRAP, light).
      return [
        { pct: 0.4, reps: 5 },
        { pct: 0.5, reps: 5 },
        { pct: 0.6, reps: 5 },
      ]
  }
}

/** 5/3/1 "Boring But Big" supplemental: 5×10 at a fixed % of TM (default 50%). */
export function bbbSupplemental(pct = 0.5, sets = 5, reps = 10): PctStep[] {
  return Array.from({ length: sets }, () => ({ pct, reps }))
}

// ── nSuns LP set shapes (Liftosaur-encoded). Week-independent; TM climbs weekly. ─
export const NSUNS_T1: PctStep[] = [
  { pct: 0.75, reps: 5 },
  { pct: 0.85, reps: 3 },
  { pct: 0.95, reps: 1, amrap: true },
  { pct: 0.81, reps: 3 },
  { pct: 0.76, reps: 3 },
  { pct: 0.72, reps: 3 },
  { pct: 0.67, reps: 5 },
  { pct: 0.63, reps: 5 },
  { pct: 0.58, reps: 5, amrap: true },
]

export const NSUNS_T2: PctStep[] = [
  { pct: 0.45, reps: 5 },
  { pct: 0.54, reps: 5 },
  { pct: 0.63, reps: 3 },
  { pct: 0.63, reps: 5 },
  { pct: 0.63, reps: 7 },
  { pct: 0.63, reps: 4 },
  { pct: 0.63, reps: 6 },
  { pct: 0.63, reps: 8, amrap: true },
]

/** Resolve a named percentage wave to its steps for the given training week. */
export function resolveWave(wave: string, weekInCycle: number): PctStep[] {
  switch (wave) {
    case '531_main':
      return fiveThreeOneMainWave(weekInCycle)
    case '531_bbb':
      return bbbSupplemental()
    case 'nsuns_t1':
      return NSUNS_T1
    case 'nsuns_t2':
      return NSUNS_T2
    default:
      return []
  }
}

/** Build concrete WORK sets (plate-rounded) from a training max + wave steps. */
export function percentSetsFromTM(tmKg: number | null, steps: PctStep[]): MaterializedSet[] {
  return steps.map((s) => ({
    weightKg: tmKg != null && tmKg > 0 ? roundToPlate(tmKg * s.pct) : null,
    reps: s.reps,
    tag: 'WORK' as const,
    amrap: s.amrap,
    pctOfTM: Math.round(s.pct * 100) / 100,
  }))
}

// ── Training max lifecycle ───────────────────────────────────────────────────
/** Seed a training max from a tested/estimated 1RM (TM = 90% of 1RM). */
export function trainingMaxFromOneRm(oneRmKg: number): number {
  if (!Number.isFinite(oneRmKg) || oneRmKg <= 0) return 0
  return roundToPlate(oneRmKg * TM_FRACTION)
}

/**
 * Per-cycle training-max increment (Wendler): lower-body lifts +5kg, upper-body
 * +2.5kg. Applied by the program service when a cycle (or week, for nSuns) closes.
 */
export function incrementTrainingMax(tmKg: number, isLowerBody: boolean): number {
  if (!Number.isFinite(tmKg) || tmKg <= 0) return tmKg
  return roundToPlate(tmKg + (isLowerBody ? 5 : 2.5))
}
