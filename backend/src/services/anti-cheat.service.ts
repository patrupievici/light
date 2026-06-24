/**
 * Anti-cheat validators (server-side). Pure functions so they are unit-testable
 * without a live DB; the route layer supplies the persisted state (counts,
 * timestamps, historical maxes) and acts on the verdict.
 *
 * Spec (CLAUDE.md → "Anti-cheat (server-side)"):
 *   - Max 3 editari/24h per post
 *   - Audit log before/after pe orice editare set
 *   - Jump SR >20% vs best 30 zile → flag "anomaly"
 *   - Weight >2× max istoric personal + <7 zile → confirm + nota obligatorie
 */

const DAY_MS = 24 * 60 * 60 * 1000
const SEVEN_DAYS_MS = 7 * DAY_MS
const MAX_EDITS_PER_24H = 3
const SR_ANOMALY_FACTOR = 1.2 // >20% jump
const WEIGHT_JUMP_FACTOR = 2 // >2× personal max

// ─── Edit limit (max 3 / 24h per post) ────────────────────────────────────────

export interface EditLimitState {
  /** How many edits already recorded in the current window. */
  editCount: number
  /** When the last edit happened (null = never edited). */
  lastEditAt: Date | null
}

export interface EditLimitVerdict {
  /** True if this edit is allowed to proceed. */
  allowed: boolean
  /** The editCount to persist if the edit proceeds (resets when window rolls). */
  nextEditCount: number
  reason?: 'EDIT_LIMIT'
}

/**
 * Decide whether an edit may proceed. The 24h window is anchored on `lastEditAt`:
 * if the last edit was more than 24h ago the counter resets to this edit (=1).
 */
export function evaluateEditLimit(
  state: EditLimitState,
  now: Date = new Date(),
): EditLimitVerdict {
  const windowOpen =
    state.lastEditAt != null && now.getTime() - state.lastEditAt.getTime() < DAY_MS

  if (!windowOpen) {
    // Fresh window — this becomes edit #1.
    return { allowed: true, nextEditCount: 1 }
  }

  if (state.editCount >= MAX_EDITS_PER_24H) {
    return { allowed: false, nextEditCount: state.editCount, reason: 'EDIT_LIMIT' }
  }

  return { allowed: true, nextEditCount: state.editCount + 1 }
}

// ─── SR anomaly (>20% jump vs best 30 days) ───────────────────────────────────

/**
 * Flag a strength-ratio jump as anomalous when the new SR exceeds the best SR of
 * the last 30 days by more than 20%. A non-positive baseline (first ever rank)
 * is never anomalous.
 */
export function isSrAnomaly(newSr: number, best30daySr: number): boolean {
  if (!Number.isFinite(newSr) || !Number.isFinite(best30daySr)) return false
  if (best30daySr <= 0) return false
  return newSr > best30daySr * SR_ANOMALY_FACTOR
}

// ─── Weight jump (>2× personal max within <7 days) ────────────────────────────

export interface WeightJumpInput {
  /** Weight of the set being logged/edited (kg). */
  newWeightKg: number
  /** All-time personal max weight for this exercise (kg), or null if none. */
  personalMaxKg: number | null
  /** When that personal max was set, or null if none. */
  personalMaxAt: Date | null
  /** Whether the client attached a note explaining the jump. */
  hasNote: boolean
}

export interface WeightJumpVerdict {
  /** True when a confirmation + note is required before accepting the set. */
  requiresConfirmation: boolean
  /** True when the set must be rejected (confirmation required but no note). */
  rejected: boolean
  reason?: 'WEIGHT_JUMP_REQUIRES_NOTE'
}

/**
 * Require confirm + obligatory note when a set's weight is more than 2× the
 * personal max AND that personal max is less than 7 days old (i.e. a sudden
 * spike, not a gradual long-term progression). Without a note the set is rejected.
 */
export function evaluateWeightJump(
  input: WeightJumpInput,
  now: Date = new Date(),
): WeightJumpVerdict {
  const { newWeightKg, personalMaxKg, personalMaxAt, hasNote } = input

  if (
    personalMaxKg == null ||
    personalMaxAt == null ||
    personalMaxKg <= 0 ||
    !Number.isFinite(newWeightKg)
  ) {
    return { requiresConfirmation: false, rejected: false }
  }

  const isJump = newWeightKg > personalMaxKg * WEIGHT_JUMP_FACTOR
  const recent = now.getTime() - personalMaxAt.getTime() < SEVEN_DAYS_MS

  if (isJump && recent) {
    if (!hasNote) {
      return {
        requiresConfirmation: true,
        rejected: true,
        reason: 'WEIGHT_JUMP_REQUIRES_NOTE',
      }
    }
    return { requiresConfirmation: true, rejected: false }
  }

  return { requiresConfirmation: false, rejected: false }
}

export const ANTI_CHEAT_CONSTANTS = {
  MAX_EDITS_PER_24H,
  SR_ANOMALY_FACTOR,
  WEIGHT_JUMP_FACTOR,
  DAY_MS,
  SEVEN_DAYS_MS,
}
