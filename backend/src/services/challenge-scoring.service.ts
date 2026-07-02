// Challenge scoring engine (Feed & Challenges v1).
//
// Pure, deterministic functions — no DB, no Prisma — so they're fully unit
// testable and reusable from the workout-complete recalc hook + the standings
// endpoint. Everything is computed from data Zvelt already controls: workout
// logger, sets (weight × reps), duration, exercises, and Epley e1RM. No
// steps/calories in v1.
//
// Formulas (exactly per spec):
//   Workout Streak : longest_streak_days*100 + total_valid_days*10
//   Most Workouts  : valid_workouts*100 + active_days*10   (≤2 counted/day)
//   Total Volume   : floor(total_volume_kg / 100)          (primary display = kg)
//   PR Battle      : max(0, best_e1RM_during − baseline_e1RM) * 20  (Epley)
//   Consistency    : completed_target_days*100 (+25 if all target days hit)

export type WorkoutTag = 'WORK' | 'WARMUP' | 'DROP'

export interface ScoringSet {
  weightKg: number
  reps: number
  tag: WorkoutTag
  isCompleted: boolean
}

export interface ScoringWorkout {
  startedAt: Date
  endedAt: Date | null
  exercises: { exerciseId: string; sets: ScoringSet[] }[]
  isManual?: boolean
}

export type ChallengeScoringType =
  | 'workout_streak'
  | 'most_workouts'
  | 'total_volume'
  | 'pr_battle'
  | 'consistency'

export interface ChallengeRules {
  minDurationMin: number
  minExercises: number
  minSets: number
  /** Max workouts counted per day for Most Workouts. */
  maxPerDayMostWorkouts: number
  /** Max workouts counted per day for Streak (a day is binary anyway). */
  maxPerDayStreak: number
}

export const DEFAULT_RULES: ChallengeRules = {
  minDurationMin: 15,
  minExercises: 3,
  minSets: 6,
  maxPerDayMostWorkouts: 2,
  maxPerDayStreak: 1,
}

export interface ScoredResult {
  /** Integer points used for ranking. */
  score: number
  /** Human-readable primary metric (e.g. "14,237 kg", "5-day streak"). */
  metric: string
  /** Tie-breaker values, applied in order (higher wins) per spec. */
  tiebreak: number[]
}

// ─── e1RM (Epley) — matches ranking.service ──────────────────────────────────
const MAX_REPS_FOR_E1RM = 12
const MAX_E1RM_KG = 600

/** Epley estimated 1RM. Null if reps outside [1..12] or result implausible. */
export function epleyE1rm(weightKg: number, reps: number): number | null {
  if (!Number.isFinite(weightKg) || !Number.isFinite(reps)) return null
  if (reps < 1 || reps > MAX_REPS_FOR_E1RM) return null
  if (weightKg <= 0) return null
  const e = weightKg * (1 + reps / 30)
  if (e > MAX_E1RM_KG) return null
  return e
}

// ─── Workout aggregates ──────────────────────────────────────────────────────
export function workoutDurationMin(w: ScoringWorkout): number {
  if (!w.endedAt) return 0
  const ms = w.endedAt.getTime() - w.startedAt.getTime()
  return ms > 0 ? ms / 60000 : 0
}

/** Total volume in kg from completed WORK sets (warm-ups/drops excluded). */
export function workoutVolumeKg(w: ScoringWorkout): number {
  let v = 0
  for (const ex of w.exercises) {
    for (const s of ex.sets) {
      if (s.tag !== 'WORK' || !s.isCompleted) continue
      v += s.weightKg * s.reps
    }
  }
  return v
}

export function completedWorkSets(w: ScoringWorkout): number {
  let n = 0
  for (const ex of w.exercises) {
    for (const s of ex.sets) {
      if (s.tag === 'WORK' && s.isCompleted) n++
    }
  }
  return n
}

/** Exercises with at least one completed WORK set. */
export function workedExerciseCount(w: ScoringWorkout): number {
  let n = 0
  for (const ex of w.exercises) {
    if (ex.sets.some((s) => s.tag === 'WORK' && s.isCompleted)) n++
  }
  return n
}

/** A workout "counts" for a challenge only if it clears the validity bar. */
export function isValidWorkout(w: ScoringWorkout, rules: ChallengeRules): boolean {
  return (
    workoutDurationMin(w) >= rules.minDurationMin &&
    workedExerciseCount(w) >= rules.minExercises &&
    completedWorkSets(w) >= rules.minSets
  )
}

/** UTC day key for grouping/streaks. */
export function dayKey(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
}

function distinctSortedDays(workouts: ScoringWorkout[]): string[] {
  return [...new Set(workouts.map((w) => dayKey(w.startedAt)))].sort()
}

/** Longest run of consecutive calendar days present in the (sorted) day list. */
export function longestConsecutiveRun(days: string[]): number {
  if (days.length === 0) return 0
  const set = new Set(days)
  let longest = 0
  for (const d of set) {
    // only start counting from the beginning of a run
    const prev = addDays(d, -1)
    if (set.has(prev)) continue
    let len = 1
    let cur = d
    while (set.has(addDays(cur, 1))) {
      len++
      cur = addDays(cur, 1)
    }
    if (len > longest) longest = len
  }
  return longest
}

function addDays(key: string, delta: number): string {
  const [y, m, d] = key.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d))
  dt.setUTCDate(dt.getUTCDate() + delta)
  return dayKey(dt)
}

// ─── Scoring (each takes the participant's VALID workouts in the window) ──────

export function scoreWorkoutStreak(valid: ScoringWorkout[]): ScoredResult {
  const days = distinctSortedDays(valid)
  const longest = longestConsecutiveRun(days)
  const totalValidDays = days.length
  const score = longest * 100 + totalValidDays * 10
  return {
    score,
    metric: `${longest}-day streak`,
    tiebreak: [longest, valid.length, totalVolume(valid)],
  }
}

export function scoreMostWorkouts(valid: ScoringWorkout[], rules: ChallengeRules): ScoredResult {
  // Cap counted workouts per day.
  const perDay = new Map<string, number>()
  for (const w of valid) {
    const k = dayKey(w.startedAt)
    perDay.set(k, (perDay.get(k) ?? 0) + 1)
  }
  let counted = 0
  for (const n of perDay.values()) counted += Math.min(n, rules.maxPerDayMostWorkouts)
  const activeDays = perDay.size
  const score = counted * 100 + activeDays * 10
  return {
    score,
    metric: `${counted} workouts`,
    tiebreak: [activeDays, totalVolume(valid), totalDurationMin(valid)],
  }
}

export function scoreTotalVolume(valid: ScoringWorkout[]): ScoredResult {
  const vol = totalVolume(valid)
  const score = Math.floor(vol / 100)
  const single = valid.reduce((m, w) => Math.max(m, workoutVolumeKg(w)), 0)
  return {
    score,
    metric: `${formatKg(vol)} kg`,
    // fewer workouts for the same volume wins → use negative count
    tiebreak: [vol, -valid.length, single],
  }
}

/**
 * PR Battle. `baselineE1rm` = best Epley e1RM for the exercise in the 90 days
 * BEFORE the challenge (or null = new baseline → baseline is the first valid
 * set during the challenge). Caller resolves the baseline.
 */
export function scorePrBattle(
  valid: ScoringWorkout[],
  exerciseId: string,
  baselineE1rm: number | null,
): ScoredResult {
  let best = 0
  let bestReps = 0
  for (const w of valid) {
    for (const ex of w.exercises) {
      if (ex.exerciseId !== exerciseId) continue
      for (const s of ex.sets) {
        if (s.tag !== 'WORK' || !s.isCompleted) continue
        const e = epleyE1rm(s.weightKg, s.reps)
        if (e != null && e > best) {
          best = e
          bestReps = s.reps
        }
      }
    }
  }
  // No baseline yet → first achievement during the challenge is the baseline.
  const baseline = baselineE1rm ?? best
  const improvement = Math.max(0, best - baseline)
  const score = Math.round(improvement * 20)
  return {
    score,
    metric: best > 0 ? `+${improvement.toFixed(1)} kg e1RM` : 'No lift yet',
    tiebreak: [improvement, best, bestReps],
  }
}

export function scoreConsistency(valid: ScoringWorkout[], targetDays: number): ScoredResult {
  const completed = distinctSortedDays(valid).length
  const cappedCompleted = targetDays > 0 ? Math.min(completed, targetDays) : completed
  const allDone = targetDays > 0 && completed >= targetDays
  const score = cappedCompleted * 100 + (allDone ? 25 : 0)
  return {
    score,
    metric: `${completed}/${targetDays} days`,
    tiebreak: [allDone ? 1 : 0, valid.length, totalVolume(valid)],
  }
}

// ─── Dispatch ────────────────────────────────────────────────────────────────
export interface ScoreInputs {
  type: ChallengeScoringType
  validWorkouts: ScoringWorkout[]
  rules: ChallengeRules
  /** PR battle only. */
  exerciseId?: string
  baselineE1rm?: number | null
  /** Consistency only. */
  targetDays?: number
}

export function computeScore(input: ScoreInputs): ScoredResult {
  switch (input.type) {
    case 'workout_streak':
      return scoreWorkoutStreak(input.validWorkouts)
    case 'most_workouts':
      return scoreMostWorkouts(input.validWorkouts, input.rules)
    case 'total_volume':
      return scoreTotalVolume(input.validWorkouts)
    case 'pr_battle':
      return scorePrBattle(input.validWorkouts, input.exerciseId ?? '', input.baselineE1rm ?? null)
    case 'consistency':
      return scoreConsistency(input.validWorkouts, input.targetDays ?? 0)
  }
}

/**
 * Rank participants by score, then by tie-breakers in order (higher wins).
 * Returns the same objects with a 1-based `rank` assigned. Stable for equal
 * keys (callers may add an "earliest reached" tiebreak before this).
 */
export function rankByScore<T extends { result: ScoredResult }>(participants: T[]): (T & { rank: number })[] {
  const sorted = [...participants].sort((a, b) => {
    if (b.result.score !== a.result.score) return b.result.score - a.result.score
    const ta = a.result.tiebreak
    const tb = b.result.tiebreak
    for (let i = 0; i < Math.max(ta.length, tb.length); i++) {
      const d = (tb[i] ?? 0) - (ta[i] ?? 0)
      if (d !== 0) return d
    }
    return 0
  })
  return sorted.map((p, i) => ({ ...p, rank: i + 1 }))
}

// ─── helpers ─────────────────────────────────────────────────────────────────
function totalVolume(ws: ScoringWorkout[]): number {
  return ws.reduce((s, w) => s + workoutVolumeKg(w), 0)
}
function totalDurationMin(ws: ScoringWorkout[]): number {
  return ws.reduce((s, w) => s + workoutDurationMin(w), 0)
}
function formatKg(n: number): string {
  const r = Math.round(n)
  return r.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

/** Filter to workouts that are valid AND inside [startAt, endAt]. */
export function validWorkoutsInWindow(
  workouts: ScoringWorkout[],
  rules: ChallengeRules,
  startAt: Date,
  endAt: Date,
): ScoringWorkout[] {
  return workouts.filter(
    (w) =>
      w.startedAt >= startAt &&
      w.startedAt <= endAt &&
      isValidWorkout(w, rules),
  )
}
