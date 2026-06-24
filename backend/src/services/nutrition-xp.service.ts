import { ageXpBonus, type UserXpContext } from './cardio-xp.service'

/**
 * XP for hitting daily nutrition targets.
 *
 * Nutrition has no "world record" the way lifts do — being on-target is a
 * binary-ish achievement, not a percentile. So instead of a power curve we
 * pay a flat XP per macro hit, weighted by difficulty: protein is hardest
 * to hit accurately, fat is easiest.
 *
 * The age bonus from cardio/gym applies here too so older users with the
 * same effort earn slightly more — same fairness principle across modalities.
 *
 * Caller awards this once per local day to avoid double-claim. We don't
 * enforce that here — that's a write-once concern in the route handler.
 */

export type DailyTargets = {
  calories?: number | null
  proteinG?: number | null
  carbsG?: number | null
  fatG?: number | null
}

export type DailyActual = {
  calories: number
  proteinG: number
  carbsG: number
  fatG: number
}

export type NutritionXpLine = {
  macro: 'calories' | 'protein' | 'carbs' | 'fat'
  pctOfTarget: number
  hit: boolean
  xp: number
}

export type NutritionXpResult = {
  sessionXp: number
  ageMultiplier: number
  bonusApplied: boolean
  breakdown: NutritionXpLine[]
}

/** ±10% of target counts as "hit" (matches common nutrition coaching). */
const TOLERANCE = 0.10

/** Per-macro base XP. Protein is intentionally higher — it's the hardest to land. */
const BASE_XP = {
  calories: 30,
  protein: 40,
  carbs: 20,
  fat: 20,
} as const

/** Bonus when ALL FOUR macros land — rewards true tracking discipline. */
const FULL_HIT_BONUS = 40

function withinTolerance(actual: number, target: number): { hit: boolean; pct: number } {
  if (target <= 0) return { hit: false, pct: 0 }
  const ratio = actual / target
  const pct = Math.round(ratio * 100)
  return { hit: Math.abs(ratio - 1) <= TOLERANCE, pct }
}

export function computeNutritionDayXp(
  targets: DailyTargets,
  actual: DailyActual,
  userContext?: UserXpContext,
): NutritionXpResult {
  const macros: Array<{ key: 'calories' | 'protein' | 'carbs' | 'fat'; tgt: number; act: number }> = [
    { key: 'calories', tgt: targets.calories ?? 0, act: actual.calories },
    { key: 'protein', tgt: Number(targets.proteinG ?? 0), act: actual.proteinG },
    { key: 'carbs', tgt: Number(targets.carbsG ?? 0), act: actual.carbsG },
    { key: 'fat', tgt: Number(targets.fatG ?? 0), act: actual.fatG },
  ]

  const breakdown: NutritionXpLine[] = []
  let earned = 0
  let hitsWithTargets = 0
  let targetsSet = 0

  for (const m of macros) {
    if (m.tgt <= 0) {
      // No target set for this macro → cannot award; skip silently.
      breakdown.push({ macro: m.key, pctOfTarget: 0, hit: false, xp: 0 })
      continue
    }
    targetsSet++
    const { hit, pct } = withinTolerance(m.act, m.tgt)
    const xp = hit ? BASE_XP[m.key] : 0
    if (hit) {
      hitsWithTargets++
      earned += xp
    }
    breakdown.push({ macro: m.key, pctOfTarget: pct, hit, xp })
  }

  // Full hit bonus only if the user *had* targets for all 4 macros.
  const bonusApplied = targetsSet === 4 && hitsWithTargets === 4
  if (bonusApplied) earned += FULL_HIT_BONUS

  const ageMultiplier = userContext ? ageXpBonus(userContext.ageYears) : 1
  const sessionXp = Math.round(earned * ageMultiplier)

  return {
    sessionXp,
    ageMultiplier,
    bonusApplied,
    breakdown,
  }
}
