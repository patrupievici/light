// ─── Canonical activity normalization (read-side) ─────────────────────────────
//
// Different kinds of effort live in different tables — outdoor GPS sessions in
// `GpsActivity`, gym sessions in `Workout` — but unified analytics / a single
// activity feed wants ONE shape to reduce over. This module is a pure mapper that
// projects each source onto a single `ActivityDTO` so callers never special-case
// per source. It is strictly read-side: no DB, no clock, no mutation. The caller
// loads the rows (selecting only the fields below) and feeds them in.

/** The one canonical activity shape unified analytics / feeds consume. */
export type ActivityDTO = {
  /** Stable id of the underlying row. */
  id: string
  /** Owner user id. */
  userId: string
  /** Canonical activity kind. 'gym' covers any completed strength workout. */
  type: 'run' | 'ride' | 'walk' | 'swim' | 'cardio' | 'gym'
  /** Start instant, ISO-8601 UTC. */
  startedAt: string
  /** Elapsed seconds; null when not derivable. */
  durationS: number | null
  /** Distance in metres for outdoor activities; null for gym/unknown. */
  distanceM: number | null
  /** Energy in kcal when known; null otherwise. */
  calories: number | null
  /** Provenance of the row, for analytics filtering / dedup. */
  source: 'gps' | 'gym'
}

/** Minimal GpsActivity projection the normalizer needs (a read-side select). */
export type NormalizableGpsActivity = {
  id: string
  userId: string
  activityType?: string | null
  distanceM: number | null
  durationS: number | null
  calories: number | null
  startedAt: Date
  endedAt: Date | null
}

/** Minimal completed-Workout projection the normalizer needs. */
export type NormalizableWorkout = {
  id: string
  userId: string
  startedAt: Date
  endedAt: Date | null
}

/**
 * Classify a GPS activity into a canonical `type` from its average speed.
 *
 * Without a per-activity sport tag in the schema we infer from pace, which is a
 * stable, explainable signal: walking pace stays below ~2.3 m/s (≈ 8.3 km/h),
 * running tops out around ~6.5 m/s before it's almost certainly wheels. Anything
 * we can't place (no usable distance/duration) falls back to the neutral
 * 'cardio' so the row still appears in unified views. Pure + deterministic.
 */
export const WALK_MAX_SPEED_MS = 2.3
export const RUN_MAX_SPEED_MS = 6.5

/** Convert client/database aliases to the canonical server activity type. */
export function canonicalGpsType(raw: unknown): Exclude<ActivityDTO['type'], 'gym'> | null {
  if (typeof raw !== 'string') return null
  switch (raw.trim().toLowerCase()) {
    case 'run':
    case 'running':
      return 'run'
    case 'ride':
    case 'bike':
    case 'cycle':
    case 'cycling':
      return 'ride'
    case 'walk':
    case 'walking':
    case 'hike':
      return 'walk'
    case 'swim':
    case 'swimming':
      return 'swim'
    case 'cardio':
      return 'cardio'
    default:
      return null
  }
}

export function classifyGpsType(
  distanceM: number | null,
  durationS: number | null,
): ActivityDTO['type'] {
  if (distanceM == null || durationS == null || !(distanceM > 0) || !(durationS > 0)) {
    return 'cardio'
  }
  const speed = distanceM / durationS
  if (speed <= WALK_MAX_SPEED_MS) return 'walk'
  if (speed <= RUN_MAX_SPEED_MS) return 'run'
  return 'ride'
}

/**
 * Elapsed seconds for a session: prefer the started→ended span (the most
 * trustworthy elapsed signal) and fall back to a stored `durationS`. Never
 * negative; null when neither source yields a positive duration.
 */
function elapsedSeconds(
  startedAt: Date,
  endedAt: Date | null,
  storedS: number | null | undefined,
): number | null {
  if (endedAt != null) {
    const span = Math.round((endedAt.getTime() - startedAt.getTime()) / 1000)
    if (span > 0) return span
  }
  return storedS != null && storedS > 0 ? storedS : null
}

/** Normalize one GPS activity into the canonical DTO. */
export function normalizeGpsActivity(a: NormalizableGpsActivity): ActivityDTO {
  const durationS = elapsedSeconds(a.startedAt, a.endedAt, a.durationS)
  return {
    id: a.id,
    userId: a.userId,
    type: canonicalGpsType(a.activityType) ?? classifyGpsType(a.distanceM, durationS),
    startedAt: a.startedAt.toISOString(),
    durationS,
    distanceM: a.distanceM != null && a.distanceM > 0 ? a.distanceM : null,
    calories: a.calories != null && a.calories >= 0 ? a.calories : null,
    source: 'gps',
  }
}

/**
 * Normalize one completed gym Workout into the canonical DTO. Gym sessions carry
 * no GPS distance, so `distanceM` is null and duration comes from the
 * started→ended span. Calories aren't stored for workouts → null.
 */
export function normalizeWorkout(w: NormalizableWorkout): ActivityDTO {
  return {
    id: w.id,
    userId: w.userId,
    type: 'gym',
    startedAt: w.startedAt.toISOString(),
    durationS: elapsedSeconds(w.startedAt, w.endedAt, null),
    distanceM: null,
    calories: null,
    source: 'gym',
  }
}

/**
 * Build a unified, time-descending activity feed from both sources. Pure: the
 * caller supplies already-loaded rows; this only maps + merges + sorts (newest
 * first) so a single list can render GPS and gym sessions together.
 */
export function buildActivityFeed(args: {
  gpsActivities?: NormalizableGpsActivity[]
  workouts?: NormalizableWorkout[]
}): ActivityDTO[] {
  const out: ActivityDTO[] = []
  for (const a of args.gpsActivities ?? []) out.push(normalizeGpsActivity(a))
  for (const w of args.workouts ?? []) out.push(normalizeWorkout(w))
  out.sort((x, y) => Date.parse(y.startedAt) - Date.parse(x.startedAt))
  return out
}
