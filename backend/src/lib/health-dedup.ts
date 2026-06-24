/**
 * Cross-source health-sample deduplication (pure, side-effect free).
 *
 * A single underlying physiological event — a run, a night of sleep, a daily
 * step count — frequently reaches us through MORE THAN ONE pipe:
 *
 *   - a device-native path (Android Health Connect, Huawei Health Kit),
 *   - a cloud aggregator (Terra → Garmin/Fitbit/…),
 *   - a manual file upload (.fit / .tcx / .gpx the user dragged in).
 *
 * The `user_health_imports` table only has a *per-source* unique index
 * `(userId, sourcePath, provider, metricType, externalId)`, so re-delivered
 * webhooks from the SAME source are already idempotent. It does nothing, though,
 * to stop the SAME run showing up once from Health Connect and once from Terra —
 * those have different sourcePaths/externalIds and would both be stored, then
 * double-count in any "today you walked X / burned Y" rollup.
 *
 * This module decides, given a set of candidate records, which ones describe the
 * same real-world sample (same metric type, overlapping time window, values
 * close enough to be the same measurement) and which single record should win.
 *
 * Everything here is a pure function of its inputs — no Prisma, no clock, no
 * env. The route layer is responsible for loading candidates and persisting the
 * decision; this file just makes the decision so it can be unit-tested in
 * isolation.
 */

/** Source pipes a health sample can arrive through, most-specific first. */
export type HealthSourcePath = 'health_connect' | 'huawei_health_kit' | 'aggregator' | 'file_upload'

/**
 * One candidate health sample under consideration for dedup. Deliberately a
 * narrow projection of `UserHealthImport` so callers can pass either freshly
 * parsed webhook rows or already-stored DB rows through the same helper.
 */
export interface HealthSampleCandidate {
  /** Stable identity for this candidate within the batch (e.g. DB id, or a
   *  synthetic key for not-yet-persisted rows). Returned verbatim in results. */
  key: string
  /** Normalized metric type, e.g. `steps`, `activity`, `sleep`, `heart_rate`. */
  metricType: string
  /** Source pipe this sample arrived through. Drives winner selection. */
  sourcePath: HealthSourcePath | string
  /** Provider label (garmin, fitbit, …) — used only as a stable tie-breaker. */
  provider?: string | null
  /** Sample window start (inclusive), epoch ms or Date. */
  startAt: number | Date
  /** Sample window end (inclusive), epoch ms or Date. */
  endAt: number | Date
  /** Numeric measurement for the window (steps, kcal, metres…). May be null
   *  when the source only carries a window (then we fall back to time-only
   *  matching for that metric). */
  value?: number | null
}

export interface HealthDedupOptions {
  /**
   * How close two values must be to count as the same measurement. Both are
   * checked; a pair is "close" if EITHER bound is satisfied, so small absolute
   * jitter near zero and proportional drift on large values both collapse.
   */
  valueAbsoluteTolerance?: number
  valueRelativeTolerance?: number
  /**
   * Two windows are considered the same sample when they overlap by at least
   * this fraction of the SHORTER window (Jaccard-style on the time axis). A
   * provider that reports a slightly wider/narrower window for the same run
   * still matches; two genuinely different back-to-back runs do not.
   */
  minOverlapRatio?: number
  /**
   * Ranking of source pipes, most-trusted/most-specific first. A record from an
   * earlier entry beats a near-duplicate from a later one. Unknown sourcePaths
   * sort after all known ones.
   */
  sourcePriority?: readonly string[]
}

export const DEFAULT_SOURCE_PRIORITY: readonly HealthSourcePath[] = [
  // Device-native paths carry the original, highest-fidelity sample.
  'health_connect',
  'huawei_health_kit',
  // Aggregators re-derive/normalize and can lag or round.
  'aggregator',
  // Manual uploads are the most error-prone and easiest to duplicate.
  'file_upload',
]

const DEFAULTS: Required<Omit<HealthDedupOptions, 'sourcePriority'>> & {
  sourcePriority: readonly string[]
} = {
  valueAbsoluteTolerance: 1,
  // 5% — a Garmin vs Fitbit step count for the same day rarely agrees exactly.
  valueRelativeTolerance: 0.05,
  // Same sample if windows overlap by ≥80% of the shorter one.
  minOverlapRatio: 0.8,
  sourcePriority: DEFAULT_SOURCE_PRIORITY,
}

/** One resolved duplicate group: the surviving record + the ones it absorbed. */
export interface HealthDedupGroup {
  /** The candidate chosen to represent this real-world sample. */
  winner: HealthSampleCandidate
  /** Near-duplicates from other sources that were collapsed into the winner. */
  merged: HealthSampleCandidate[]
  /** The metric type shared by the whole group. */
  metricType: string
}

export interface HealthDedupResult {
  /** Winners only — the deduped set safe to count/store without double-counting. */
  kept: HealthSampleCandidate[]
  /** Candidates that lost to a winner and should be skipped/merged. */
  dropped: HealthSampleCandidate[]
  /** Full grouping (winner + merged) for auditing/explainability. */
  groups: HealthDedupGroup[]
}

function toMs(value: number | Date): number {
  return value instanceof Date ? value.getTime() : value
}

/**
 * Fraction of the SHORTER window covered by the intersection of two windows.
 * Returns 0 when they don't overlap. A zero-length window (instant sample) is
 * treated as overlapping when it falls inside the other window.
 */
export function windowOverlapRatio(
  aStart: number,
  aEnd: number,
  bStart: number,
  bEnd: number,
): number {
  const loA = Math.min(aStart, aEnd)
  const hiA = Math.max(aStart, aEnd)
  const loB = Math.min(bStart, bEnd)
  const hiB = Math.max(bStart, bEnd)

  const interStart = Math.max(loA, loB)
  const interEnd = Math.min(hiA, hiB)
  const intersection = interEnd - interStart
  if (intersection < 0) return 0

  const durA = hiA - loA
  const durB = hiB - loB
  const shorter = Math.min(durA, durB)

  // Both instantaneous (or one is): if their windows touch at all, they're the
  // same instant sample.
  if (shorter === 0) return interEnd >= interStart ? 1 : 0
  return intersection / shorter
}

/**
 * True when two numeric measurements are close enough to be the same reading.
 * `null`/`undefined` on EITHER side means "no comparable value" — we don't let
 * a missing value block a time match, so those are treated as compatible.
 */
export function valuesAreClose(
  a: number | null | undefined,
  b: number | null | undefined,
  absTol: number,
  relTol: number,
): boolean {
  if (a == null || b == null) return true
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false
  const diff = Math.abs(a - b)
  if (diff <= absTol) return true
  const scale = Math.max(Math.abs(a), Math.abs(b))
  return scale > 0 && diff <= scale * relTol
}

function priorityRank(sourcePath: string, priority: readonly string[]): number {
  const idx = priority.indexOf(sourcePath)
  // Unknown sources rank after every known one, but before each other stably.
  return idx === -1 ? priority.length : idx
}

/**
 * Decide whether two candidates describe the same real-world sample: same
 * metric type, time windows overlapping past the threshold, and (when both
 * carry a value) values within tolerance.
 */
function isSameSample(
  a: HealthSampleCandidate,
  b: HealthSampleCandidate,
  opts: Required<Omit<HealthDedupOptions, 'sourcePriority'>>,
): boolean {
  if (a.metricType !== b.metricType) return false
  const overlap = windowOverlapRatio(
    toMs(a.startAt),
    toMs(a.endAt),
    toMs(b.startAt),
    toMs(b.endAt),
  )
  if (overlap < opts.minOverlapRatio) return false
  return valuesAreClose(
    a.value,
    b.value,
    opts.valueAbsoluteTolerance,
    opts.valueRelativeTolerance,
  )
}

/**
 * Pick the surviving record from a duplicate group: highest source priority
 * wins; ties break toward the longer (more complete) window, then the larger
 * available value, then a stable key compare so the result is deterministic.
 */
function chooseWinner(
  group: HealthSampleCandidate[],
  priority: readonly string[],
): HealthSampleCandidate {
  return group.reduce((best, cur) => {
    const bRank = priorityRank(best.sourcePath, priority)
    const cRank = priorityRank(cur.sourcePath, priority)
    if (cRank !== bRank) return cRank < bRank ? cur : best

    const bDur = Math.abs(toMs(best.endAt) - toMs(best.startAt))
    const cDur = Math.abs(toMs(cur.endAt) - toMs(cur.startAt))
    if (cDur !== bDur) return cDur > bDur ? cur : best

    const bVal = best.value ?? -Infinity
    const cVal = cur.value ?? -Infinity
    if (cVal !== bVal) return cVal > bVal ? cur : best

    return cur.key < best.key ? cur : best
  })
}

/**
 * Collapse cross-source duplicates in a set of health-sample candidates.
 *
 * Pure: deterministic for a given input + options, never mutates the inputs.
 * Behavior-preserving for the single-source case — with one source there are no
 * cross-source pairs to collapse, so every candidate is kept (records that are
 * already unique within a source stay independent).
 *
 * Grouping uses single-link clustering on the same-sample relation: A links to B
 * and B links to C ⇒ {A,B,C} are one sample. Across-batch chaining like this is
 * what lets a slightly-shifted aggregator window bridge a native sample and a
 * file upload of the same activity.
 */
export function dedupeHealthSamples(
  candidates: readonly HealthSampleCandidate[],
  options: HealthDedupOptions = {},
): HealthDedupResult {
  const opts = {
    valueAbsoluteTolerance:
      options.valueAbsoluteTolerance ?? DEFAULTS.valueAbsoluteTolerance,
    valueRelativeTolerance:
      options.valueRelativeTolerance ?? DEFAULTS.valueRelativeTolerance,
    minOverlapRatio: options.minOverlapRatio ?? DEFAULTS.minOverlapRatio,
  }
  const priority = options.sourcePriority ?? DEFAULTS.sourcePriority

  const items = [...candidates]
  const n = items.length

  // Union-Find for single-link clustering.
  const parent = items.map((_, i) => i)
  const find = (x: number): number => {
    let r = x
    while (parent[r] !== r) r = parent[r]
    // Path compression.
    let c = x
    while (parent[c] !== c) {
      const next = parent[c]
      parent[c] = r
      c = next
    }
    return r
  }
  const union = (a: number, b: number) => {
    const ra = find(a)
    const rb = find(b)
    if (ra !== rb) parent[rb] = ra
  }

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (isSameSample(items[i], items[j], opts)) union(i, j)
    }
  }

  const buckets = new Map<number, HealthSampleCandidate[]>()
  for (let i = 0; i < n; i++) {
    const root = find(i)
    const bucket = buckets.get(root)
    if (bucket) bucket.push(items[i])
    else buckets.set(root, [items[i]])
  }

  const kept: HealthSampleCandidate[] = []
  const dropped: HealthSampleCandidate[] = []
  const groups: HealthDedupGroup[] = []

  for (const bucket of buckets.values()) {
    const winner = chooseWinner(bucket, priority)
    const merged = bucket.filter((c) => c !== winner)
    kept.push(winner)
    dropped.push(...merged)
    groups.push({ winner, merged, metricType: winner.metricType })
  }

  return { kept, dropped, groups }
}
