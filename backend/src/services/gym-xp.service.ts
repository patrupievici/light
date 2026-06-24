/**
 * XP / level curve from gym_rpg_app.html (WORLD_RECORDS, LEVEL_THRESHOLDS, formulas).
 */
import { ageXpBonus, type UserXpContext } from './cardio-xp.service'

export const LEVEL_THRESHOLDS = [0, 500, 1500, 3500, 7500, 15000, 30000, 60000, 120000, 250000] as const
export const LEVEL_NAMES = [
  'Recruit',
  'Iron I',
  'Iron II',
  'Bronze',
  'Silver',
  'Gold',
  'Platinum',
  'Diamond',
  'Master',
  'Legend',
] as const

type WrSpec = {
  wrKg?: number
  wrSeconds?: number
  base: number
  fatigue: number
  bodyweight: boolean
  time: boolean
}

/** Canonical WR table (gym_rpg_app.html). */
const WORLD_RECORDS: Record<string, WrSpec> = {
  Deadlift: { wrKg: 501, base: 15, fatigue: 12, bodyweight: false, time: false },
  Squat: { wrKg: 477, base: 14, fatigue: 11, bodyweight: false, time: false },
  'Bench Press': { wrKg: 349, base: 12, fatigue: 8, bodyweight: false, time: false },
  'Overhead Press': { wrKg: 216, base: 11, fatigue: 7, bodyweight: false, time: false },
  'Barbell Row': { wrKg: 260, base: 11, fatigue: 8, bodyweight: false, time: false },
  'Pull-up': { base: 10, fatigue: 7, bodyweight: true, time: false },
  Dip: { base: 9, fatigue: 6, bodyweight: true, time: false },
  'Bicep Curl': { wrKg: 132, base: 8, fatigue: 4, bodyweight: false, time: false },
  'Tricep Extension': { wrKg: 130, base: 8, fatigue: 4, bodyweight: false, time: false },
  'Leg Press': { wrKg: 820, base: 12, fatigue: 9, bodyweight: false, time: false },
  'Romanian Deadlift': { wrKg: 380, base: 12, fatigue: 9, bodyweight: false, time: false },
  Plank: { wrSeconds: 9 * 3600 + 38 * 60, base: 8, fatigue: 3, bodyweight: true, time: true },
  'Push-up': { base: 6, fatigue: 4, bodyweight: true, time: false },
}

/** Map seed / UI exercise names → same stats as a known lift (or approximate). */
const NAME_ALIASES: Record<string, keyof typeof WORLD_RECORDS> = {
  'front squat': 'Squat',
  'dumbbell press': 'Bench Press',
  'dumbbell row': 'Barbell Row',
  'dumbbell curl': 'Bicep Curl',
  'lateral raise': 'Bicep Curl',
  'dumbbell lunge': 'Squat',
  'lat pulldown': 'Barbell Row',
  'cable row': 'Barbell Row',
  'chest fly': 'Bench Press',
  'tricep pushdown': 'Tricep Extension',
  'leg curl': 'Romanian Deadlift',
  'leg extension': 'Leg Press',
  'hip thrust': 'Romanian Deadlift',
  'power clean': 'Deadlift',
  'hang clean': 'Deadlift',
  'power snatch': 'Deadlift',
  'push press': 'Overhead Press',
  'box jump': 'Squat',
  'vertical jump': 'Squat',
  'broad jump': 'Squat',
  'jump squat': 'Squat',
  'burpee': 'Push-up',
  'depth jump': 'Squat',
  'lateral bound': 'Squat',
  'clap push-up': 'Push-up',
}

function normalizeName(name: string): string {
  return name.trim().toLowerCase()
}

function worldRecordByName(name: string): WrSpec | null {
  const n = normalizeName(name)
  for (const [k, v] of Object.entries(WORLD_RECORDS)) {
    if (normalizeName(k) === n) return { ...v }
  }
  return null
}

function resolveSpec(exerciseName: string, rankModel: string, fatigueScore: number): WrSpec {
  const n = normalizeName(exerciseName)
  const aliasTarget = NAME_ALIASES[n]
  if (aliasTarget && WORLD_RECORDS[aliasTarget]) {
    return { ...WORLD_RECORDS[aliasTarget] }
  }
  const direct = worldRecordByName(exerciseName)
  if (direct) return direct

  if (rankModel === 'TIME') {
    return {
      wrSeconds: 3600,
      base: 8,
      fatigue: Math.min(10, Math.max(3, fatigueScore * 2)),
      bodyweight: false,
      time: true,
    }
  }
  if (rankModel === 'BW_REPS') {
    return {
      base: 8,
      fatigue: Math.min(10, Math.max(3, fatigueScore * 2)),
      bodyweight: true,
      time: false,
    }
  }

  const fatigue = Math.min(10, Math.max(4, fatigueScore * 3))
  return { wrKg: 250, base: 10, fatigue, bodyweight: false, time: false }
}

/**
 * XP multiplier as a function of % of world record.
 *
 * Was a step function (1/2/4/8/16/32 at 20/40/60/80/100) which had jarring
 * jumps: someone hitting 79% got 8×, hitting 80% got 16× — a 1% lift change
 * doubled their XP. The smooth curve below avoids that and matches the
 * intuition that "closer to WR = exponentially more meaningful":
 *
 *   mult = 1 + 31 × (pct / 100)^1.8
 *
 * Endpoints preserved (0% → 1, 100% → 32) so historical XP totals don't
 * shift wildly. Exponent 1.8 keeps mid-range values close to the old step
 * table but removes the cliffs. Example values:
 *
 *   pct=10 → 1.5   (was 1)
 *   pct=20 → 2.5   (was 2)
 *   pct=40 → 6.5   (was 4)
 *   pct=60 → 13.3  (was 8)
 *   pct=80 → 22.0  (was 16)
 *   pct=90 → 26.9  (was 16)
 *   pct=100 → 32   (was 32)
 *
 * Calling it "logarithmic" is colloquial — strict log would explode at the
 * top; power-curve is the closest smooth analogue that keeps WR effort
 * still feeling rewarding without overpaying mid-range lifters.
 */
export function getWrMultiplier(pct: number): number {
  const clamped = Math.max(0, Math.min(110, pct))
  const norm = clamped / 100
  const mult = 1 + 31 * Math.pow(norm, 1.8)
  // Round to 2 decimals so the UI can show "8.24×" without float noise.
  return Math.round(mult * 100) / 100
}

function computePct(weightKg: number, bodyweightKg: number, spec: WrSpec): number {
  let pct = 0
  if (spec.time && spec.wrSeconds) {
    pct = (weightKg / spec.wrSeconds) * 100
  } else if (spec.bodyweight) {
    pct = (weightKg / (bodyweightKg * 1.5)) * 100
  } else if (spec.wrKg) {
    pct = (weightKg / spec.wrKg) * 100
  }
  return Math.min(Math.round(pct), 110)
}

/**
 * XP for one "block" (HTML: base × mult × sets × reps), with session fatigue penalty.
 */
export function calcXpBlock(
  weightKg: number,
  sets: number,
  reps: number,
  bodyweightKg: number,
  spec: WrSpec,
  sessionFatigue: number,
): { xp: number; pct: number; mult: number } {
  const pct = computePct(weightKg, bodyweightKg, spec)
  const mult = getWrMultiplier(pct)
  const rawXp = spec.base * mult * sets * reps
  const fatiguePenalty = Math.max(0.5, 1 - sessionFatigue / 200)
  return { xp: Math.round(rawXp * fatiguePenalty), pct, mult }
}

export function fatigueAfterExerciseBlock(spec: WrSpec, pct: number, sets: number): number {
  return Math.round(spec.fatigue * (1 + pct / 200) * (sets / 2))
}

export type ExerciseForXp = {
  name: string
  rankModel: string
  fatigueScore: number
  category: string
  equipment: string | null
  sets: { weightKg: number; reps: number; tag: string; isCompleted: boolean }[]
}

/** Load used in XP formula: explicit kg, or profile BW for logged BW work at 0 kg. */
function effectiveLoadKg(
  weightKg: number,
  bodyweightKg: number,
  ex: Pick<ExerciseForXp, 'rankModel' | 'equipment' | 'category'>,
): number {
  if (weightKg > 0) return weightKg
  if (ex.rankModel === 'BW_REPS' && (ex.equipment ?? '').toLowerCase() === 'bodyweight') {
    return bodyweightKg
  }
  return 0
}

/**
 * Sum XP for a completed workout: processes exercises in order, then completed WORK sets
 * (per set: sets=1,reps=reps), accumulating fatigue like the HTML prototype.
 *
 * Pass [userContext] to apply the age multiplier (older lifters get more XP
 * for the same lift — the same curve cardio already uses). When omitted the
 * function behaves as before (no bonus) so older callers don't break.
 */
export function computeWorkoutGameXp(
  exercisesOrdered: ExerciseForXp[],
  bodyweightKg: number,
  userContext?: UserXpContext,
): { sessionXp: number; ageMultiplier: number } {
  let fatigue = 0
  let sessionXp = 0
  const bw = bodyweightKg >= 30 && bodyweightKg <= 250 ? bodyweightKg : 80

  for (const we of exercisesOrdered) {
    const spec = resolveSpec(we.name, we.rankModel, we.fatigueScore)
    const workSets = we.sets.filter((s) => {
      if (!s.isCompleted || s.tag !== 'WORK' || s.reps <= 0) return false
      return effectiveLoadKg(s.weightKg, bw, we) > 0
    })
    if (workSets.length === 0) continue

    for (const s of workSets) {
      const load = effectiveLoadKg(s.weightKg, bw, we)
      const { xp, pct } = calcXpBlock(load, 1, s.reps, bw, spec, fatigue)
      sessionXp += xp
      fatigue = Math.min(100, fatigue + fatigueAfterExerciseBlock(spec, pct, 1))
    }
  }

  // Apply age bonus AFTER summing so the curve hits consistently regardless
  // of set count. Same function cardio uses — fair across modalities.
  const ageMultiplier = userContext ? ageXpBonus(userContext.ageYears) : 1
  const adjusted = Math.round(sessionXp * ageMultiplier)
  return { sessionXp: adjusted, ageMultiplier }
}

export function levelFromTotalXp(totalXp: number): {
  level: number
  levelName: string
  xpIntoLevel: number
  xpForNextLevel: number
  progressFraction: number
} {
  let lvl = 1
  for (let i = 1; i < LEVEL_THRESHOLDS.length; i++) {
    if (totalXp >= LEVEL_THRESHOLDS[i]) lvl = i + 1
  }
  lvl = Math.min(lvl, LEVEL_NAMES.length)
  const curThresh = LEVEL_THRESHOLDS[lvl - 1] ?? 0
  const nextThresh = LEVEL_THRESHOLDS[lvl] ?? LEVEL_THRESHOLDS[LEVEL_THRESHOLDS.length - 1]
  const span = nextThresh - curThresh
  const xpIntoLevel = totalXp - curThresh
  const maxLevel = lvl >= LEVEL_NAMES.length && span <= 0
  const xpForNextLevel = maxLevel ? 0 : span
  const progressFraction = maxLevel ? 1 : span > 0 ? Math.min(1, xpIntoLevel / span) : 1
  return {
    level: lvl,
    levelName: LEVEL_NAMES[lvl - 1] ?? LEVEL_NAMES[0],
    xpIntoLevel,
    xpForNextLevel,
    progressFraction,
  }
}

export function gameXpPayload(totalXp: number) {
  const l = levelFromTotalXp(totalXp)
  return {
    totalXp,
    level: l.level,
    levelName: l.levelName,
    xpIntoLevel: l.xpIntoLevel,
    xpForNextLevel: l.xpForNextLevel,
    progressFraction: l.progressFraction,
  }
}
