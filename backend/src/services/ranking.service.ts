import { prisma } from '../lib/prisma'
import { getCanonicalBodyweightKg } from '../lib/bodyweight'

// ─── Constante ───────────────────────────────────────────────────────────────

const MAX_REPS_FOR_E1RM = 12
const MAX_E1RM_KG = 600
const MAX_SR = 6.0
const TOP_N_EXERCISES = 10

// Praguri SR pentru fiecare tier (per gender + bw_band - simplificat MVP)
const SR_THRESHOLDS: Record<string, number[]> = {
  WEIGHTED_HEAVY: [0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0],
  WEIGHTED_UPPER: [0.3, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
  WEIGHTED: [0.4, 0.6, 0.85, 1.2, 1.6, 2.0, 2.5],
}

/** BW_REPS: SR = e1RM/BW ≈ fracțiune×(1+r/30) — praguri mai joase decât gantere. */
const SR_THRESHOLDS_BW_VERTICAL = [0.52, 0.68, 0.82, 0.95, 1.08, 1.22, 1.38]
const SR_THRESHOLDS_BW_HORIZONTAL = [0.36, 0.46, 0.54, 0.62, 0.7, 0.78, 0.88]
const SR_THRESHOLDS_BW_LOWER = [0.42, 0.55, 0.68, 0.8, 0.93, 1.05, 1.18]

const TIER_NAMES = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Olympian']

// ─── Data-driven exercise→threshold mapping ────────────────────────────────────
//
// Previously the threshold / strength-standard selection was a hand-rolled chain
// of `if (name.includes('squat')) ...` branches scattered across three
// functions. That was fragile (order-sensitive, easy to break with a typo, and
// invisible to tests). We replace the control flow with declarative *data*: an
// ordered list of keyword rules per concern. The matching semantics are
// identical to the old chains (first matching rule wins, substring match on the
// lower-cased name, otherwise a documented fallback), so numeric outcomes for
// every known exercise are preserved — but the mapping is now a single table
// that can be unit-tested and audited at a glance.

/** One rule: if any keyword is a substring of the (lower-cased) name → value. */
export interface KeywordRule<T> {
  /** Substrings to look for in the lower-cased exercise name (OR-matched). */
  match: string[]
  value: T
}

/**
 * Resolve a value from an ordered rule table. First rule with a matching
 * keyword wins (preserving the original if/else precedence); none → fallback.
 */
export function resolveByKeyword<T>(
  name: string,
  rules: ReadonlyArray<KeywordRule<T>>,
  fallback: T,
): T {
  const n = name.toLowerCase()
  for (const rule of rules) {
    if (rule.match.some((kw) => n.includes(kw))) return rule.value
  }
  return fallback
}

type WeightedBand = keyof typeof SR_THRESHOLDS

/** WEIGHTED model: name keywords → SR threshold band. (was getSRThresholds) */
export const WEIGHTED_THRESHOLD_RULES: ReadonlyArray<KeywordRule<WeightedBand>> = [
  { match: ['squat', 'deadlift', 'hip thrust'], value: 'WEIGHTED_HEAVY' },
  { match: ['bench', 'press', 'row'], value: 'WEIGHTED_UPPER' },
]

type BwThresholdKind = 'VERTICAL' | 'HORIZONTAL' | 'LOWER'

const SR_THRESHOLDS_BW: Record<BwThresholdKind, number[]> = {
  VERTICAL: SR_THRESHOLDS_BW_VERTICAL,
  HORIZONTAL: SR_THRESHOLDS_BW_HORIZONTAL,
  LOWER: SR_THRESHOLDS_BW_LOWER,
}

/** BW_REPS model: name keywords → SR threshold kind. (was getSRThresholdsBw) */
export const BW_THRESHOLD_RULES: ReadonlyArray<KeywordRule<BwThresholdKind>> = [
  { match: ['pull', 'chin', 'dip'], value: 'VERTICAL' },
  {
    match: ['squat', 'lunge', 'jump', 'box', 'bound', 'depth', 'sprint', 'burpee'],
    value: 'LOWER',
  },
]

// BW_REPS model: name keywords → inferred bodyweight strength fraction.
// (was inferBwStrengthFraction) Only used when the DB column is absent. Split
// around the compound "squat && !jump" branch so the original if/else
// precedence is preserved exactly — see inferBwStrengthFraction below.
export const BW_FRACTION_RULES_BEFORE_SQUAT: ReadonlyArray<KeywordRule<number>> = [
  { match: ['pull', 'chin'], value: 1.0 },
  { match: ['dip'], value: 0.95 },
  { match: ['push', 'push-up', 'push up'], value: 0.64 },
  { match: ['inverted row', 'australian'], value: 0.65 },
]

export const BW_FRACTION_RULES_AFTER_SQUAT: ReadonlyArray<KeywordRule<number>> = [
  { match: ['good morning'], value: 0.45 },
  { match: ['lunge'], value: 0.88 },
  { match: ['jump', 'box', 'bound', 'depth'], value: 1.0 },
  { match: ['burpee'], value: 0.72 },
  { match: ['sprint'], value: 0.85 },
]

// ─── Formule ─────────────────────────────────────────────────────────────────

export function calcE1RM(weightKg: number, reps: number): number | null {
  if (reps < 1 || reps > MAX_REPS_FOR_E1RM) return null
  if (weightKg <= 0) return null
  return weightKg * (1 + reps / 30)
}

export function calcStrengthRatio(e1rm: number, bodyweightKg: number): number {
  return e1rm / bodyweightKg
}

export function getSRThresholds(exerciseName: string): number[] {
  const band = resolveByKeyword(exerciseName, WEIGHTED_THRESHOLD_RULES, 'WEIGHTED')
  return SR_THRESHOLDS[band]
}

export function getSRThresholdsBw(exerciseName: string): number[] {
  const kind = resolveByKeyword(exerciseName, BW_THRESHOLD_RULES, 'HORIZONTAL')
  return SR_THRESHOLDS_BW[kind]
}

// Returneaza LP (0-699) bazat pe SR
export function srToLP(sr: number, exerciseName: string, rankModel: string = 'WEIGHTED'): number {
  const thresholds =
    rankModel === 'BW_REPS' ? getSRThresholdsBw(exerciseName) : getSRThresholds(exerciseName)
  const clampedSr = Math.min(sr, MAX_SR)

  let tierIndex = 0
  for (let i = thresholds.length - 1; i >= 0; i--) {
    if (clampedSr >= thresholds[i]) {
      tierIndex = i
      break
    }
  }

  const tierMin = thresholds[tierIndex] ?? 0
  const tierMax = thresholds[tierIndex + 1] ?? thresholds[tierIndex] * 1.5

  const progressInTier = Math.max(0, Math.min(1, (clampedSr - tierMin) / (tierMax - tierMin)))
  const lp = Math.floor(tierIndex * 100 + progressInTier * 100)

  return Math.max(0, Math.min(699, lp))
}

export function lpToTier(lp: number): string {
  const tierIndex = Math.min(Math.floor(lp / 100), TIER_NAMES.length - 1)
  return TIER_NAMES[tierIndex]
}

// ─── Bodyweight (BW_REPS) ───────────────────────────────────────────────────

const BW_FRACTION_FALLBACK = 0.7

/** Dacă DB nu are `bwStrengthFraction`, deducem din nume (MVP).
 *  Data-driven via BW_FRACTION_RULES; the "squat & not jump" branch is a
 *  compound condition that does not fit the plain OR-keyword table, so it is
 *  applied explicitly here at its original precedence (after inverted-row,
 *  before good-morning). Outcomes are identical to the prior if/else chain. */
export function inferBwStrengthFraction(exerciseName: string): number {
  const n = exerciseName.toLowerCase()
  // Rules that precede the squat branch.
  for (const rule of BW_FRACTION_RULES_BEFORE_SQUAT) {
    if (rule.match.some((kw) => n.includes(kw))) return rule.value
  }
  // Original compound branch: squat but NOT a jump-squat variant.
  if (n.includes('squat') && !n.includes('jump')) return 1.0
  // Rules that follow the squat branch.
  for (const rule of BW_FRACTION_RULES_AFTER_SQUAT) {
    if (rule.match.some((kw) => n.includes(kw))) return rule.value
  }
  return BW_FRACTION_FALLBACK
}

export function resolveBwStrengthFraction(
  exerciseName: string,
  rankModel: string,
  bwStrengthFraction: unknown,
): number {
  if (rankModel !== 'BW_REPS') return 1
  if (bwStrengthFraction != null) {
    const v =
      typeof bwStrengthFraction === 'object' &&
      bwStrengthFraction !== null &&
      'toNumber' in bwStrengthFraction &&
      typeof (bwStrengthFraction as { toNumber: () => number }).toNumber === 'function'
        ? (bwStrengthFraction as { toNumber: () => number }).toNumber()
        : Number(bwStrengthFraction)
    if (Number.isFinite(v) && v > 0 && v <= 2.5) return v
  }
  return inferBwStrengthFraction(exerciseName)
}

export interface BestWorkSetRankResult {
  e1rm: number
  weightKg: number
  reps: number
}

type RankableSet = { weightKg: unknown; reps: number; tag: string; isCompleted: boolean }

/** Cel mai bun set WORK pentru rang (WEIGHTED sau BW_REPS). */
export function bestWorkSetForRank(
  exercise: {
    name: string
    rankModel: string
    isRanked: boolean
    bwStrengthFraction: unknown
  },
  bodyweightKg: number,
  sets: RankableSet[],
): BestWorkSetRankResult | null {
  if (!exercise.isRanked) return null
  if (exercise.rankModel !== 'WEIGHTED' && exercise.rankModel !== 'BW_REPS') return null

  let best: BestWorkSetRankResult | null = null

  const fraction =
    exercise.rankModel === 'BW_REPS'
      ? resolveBwStrengthFraction(exercise.name, exercise.rankModel, exercise.bwStrengthFraction)
      : 1

  for (const set of sets) {
    if (set.tag !== 'WORK' || !set.isCompleted) continue

    const added = Number(set.weightKg)
    const reps = set.reps

    let loadKg: number
    if (exercise.rankModel === 'WEIGHTED') {
      if (!Number.isFinite(added) || added <= 0) continue
      loadKg = added
    } else {
      if (!Number.isFinite(added) || added < 0) continue
      loadKg = bodyweightKg * fraction + Math.max(0, added)
    }

    const e1rm = calcE1RM(loadKg, reps)
    if (e1rm === null || e1rm > MAX_E1RM_KG) continue

    if (best === null || e1rm > best.e1rm) {
      best = { e1rm, weightKg: Number.isFinite(added) ? added : 0, reps }
    }
  }

  return best
}

// ─── Calcul principal ─────────────────────────────────────────────────────────

export interface RankResult {
  exerciseId: string
  exerciseName: string
  bestE1rmKg: number
  strengthRatio: number
  lpTotal: number
  lpDelta: number
  tier: string
  isAnomaly: boolean
}

export interface ComputeRanksResult {
  results: RankResult[]
  overallLpDelta: number
  seasonLpDelta: number
}

export async function computeRanks(
  userId: string,
  workoutId: string,
): Promise<ComputeRanksResult> {
  const profile = await prisma.userProfile.findUnique({ where: { userId } })
  // Bodyweight comes from the single canonical source (lib/bodyweight) so every
  // consumer coerces the Decimal column the same way.
  const bw = getCanonicalBodyweightKg(profile)
  if (bw == null) {
    throw new Error('BW_REQUIRED')
  }

  // Anti-cheat: reject impossible bodyweights instead of computing a rank from
  // garbage. Validated server-side even though the client also range-checks.
  if (!Number.isFinite(bw) || bw < 30 || bw > 250) {
    throw new Error('BW_INVALID')
  }

  const workout = await prisma.workout.findUnique({
    where: { id: workoutId },
    include: {
      exercises: {
        include: {
          exercise: true,
          sets: true,
        },
      },
    },
  })

  if (!workout) throw new Error('WORKOUT_NOT_FOUND')

  const results: RankResult[] = []

  for (const we of workout.exercises) {
    const ex = we.exercise
    if (!ex.isRanked) continue
    if (ex.rankModel !== 'WEIGHTED' && ex.rankModel !== 'BW_REPS') continue

    const best = bestWorkSetForRank(ex, bw, we.sets)
    if (!best) continue

    const bestE1rm = best.e1rm
    const sr = calcStrengthRatio(bestE1rm, bw)
    if (sr > MAX_SR) continue

    const newLp = srToLP(sr, ex.name, ex.rankModel)
    const tier = lpToTier(newLp)

    const prevRank = await prisma.userExerciseRank.findUnique({
      where: { userId_exerciseId: { userId, exerciseId: we.exerciseId } },
    })

    const prevLp = prevRank?.lpTotal ?? 0
    const lpDelta = newLp - prevLp

    const prevSr = prevRank ? Number(prevRank.strengthRatio) : 0
    const isAnomaly = prevSr > 0 && sr > prevSr * 1.2

    await prisma.userExerciseRank.upsert({
      where: { userId_exerciseId: { userId, exerciseId: we.exerciseId } },
      update: {
        bestE1rmKg: bestE1rm,
        strengthRatio: sr,
        lpTotal: Math.max(newLp, prevLp),
      },
      create: {
        userId,
        exerciseId: we.exerciseId,
        bestE1rmKg: bestE1rm,
        strengthRatio: sr,
        lpTotal: newLp,
      },
    })

    results.push({
      exerciseId: we.exerciseId,
      exerciseName: ex.name,
      bestE1rmKg: Math.round(bestE1rm * 10) / 10,
      strengthRatio: Math.round(sr * 1000) / 1000,
      lpTotal: newLp,
      lpDelta,
      tier,
      isAnomaly,
    })
  }

  const overallLpDelta = results
    .sort((a, b) => b.lpTotal - a.lpTotal)
    .slice(0, TOP_N_EXERCISES)
    .reduce((sum, r) => sum + r.lpDelta, 0)

  const seasonLpDelta = Math.max(0, overallLpDelta)
  const activeSeason = await prisma.season.findFirst({
    where: {
      startsAt: { lte: new Date() },
      endsAt: { gte: new Date() },
    },
  })

  if (activeSeason && seasonLpDelta > 0) {
    await prisma.userSeasonStat.upsert({
      where: { seasonId_userId: { seasonId: activeSeason.id, userId } },
      update: { lpSeason: { increment: seasonLpDelta } },
      create: { seasonId: activeSeason.id, userId, lpSeason: seasonLpDelta },
    })
  }

  return { results, overallLpDelta, seasonLpDelta }
}
