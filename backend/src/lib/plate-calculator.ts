/**
 * Plate calculator — turn a target barbell load into the exact per-side plate
 * stack a user can build from their own inventory, and report the nearest
 * achievable weight when the exact target can't be made.
 *
 * Pure + unit-testable (no Prisma, no Date): the route reads the user's
 * UserTrainingProfile.plateInventoryKg / barbellKg and passes plain numbers in.
 *
 * Conventions (Zvelt canonical metric storage — everything in kg):
 *  - A barbell is loaded SYMMETRICALLY: plates go on in equal pairs, one stack
 *    per side. So the loadable weight beyond the bar must be split evenly and is
 *    always an even multiple of the per-side total.
 *  - `inventoryKg` is the list of plate denominations the user OWNS, expressed as
 *    PAIRS available. A count of 2 of a 20kg plate means one pair → one 20 on
 *    each side. We model inventory as { kg, pairs } so a greedy fill never asks
 *    for a plate the user doesn't physically have.
 *
 * Clean-room: greedy largest-first fill with a bounded inventory is standard
 * arithmetic; the data shapes + rounding policy here are Zvelt's own.
 */

/** Default Olympic barbell weight when the profile doesn't specify one. */
export const DEFAULT_BARBELL_KG = 20

/** Standard metric plate denominations (kg), largest first. */
export const STANDARD_PLATES_KG = [25, 20, 15, 10, 5, 2.5, 1.25] as const

/** A plate denomination and how many PAIRS of it the user owns. */
export type PlatePair = {
  /** Plate weight in kg (one plate). */
  kg: number
  /** Number of PAIRS available (one pair = one plate per side). */
  pairs: number
}

export type PlateStackInput = {
  /** Desired total barbell weight in kg (bar + all plates). */
  targetKg: number
  /** Bar weight in kg. Defaults to DEFAULT_BARBELL_KG when null/invalid. */
  barbellKg?: number | null
  /** Owned plate inventory. Defaults to an unlimited STANDARD set when null. */
  inventory?: PlatePair[] | null
}

export type PlateStackResult = {
  /** The bar weight used. */
  barbellKg: number
  /** Per-side plate stack, largest plate first (kg values, repeated by count). */
  perSideKg: number[]
  /** The total weight actually achievable with this stack (bar + 2×per-side). */
  achievableKg: number
  /** True when achievableKg exactly equals the (clamped) target. */
  exact: boolean
  /** Signed kg difference: achievable − requested target (negative = under). */
  deltaKg: number
}

/**
 * Parse the raw plateInventoryKg JSON column into a clean PlatePair[]. Accepts
 * either:
 *  - a flat array of plate kg values (each entry = one PAIR owned), e.g.
 *    [20, 20, 10, 5] → two pairs of 20, one of 10, one of 5; or
 *  - an array of { kg, pairs } objects.
 *
 * Invalid / non-positive entries are dropped. Returns null when nothing usable
 * is present so callers can fall back to the unlimited standard set.
 */
export function parsePlateInventory(raw: unknown): PlatePair[] | null {
  if (!Array.isArray(raw)) return null

  const byKg = new Map<number, number>()
  for (const entry of raw) {
    let kg: number | null = null
    let pairs = 1
    if (typeof entry === 'number') {
      kg = entry
    } else if (entry && typeof entry === 'object') {
      const o = entry as Record<string, unknown>
      const k = Number(o.kg)
      const p = Number(o.pairs)
      if (Number.isFinite(k)) kg = k
      if (Number.isFinite(p)) pairs = p
    }
    if (kg == null || !Number.isFinite(kg) || kg <= 0) continue
    if (!Number.isFinite(pairs) || pairs <= 0) continue
    byKg.set(kg, (byKg.get(kg) ?? 0) + Math.floor(pairs))
  }

  if (byKg.size === 0) return null
  // Largest plate first for the greedy fill.
  return Array.from(byKg.entries())
    .map(([kg, pairs]) => ({ kg, pairs }))
    .sort((a, b) => b.kg - a.kg)
}

/** Resolve the effective bar weight (positive finite, else the default). */
function resolveBar(barbellKg: number | null | undefined): number {
  return typeof barbellKg === 'number' && Number.isFinite(barbellKg) && barbellKg > 0
    ? barbellKg
    : DEFAULT_BARBELL_KG
}

/** Build the working inventory: provided pairs, or an unlimited standard set. */
function resolveInventory(inventory: PlatePair[] | null | undefined): PlatePair[] {
  if (inventory && inventory.length > 0) {
    return [...inventory]
      .filter((p) => Number.isFinite(p.kg) && p.kg > 0 && Number.isFinite(p.pairs) && p.pairs > 0)
      .sort((a, b) => b.kg - a.kg)
  }
  // Unlimited standard set (large pair count stands in for "as many as needed").
  return STANDARD_PLATES_KG.map((kg) => ({ kg, pairs: 1000 }))
}

/**
 * Greedily fill ONE side toward `perSideTargetKg` using the largest plate that
 * fits and is still in stock. Returns the chosen plates (kg, largest first) and
 * the weight actually placed per side.
 */
function fillSide(
  perSideTargetKg: number,
  inventory: PlatePair[],
): { plates: number[]; loadedKg: number } {
  const plates: number[] = []
  let remaining = perSideTargetKg
  let loaded = 0
  const EPS = 1e-9

  for (const { kg, pairs } of inventory) {
    let used = 0
    // Use this denomination while it fits and pairs remain.
    while (used < pairs && kg <= remaining + EPS) {
      plates.push(kg)
      remaining -= kg
      loaded += kg
      used += 1
    }
  }
  return { plates, loadedKg: loaded }
}

/**
 * Compute the nearest-achievable plate stack for a target barbell weight.
 *
 * Greedy largest-first fill never OVERSHOOTS the target (it only places a plate
 * that still fits), so the result is the nearest achievable weight AT OR BELOW
 * the target given the inventory — the safe rounding direction for a strength
 * prescription (you never get handed more than you asked for). The bar alone is
 * the floor: a target under the bar clamps to the bar.
 */
export function computePlateStack(input: PlateStackInput): PlateStackResult {
  const barbellKg = resolveBar(input.barbellKg)
  const inventory = resolveInventory(input.inventory)
  const rawTarget = Number(input.targetKg)
  const target = Number.isFinite(rawTarget) ? rawTarget : barbellKg

  // Below or at the bar → no plates.
  if (target <= barbellKg) {
    return {
      barbellKg,
      perSideKg: [],
      achievableKg: barbellKg,
      exact: target === barbellKg,
      deltaKg: barbellKg - target,
    }
  }

  const perSideTarget = (target - barbellKg) / 2
  const { plates, loadedKg } = fillSide(perSideTarget, inventory)
  const achievableKg = roundKg(barbellKg + loadedKg * 2)
  const deltaKg = roundKg(achievableKg - target)

  return {
    barbellKg,
    perSideKg: plates,
    achievableKg,
    exact: Math.abs(deltaKg) < 1e-9,
    deltaKg,
  }
}

/** Round to 0.01 kg to avoid binary-float dust in totals. */
function roundKg(kg: number): number {
  return Math.round(kg * 100) / 100
}
