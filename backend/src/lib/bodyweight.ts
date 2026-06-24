import { prisma } from './prisma'

/**
 * Bodyweight — single source of truth.
 *
 * Canonical bodyweight lives in `userProfile.bodyweightKg` (Postgres Decimal,
 * stored in kilograms). Historically every consumer (ranking, nutrition, XP)
 * re-read and re-parsed that column on its own, with subtly different coercion
 * (`Number(...)`, `as unknown as number`, Decimal.toNumber()). That made
 * "where does bodyweight come from?" un-greppable and risked drift.
 *
 * This module is the ONE place that knows:
 *   1. which column is canonical (`bodyweightKg`), and
 *   2. how to coerce the Prisma Decimal | string | number into a plain number.
 *
 * Callers get a single typed entry point and never touch the raw column again.
 *
 * NOTE: the canonical value is intentionally NOT range-validated here — callers
 * own their own policy (e.g. ranking rejects <30 / >250 with BW_INVALID; a
 * nutrition estimate may clamp instead). This helper only answers "what is the
 * stored bodyweight, as a number?" and returns null when it is absent/unusable.
 */

/** Anything Prisma can hand back for a Decimal column. */
export type DecimalLike =
  | number
  | string
  | { toNumber: () => number }
  | null
  | undefined

/** Minimal shape we read off a user profile row. */
export interface BodyweightSource {
  bodyweightKg: DecimalLike
}

/** Coerce a Prisma Decimal | string | number | null into a finite number or null. */
function toFiniteNumber(value: DecimalLike): number | null {
  if (value == null) return null
  let n: number
  if (typeof value === 'number') {
    n = value
  } else if (typeof value === 'string') {
    n = Number(value)
  } else if (typeof value === 'object' && typeof value.toNumber === 'function') {
    n = value.toNumber()
  } else {
    n = Number(value as unknown)
  }
  return Number.isFinite(n) ? n : null
}

/**
 * The canonical bodyweight (kg) for a profile-like row, or null if missing.
 * Pure + synchronous — safe to unit test and to reuse anywhere a profile is
 * already loaded (avoids a second DB round-trip).
 */
export function getCanonicalBodyweightKg(profile: BodyweightSource | null | undefined): number | null {
  if (!profile) return null
  return toFiniteNumber(profile.bodyweightKg)
}

/**
 * The canonical bodyweight (kg) for a user, read from the single source
 * (`userProfile.bodyweightKg`). Returns null when there is no profile row or
 * the column is empty/unusable. Callers decide what an absent value means.
 */
export async function getUserBodyweightKg(userId: string): Promise<number | null> {
  const profile = await prisma.userProfile.findUnique({
    where: { userId },
    select: { bodyweightKg: true },
  })
  return getCanonicalBodyweightKg(profile)
}
