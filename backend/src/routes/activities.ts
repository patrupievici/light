import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { acceptedFriendIds } from '../lib/friendships'
import { gameXpPayload } from '../services/gym-xp.service'
import {
  computeCardioGameXp,
  resolveUserXpContext,
} from '../services/cardio-xp.service'
import {
  parseActivityFile,
  ActivityFileParseError,
  MAX_IMPORT_POINTS,
} from '../lib/activity-file-import'
import {
  buildActivityFeed,
  canonicalGpsType,
  normalizeGpsActivity,
} from '../lib/activity-normalize'

/** Data civilă (YYYY-MM-DD) în offset-ul clientului (minute față de UTC). */
function ymdFromUtcWithOffset(d: Date, offsetMin: number): string {
  const x = new Date(d.getTime() + offsetMin * 60 * 1000)
  const y = x.getUTCFullYear()
  const m = String(x.getUTCMonth() + 1).padStart(2, '0')
  const day = String(x.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

const CalendarQuery = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/),
  tzOffset: z.coerce.number().min(-840).max(840).optional().default(0),
})

const CardioCompleteSchema = z.object({
  mode: z.enum(['run', 'bike', 'cycle', 'walk', 'swim']),
  distanceM: z.number().min(0).max(500_000),
  durationSec: z.number().int().min(1).max(86_400),
  source: z.string().max(64).optional(),
})

// ─── GPS activity ingest (anti-cheat: server recomputes metrics) ──────────────
//
// Clients (BackgroundTrackingService) POST a recorded route plus their own
// distance/duration/calories.  Those client numbers are NOT trusted: whenever
// route_points are present we recompute distance / moving + elapsed duration /
// avg pace / elevation gain server-side from the points and persist the
// server-computed values into the existing `activities` columns.  If no usable
// points are sent we fall back to the client-reported values (don't zero them).

/** One recorded GPS sample.  Only lat/lng are guaranteed; the rest are best-effort. */
export type RoutePoint = {
  lat: number
  lng: number
  /** Altitude in metres (optional — many clients omit it). */
  ele?: number | null
  /** Epoch milliseconds for this sample (optional). */
  t?: number | null
}

export type RouteMetrics = {
  /** Total moving distance in metres after outlier filtering. */
  distanceM: number
  /** Cumulative positive elevation change in metres (0 when no altitude data). */
  elevGainM: number
  /** Average speed in m/s over the supplied elapsed seconds (0 when unknown). */
  avgSpeedMs: number
  /**
   * Elapsed seconds the athlete spent actually moving, excluding stationary
   * (auto-paused) segments. Falls back to elapsed when timing is unusable.
   */
  movingTimeS: number
  /** Average pace over the moving time, seconds per kilometre (0 when unknown). */
  movingPaceSecsPerKm: number
  /** Number of point-to-point hops dropped as physically impossible. */
  droppedPoints: number
  /** Usable points after coordinate validation. */
  usedPoints: number
}

/** Moving-time breakdown for a recorded route (excludes stationary segments). */
export type MovingTimeMetrics = {
  /** Seconds spent moving above the auto-pause speed floor. */
  movingTimeS: number
  /** Average pace over the moving time, seconds per kilometre (0 when unknown). */
  movingPaceSecsPerKm: number
}

const EARTH_RADIUS_M = 6_371_000

/**
 * Max plausible point-to-point ground speed (m/s).  ~45 m/s ≈ 162 km/h covers
 * downhill cycling / GPS jitter on fast vehicles while still rejecting teleports
 * caused by a dropped/garbage fix.  Used by the outlier guard.
 */
export const MAX_PLAUSIBLE_SPEED_MS = 45

/**
 * Below this rise (m) between consecutive samples we treat the delta as GPS
 * altitude noise and ignore it for elevation-gain accumulation.
 */
export const ELEVATION_NOISE_THRESHOLD_M = 1.0

/**
 * Auto-pause speed floor (m/s). A hop whose implied ground speed is below this is
 * treated as the athlete being stationary (waiting at a light, resting) and its
 * time is excluded from "moving time". ~0.5 m/s ≈ 1.8 km/h sits below a slow
 * walk so genuine slow movement still counts while standing still does not.
 */
export const MOVING_SPEED_THRESHOLD_MS = 0.5

/** Great-circle distance between two coordinates in metres (Haversine). */
export function haversineMeters(
  aLat: number,
  aLng: number,
  bLat: number,
  bLng: number,
): number {
  const dLat = ((bLat - aLat) * Math.PI) / 180
  const dLng = ((bLng - aLng) * Math.PI) / 180
  const lat1 = (aLat * Math.PI) / 180
  const lat2 = (bLat * Math.PI) / 180
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
  return EARTH_RADIUS_M * 2 * Math.asin(Math.min(1, Math.sqrt(h)))
}

/** True when the value is a finite number inside the given inclusive range. */
function inRange(n: unknown, min: number, max: number): n is number {
  return typeof n === 'number' && Number.isFinite(n) && n >= min && n <= max
}

/**
 * Parse + validate raw client points into usable RoutePoints.  Anything without
 * a valid lat/lng pair is discarded.  Accepts the `{lat,lng}` object shape the
 * app sends as well as a couple of common aliases for robustness.
 */
export function normalizeRoutePoints(raw: unknown): RoutePoint[] {
  if (!Array.isArray(raw)) return []
  const out: RoutePoint[] = []
  for (const item of raw) {
    if (item == null || typeof item !== 'object') continue
    const o = item as Record<string, unknown>
    const lat = o.lat ?? o.latitude
    const lng = o.lng ?? o.longitude ?? o.lon
    if (!inRange(lat, -90, 90) || !inRange(lng, -180, 180)) continue
    const eleRaw = o.ele ?? o.elevation ?? o.altitude ?? o.alt
    const tRaw = o.t ?? o.ts ?? o.time ?? o.timestamp
    out.push({
      lat,
      lng,
      ele: inRange(eleRaw, -500, 9_000) ? eleRaw : null,
      t: typeof tRaw === 'number' && Number.isFinite(tRaw) ? tRaw : null,
    })
  }
  return out
}

/**
 * Drop hops whose implied speed is physically impossible before summing.
 * When samples carry timestamps we use the real time delta; otherwise we fall
 * back to `fallbackDtS` seconds per hop (derived from elapsed / hops).
 * Returns the kept points plus the count of dropped hops.
 */
export function filterOutlierPoints(
  points: RoutePoint[],
  fallbackDtS: number,
): { kept: RoutePoint[]; dropped: number } {
  if (points.length <= 1) return { kept: points.slice(), dropped: 0 }
  const kept: RoutePoint[] = [points[0]]
  let dropped = 0
  for (let i = 1; i < points.length; i++) {
    const prev = kept[kept.length - 1]
    const cur = points[i]
    const d = haversineMeters(prev.lat, prev.lng, cur.lat, cur.lng)
    // Determine a trustworthy time delta: prefer per-point timestamps, else the
    // elapsed-derived fallback.  Without either we can't judge speed, so we
    // keep the point rather than dropping legitimate data.
    let dt = 0
    if (prev.t != null && cur.t != null && cur.t > prev.t) {
      dt = (cur.t - prev.t) / 1000
    } else if (fallbackDtS > 0) {
      dt = fallbackDtS
    }
    if (dt > 0 && d / dt > MAX_PLAUSIBLE_SPEED_MS) {
      dropped++
      continue // skip this point; keep accumulating from `prev`
    }
    kept.push(cur)
  }
  return { kept, dropped }
}

/**
 * Total great-circle length of a polyline in metres: the sum of Haversine hops
 * over consecutive points. This is the *single* distance algorithm for the file
 * — both the trusted recompute and any other total-distance need route through
 * here so distance can never be computed two different ways. Pure; returns 0 for
 * fewer than two points.
 */
export function routeDistanceMeters(points: RoutePoint[]): number {
  let distanceM = 0
  for (let i = 1; i < points.length; i++) {
    distanceM += haversineMeters(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng)
  }
  return distanceM
}

/** Sum of positive altitude deltas, ignoring sub-threshold GPS noise. */
export function elevationGainMeters(points: RoutePoint[]): number {
  let gain = 0
  let lastEle: number | null = null
  for (const p of points) {
    if (p.ele == null) continue
    if (lastEle != null) {
      const rise = p.ele - lastEle
      if (rise >= ELEVATION_NOISE_THRESHOLD_M) gain += rise
    }
    lastEle = p.ele
  }
  return gain
}

/**
 * Compute "moving time" for a route by summing only the time of hops whose
 * implied ground speed clears `MOVING_SPEED_THRESHOLD_MS`; sub-threshold hops are
 * treated as auto-paused (standing still) and dropped. Moving pace is derived
 * from the route distance over that moving time.
 *
 * Per-hop time comes from real per-point timestamps when the track carries them
 * (the only way to know a pause actually happened); without timestamps every hop
 * gets an even slice of `elapsedS`, which can't distinguish a pause, so moving
 * time degrades gracefully to the full elapsed time. Pure + deterministic.
 */
export function movingTimeMetrics(
  points: RoutePoint[],
  elapsedS: number,
): MovingTimeMetrics {
  if (points.length < 2 || !(elapsedS > 0)) {
    return { movingTimeS: 0, movingPaceSecsPerKm: 0 }
  }

  const times = pointElapsedSeconds(points, elapsedS)
  let movingTimeS = 0
  let movingDistanceM = 0
  for (let i = 1; i < points.length; i++) {
    const dt = times[i]! - times[i - 1]!
    if (!(dt > 0)) continue
    const d = haversineMeters(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng)
    if (d / dt < MOVING_SPEED_THRESHOLD_MS) continue // stationary → auto-paused
    movingTimeS += dt
    movingDistanceM += d
  }

  // No moving hops detected (e.g. timestamp-less track distributed evenly below
  // the floor): fall back to elapsed so we never report 0 moving time for a real
  // session with distance.
  if (!(movingTimeS > 0)) {
    return { movingTimeS: Math.round(elapsedS), movingPaceSecsPerKm: 0 }
  }

  const movingPaceSecsPerKm =
    movingDistanceM > 0 ? Math.round((movingTimeS / movingDistanceM) * 1000) : 0
  return { movingTimeS: Math.round(movingTimeS), movingPaceSecsPerKm }
}

/**
 * Recompute trustworthy metrics from a recorded route.  `elapsedS` is the
 * server-validated elapsed duration (started→ended) used for avg speed.
 * Returns null when there are too few usable points to compute anything, so the
 * caller can fall back to client-reported values.
 */
export function computeRouteMetrics(
  rawPoints: unknown,
  elapsedS: number,
): RouteMetrics | null {
  const points = normalizeRoutePoints(rawPoints)
  if (points.length < 2) return null

  const fallbackDtS = elapsedS > 0 ? elapsedS / (points.length - 1) : 0
  const { kept, dropped } = filterOutlierPoints(points, fallbackDtS)
  if (kept.length < 2) return null

  const distanceM = routeDistanceMeters(kept)

  const elevGainM = elevationGainMeters(kept)
  const avgSpeedMs = elapsedS > 0 ? distanceM / elapsedS : 0
  const { movingTimeS, movingPaceSecsPerKm } = movingTimeMetrics(kept, elapsedS)

  return {
    distanceM: Math.round(distanceM * 100) / 100,
    elevGainM: Math.round(elevGainM * 100) / 100,
    avgSpeedMs: Math.round(avgSpeedMs * 1000) / 1000,
    movingTimeS,
    movingPaceSecsPerKm,
    droppedPoints: dropped,
    usedPoints: kept.length,
  }
}

// ─── Per-km / per-mile splits ─────────────────────────────────────────────────
//
// A "split" is one fixed-distance segment of the route (1 km by default, or 1
// mile when the client asks). For each completed segment we report the elapsed
// time spent covering it, the pace over that segment and the elevation gained.
// This is recomputed server-side from the same `route_points` used for the
// trusted distance/duration so the splits can never disagree with the headline
// metrics. Pure + deterministic: no DB, no clock.

/** Metres in one statute mile (for split unit selection). */
export const METERS_PER_MILE = 1609.344

/** One completed distance segment of a route. */
export type Split = {
  /** 1-based segment index (km 1, km 2, …; or mile 1, mile 2, …). */
  index: number
  /** Segment length in metres — `splitMeters` for full splits, less for the
   *  trailing partial segment. */
  distanceM: number
  /** Elapsed seconds spent covering this segment. 0 when no usable timing. */
  timeS: number
  /** Pace over the segment in seconds per kilometre. 0 when not derivable. */
  paceSecsPerKm: number
  /** Positive elevation gain within the segment in metres (0 without altitude). */
  elevGainM: number
  /** True for the final segment when it is shorter than a full split. */
  partial: boolean
}

/**
 * Estimate a per-point elapsed-seconds series for a route.
 *
 * When every point carries a timestamp we use the real (monotonic) offsets from
 * the first sample. Otherwise we distribute `elapsedS` evenly across the hops so
 * splits still get a sensible time even for timestamp-less tracks. The returned
 * array is the same length as `points` and is non-decreasing.
 */
function pointElapsedSeconds(points: RoutePoint[], elapsedS: number): number[] {
  const n = points.length
  if (n === 0) return []
  const haveTimestamps =
    points.every((p) => p.t != null) &&
    points[n - 1]!.t! >= points[0]!.t!
  if (haveTimestamps) {
    const t0 = points[0]!.t!
    let prev = 0
    return points.map((p) => {
      // Clamp to non-decreasing so a stray out-of-order sample can't rewind time.
      const v = Math.max(prev, (p.t! - t0) / 1000)
      prev = v
      return v
    })
  }
  const perHop = n > 1 && elapsedS > 0 ? elapsedS / (n - 1) : 0
  return points.map((_, i) => i * perHop)
}

/**
 * Split a recorded route into fixed-distance segments (per km, or per mile when
 * `splitMeters` is `METERS_PER_MILE`). Distance is accumulated with Haversine
 * over the outlier-filtered points; the time and elevation at each split
 * boundary are linearly interpolated along the hop that crosses the boundary so
 * a split's time isn't quantised to whole GPS samples.
 *
 * Returns `[]` when there are too few usable points or the route is shorter than
 * one split. A trailing partial segment (e.g. the last 0.4 km) is included and
 * flagged `partial: true` so the UI can render it distinctly.
 */
export function computeSplits(
  rawPoints: unknown,
  elapsedS: number,
  splitMeters: number = 1000,
): Split[] {
  if (!(splitMeters > 0)) return []
  const points = normalizeRoutePoints(rawPoints)
  if (points.length < 2) return []

  const fallbackDtS = elapsedS > 0 ? elapsedS / (points.length - 1) : 0
  const { kept } = filterOutlierPoints(points, fallbackDtS)
  if (kept.length < 2) return []

  const times = pointElapsedSeconds(kept, elapsedS)

  const splits: Split[] = []
  let segStartDist = 0 // cumulative distance where the current segment began
  let segStartTime = times[0]!
  let segStartEle: number | null = kept[0]!.ele ?? null
  let segGain = 0
  let prevSegEle: number | null = segStartEle
  let cumDist = 0
  let nextBoundary = splitMeters

  const pushSplit = (
    boundaryDist: number,
    boundaryTime: number,
    boundaryEle: number | null,
    partial: boolean,
  ) => {
    const distanceM = boundaryDist - segStartDist
    const timeS = Math.max(0, boundaryTime - segStartTime)
    // Fold the gain from the segment's start point through the boundary.
    if (boundaryEle != null && prevSegEle != null) {
      const rise = boundaryEle - prevSegEle
      if (rise >= ELEVATION_NOISE_THRESHOLD_M) segGain += rise
    }
    splits.push({
      index: splits.length + 1,
      distanceM: Math.round(distanceM * 100) / 100,
      timeS: Math.round(timeS),
      paceSecsPerKm:
        distanceM > 0 ? Math.round((timeS / distanceM) * 1000) : 0,
      elevGainM: Math.round(segGain * 100) / 100,
      partial,
    })
    segStartDist = boundaryDist
    segStartTime = boundaryTime
    segStartEle = boundaryEle
    prevSegEle = boundaryEle
    segGain = 0
  }

  for (let i = 1; i < kept.length; i++) {
    const a = kept[i - 1]!
    const b = kept[i]!
    const hop = haversineMeters(a.lat, a.lng, b.lat, b.lng)
    const hopStartDist = cumDist
    const hopEndDist = cumDist + hop

    // Emit every split boundary the current hop crosses, interpolating time/ele.
    while (hop > 0 && nextBoundary <= hopEndDist + 1e-9) {
      const frac = (nextBoundary - hopStartDist) / hop
      const boundaryTime = times[i - 1]! + (times[i]! - times[i - 1]!) * frac
      const boundaryEle =
        a.ele != null && b.ele != null ? a.ele + (b.ele - a.ele) * frac : (b.ele ?? a.ele ?? null)
      pushSplit(nextBoundary, boundaryTime, boundaryEle, false)
      nextBoundary += splitMeters
    }

    // Accumulate elevation across whole hops that don't hit a boundary so the
    // running segment gain stays accurate between boundaries.
    if (b.ele != null && prevSegEle != null) {
      const rise = b.ele - prevSegEle
      if (rise >= ELEVATION_NOISE_THRESHOLD_M) {
        segGain += rise
        prevSegEle = b.ele
      } else if (rise < 0) {
        prevSegEle = b.ele
      }
    } else if (b.ele != null) {
      prevSegEle = b.ele
    }

    cumDist = hopEndDist
  }

  // Trailing partial segment (distance left over after the last full split).
  if (cumDist - segStartDist > 1e-6) {
    pushSplit(cumDist, times[times.length - 1]!, kept[kept.length - 1]!.ele ?? null, true)
  }

  return splits
}

// ─── Outdoor personal records ─────────────────────────────────────────────────
//
// A lightweight, derive-on-read summary of a user's outdoor bests: the fastest
// average pace they've sustained over a meaningful distance, their longest
// single activity, and their fastest time over the classic benchmark distances
// (1 km, 5 km, 10 km). All computed from the trusted per-activity
// distance/duration columns — no schema, no extra tables.

/** A finished outdoor activity reduced to the fields PRs are derived from. */
export type ActivityPrInput = {
  distanceM: number | null
  durationS: number | null
}

/** Fastest known-distance record: the quickest time to cover `>= distanceM`. */
export type KnownDistancePr = {
  distanceM: number
  /** Best (lowest) time in seconds over an activity that reached the distance. */
  timeS: number
  /** Average pace of that best effort, seconds per kilometre. */
  paceSecsPerKm: number
}

export type OutdoorPrSummary = {
  /** Fastest sustained average pace (s/km) over a qualifying activity, or null. */
  fastestPaceSecsPerKm: number | null
  /** Longest single-activity distance in metres, or null when none. */
  longestDistanceM: number | null
  /** Best times over the benchmark distances the user has actually reached. */
  knownDistances: KnownDistancePr[]
  /** Number of activities that contributed to the summary. */
  qualifyingActivities: number
}

/**
 * Minimum distance (m) an activity must reach before its average pace counts as
 * a "fastest pace" PR. Short GPS blips produce wild paces; 400 m filters them
 * out while still admitting a hard sprint lap.
 */
export const MIN_PACE_PR_DISTANCE_M = 400

/** Benchmark distances (m) we report fastest-time PRs for, when reached. */
export const KNOWN_PR_DISTANCES_M = [1000, 5000, 10000] as const

/**
 * Derive an outdoor-PR summary from a user's activities. Pure: the caller loads
 * the rows, this only reduces them. Activities missing a usable distance or a
 * positive duration are ignored. For known-distance PRs we credit any activity
 * whose total distance reached the benchmark and use its average pace over the
 * benchmark distance, picking the lowest time across all such activities.
 */
export function outdoorPrSummary(activities: ActivityPrInput[]): OutdoorPrSummary {
  let fastestPaceSecsPerKm: number | null = null
  let longestDistanceM: number | null = null
  let qualifying = 0
  const bestByDistance = new Map<number, number>() // distanceM → best timeS

  for (const a of activities) {
    const distanceM = a.distanceM
    const durationS = a.durationS
    if (distanceM == null || !(distanceM > 0)) continue
    if (durationS == null || !(durationS > 0)) continue
    qualifying++

    if (longestDistanceM == null || distanceM > longestDistanceM) {
      longestDistanceM = distanceM
    }

    if (distanceM >= MIN_PACE_PR_DISTANCE_M) {
      const pace = (durationS / distanceM) * 1000
      if (fastestPaceSecsPerKm == null || pace < fastestPaceSecsPerKm) {
        fastestPaceSecsPerKm = Math.round(pace)
      }
    }

    // The pace held over the whole activity is the best estimate of the time to
    // cover any benchmark the activity reached.
    const avgPacePerM = durationS / distanceM
    for (const benchmark of KNOWN_PR_DISTANCES_M) {
      if (distanceM < benchmark) continue
      const benchmarkTime = avgPacePerM * benchmark
      const prev = bestByDistance.get(benchmark)
      if (prev == null || benchmarkTime < prev) {
        bestByDistance.set(benchmark, benchmarkTime)
      }
    }
  }

  const knownDistances: KnownDistancePr[] = KNOWN_PR_DISTANCES_M.filter((d) =>
    bestByDistance.has(d),
  ).map((distanceM) => {
    const timeS = bestByDistance.get(distanceM)!
    return {
      distanceM,
      timeS: Math.round(timeS),
      paceSecsPerKm: Math.round((timeS / distanceM) * 1000),
    }
  })

  return {
    fastestPaceSecsPerKm,
    longestDistanceM: longestDistanceM != null ? Math.round(longestDistanceM * 100) / 100 : null,
    knownDistances,
    qualifyingActivities: qualifying,
  }
}

// ─── Per-activity GPS privacy ─────────────────────────────────────────────────
//
// Each activity carries a `visibility`: 'private' (only the owner), 'friends'
// (owner + accepted friends) or 'public' (anyone authenticated). Reads that can
// surface another user's activity enforce this with `canViewActivity`, and the
// route polyline returned to a non-owner is trimmed at both ends with
// `fuzzRoutePoints` so a viewer can't read off the athlete's home/start.

/** Allowed visibility values. `private` is the safe default (privacy by default). */
export const ACTIVITY_VISIBILITIES = ['private', 'friends', 'public'] as const
export type ActivityVisibility = (typeof ACTIVITY_VISIBILITIES)[number]

/** Coerce arbitrary stored input into a known visibility, defaulting to private. */
export function normalizeVisibility(raw: unknown): ActivityVisibility {
  return (ACTIVITY_VISIBILITIES as readonly string[]).includes(raw as string)
    ? (raw as ActivityVisibility)
    : 'private'
}

/**
 * Decide whether `viewerId` may see an activity owned by `ownerId` given its
 * `visibility`. Pure: the caller supplies `isFriend` (resolved separately).
 * - owner always sees their own activity, whatever the visibility
 * - 'public'  → anyone
 * - 'friends' → accepted friends only
 * - 'private' → owner only
 */
export function canViewActivity(args: {
  viewerId: string
  ownerId: string
  visibility: unknown
  isFriend: boolean
}): boolean {
  const { viewerId, ownerId, isFriend } = args
  if (viewerId === ownerId) return true
  const visibility = normalizeVisibility(args.visibility)
  if (visibility === 'public') return true
  if (visibility === 'friends') return isFriend
  return false
}

/**
 * Metres of polyline trimmed from each end before a non-owner sees the route.
 * Hides the start (home/gym) and finish so they can't be geolocated from a
 * shared map. ~200 m balances privacy against still showing a usable track.
 */
export const ROUTE_FUZZ_RADIUS_M = 200

/**
 * Trim the first/last ~`radiusM` metres of a polyline for non-owner viewers.
 * Walks inward from each end dropping points until the cumulative distance from
 * the original endpoint exceeds `radiusM`, so home/start/finish aren't exposed.
 * Owners get the untouched array — callers must only fuzz for non-owners.
 *
 * Degenerate inputs (≤2 points, or a route shorter than 2× the radius) collapse
 * to a single midpoint rather than leaking a precise start or end coordinate.
 */
export function fuzzRoutePoints(
  points: RoutePoint[],
  radiusM: number = ROUTE_FUZZ_RADIUS_M,
): RoutePoint[] {
  if (radiusM <= 0) return points.slice()
  if (points.length <= 2) {
    return points.length === 0 ? [] : [points[Math.floor(points.length / 2)]]
  }

  // First index whose cumulative distance from the start exceeds the radius.
  let startIdx = 0
  let acc = 0
  for (let i = 1; i < points.length; i++) {
    acc += haversineMeters(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng)
    if (acc > radiusM) {
      startIdx = i
      break
    }
    startIdx = i
  }

  // Last index whose cumulative distance from the end exceeds the radius.
  let endIdx = points.length - 1
  acc = 0
  for (let i = points.length - 1; i > 0; i--) {
    acc += haversineMeters(points[i].lat, points[i].lng, points[i - 1].lat, points[i - 1].lng)
    if (acc > radiusM) {
      endIdx = i - 1
      break
    }
    endIdx = i - 1
  }

  // Route too short to trim both ends without crossing over → keep one midpoint.
  if (startIdx >= endIdx) {
    return [points[Math.floor((points.length - 1) / 2)]]
  }
  return points.slice(startIdx, endIdx + 1)
}

const GpsActivitySchema = z.object({
  activity_type: z.enum(['run', 'ride', 'bike', 'cycle', 'walk', 'swim', 'cardio']).optional(),
  route_points: z.array(z.unknown()).max(100_000).optional(),
  distance_m: z.number().min(0).max(500_000).optional(),
  duration_s: z.number().int().min(0).max(86_400).optional(),
  calories: z.number().int().min(0).max(50_000).optional(),
  visibility: z.enum(ACTIVITY_VISIBILITIES).optional(),
  started_at: z.string().datetime({ offset: true }).optional(),
  ended_at: z.string().datetime({ offset: true }).optional(),
})

/**
 * Body for POST /v1/activities/import. The file is delivered as a string in the
 * JSON body (raw XML in `content`, or base64 in `contentBase64`) so we don't pull
 * in a multipart dependency. `filename` is an optional hint for format detection;
 * the file body itself always wins. ~8 MiB of base64 ≈ a very large track.
 */
const ImportActivitySchema = z
  .object({
    content: z.string().min(1).max(12_000_000).optional(),
    contentBase64: z.string().min(1).max(16_000_000).optional(),
    filename: z.string().max(256).optional(),
    visibility: z.enum(ACTIVITY_VISIBILITIES).optional(),
    activity_type: z.enum(['run', 'ride', 'bike', 'cycle', 'walk', 'swim', 'cardio']).optional(),
  })
  .refine((b) => b.content != null || b.contentBase64 != null, {
    message: 'content or contentBase64 required',
  })

/** Map a parse-error code onto an HTTP status. Malformed/empty → 400; rest → 422. */
function importErrorStatus(code: ActivityFileParseError['code']): number {
  return code === 'EMPTY_FILE' || code === 'MALFORMED_XML' ? 400 : 422
}

/** Zile cu antrenament (gym) într-o lună — task Excel #16 / #18. */
export async function activitiesRoutes(app: FastifyInstance) {
  /**
   * POST /v1/activities — ingest a recorded GPS outdoor session.
   *
   * Anti-cheat: whenever route_points are present, distance / duration / avg
   * speed / elevation gain are recomputed server-side from the points and the
   * server values are persisted (client-sent metrics are ignored).  If no
   * usable points are supplied we fall back to the client-reported values.
   */
  app.post('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = GpsActivitySchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'route_points, distance_m, duration_s, started_at required',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const body = parsed.data
    const startedAt = body.started_at ? new Date(body.started_at) : new Date()
    const endedAt = body.ended_at ? new Date(body.ended_at) : null

    // Server-validated elapsed duration: prefer the timestamp span, but never
    // exceed the client duration by more than its own value and clamp to a day.
    const spanS =
      endedAt != null ? Math.max(0, Math.round((endedAt.getTime() - startedAt.getTime()) / 1000)) : 0
    const clientDurationS = body.duration_s ?? 0
    const elapsedS = Math.min(86_400, spanS > 0 ? spanS : clientDurationS)

    // Recompute from the route; null when too few usable points → keep client values.
    const metrics = computeRouteMetrics(body.route_points, elapsedS)

    const distanceM = metrics != null ? metrics.distanceM : (body.distance_m ?? null)
    const durationS = elapsedS > 0 ? elapsedS : (body.duration_s ?? null)

    const routePoints = normalizeRoutePoints(body.route_points)
    const visibility = normalizeVisibility(body.visibility)
    const activityType = canonicalGpsType(body.activity_type)

    const activity = await prisma.gpsActivity.create({
      data: {
        userId,
        activityType,
        routePoints,
        distanceM,
        durationS,
        // Persist the server-recomputed metrics (anti-cheat); null when too few
        // usable points let us recompute them.
        elevGainM: metrics?.elevGainM ?? null,
        avgSpeedMs: metrics?.avgSpeedMs ?? null,
        visibility,
        calories: body.calories ?? null,
        startedAt,
        endedAt,
      },
    })

    await prisma.analyticsEvent.create({
      data: {
        userId,
        eventName: 'gps_activity_ingested',
        props: {
          activityId: activity.id,
          recomputed: metrics != null,
          pointCount: routePoints.length,
          droppedPoints: metrics?.droppedPoints ?? 0,
          serverDistanceM: distanceM,
          clientDistanceM: body.distance_m ?? null,
          elevGainM: metrics?.elevGainM ?? null,
        },
      },
    })

    // Per-km splits from the same trusted route the metrics came from, so the
    // client can render the splits table without re-fetching the activity.
    const splits = computeSplits(routePoints, durationS ?? 0)

    return reply.code(201).send({
      activity: {
        id: activity.id,
        type: normalizeGpsActivity(activity).type,
        distanceM: activity.distanceM,
        durationS: activity.durationS,
        calories: activity.calories,
        elevGainM: activity.elevGainM,
        avgSpeedMs: activity.avgSpeedMs,
        // Moving time excludes auto-paused (stationary) segments; additive and
        // derived from the recomputed route, null when too few usable points.
        movingTimeS: metrics?.movingTimeS ?? null,
        movingPaceSecsPerKm: metrics?.movingPaceSecsPerKm ?? null,
        visibility: activity.visibility,
        startedAt: activity.startedAt.toISOString(),
        endedAt: activity.endedAt ? activity.endedAt.toISOString() : null,
        recomputed: metrics != null,
        splits,
      },
    })
  })

  /**
   * POST /v1/activities/import — import a recorded GPS session from a GPX or TCX
   * file. The file arrives as a string in the JSON body (`content` raw XML, or
   * `contentBase64`) — no multipart dependency required.
   *
   * The track is parsed clean-room (GPX/TCX), then flows through the EXISTING
   * server-side metric recompute (`computeRouteMetrics`) so an imported activity
   * gets the same trusted distance / duration / elevation / avg-speed as a live
   * recording. A new GpsActivity is created; existing create/GET are untouched.
   *
   * FIT (binary) is intentionally not handled here — `.fit` is rejected with 415
   * UNSUPPORTED_FORMAT (FIT-as-followup, would need a maintained binary parser).
   *
   * Errors are per-file and explicit: malformed/empty XML → 400, recognised but
   * unusable (no points / unknown format) → 422, .fit → 415.
   */
  app.post('/import', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = ImportActivitySchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'content or contentBase64 required',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const body = parsed.data

    // Reject FIT (binary) up front — it can't be a usable XML string and we don't
    // ship a binary parser yet. Surfaced as a distinct, stable code.
    if (body.filename && body.filename.toLowerCase().endsWith('.fit')) {
      return reply.code(415).send({
        error: 'UNSUPPORTED_FORMAT',
        message: 'Importul FIT nu este încă suportat (urmează) — folosește GPX sau TCX',
        requestId: request.id,
      })
    }

    // Decode the payload to text. A bad base64 string is a client error.
    let content: string
    if (body.content != null) {
      content = body.content
    } else {
      try {
        content = Buffer.from(body.contentBase64!, 'base64').toString('utf8')
      } catch {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'contentBase64 invalid',
          requestId: request.id,
        })
      }
    }

    let parsedFile
    try {
      parsedFile = parseActivityFile(content, body.filename ?? null)
    } catch (err) {
      if (err instanceof ActivityFileParseError) {
        return reply.code(importErrorStatus(err.code)).send({
          error: err.code,
          message: err.message,
          requestId: request.id,
          file: body.filename ?? null,
        })
      }
      throw err
    }

    const points = parsedFile.points
    // Cap defensively (parser already caps) and derive the elapsed span from the
    // first/last timestamp when the track carried them.
    const trimmed = points.slice(0, MAX_IMPORT_POINTS)
    const firstT = trimmed.find((p) => p.t != null)?.t ?? null
    let lastT: number | null = null
    for (let i = trimmed.length - 1; i >= 0; i--) {
      if (trimmed[i].t != null) {
        lastT = trimmed[i].t!
        break
      }
    }
    const spanS =
      firstT != null && lastT != null && lastT > firstT
        ? Math.min(86_400, Math.round((lastT - firstT) / 1000))
        : 0

    const startedAt = firstT != null ? new Date(firstT) : new Date()
    const endedAt = lastT != null && lastT > (firstT ?? lastT) ? new Date(lastT) : null

    // Run the EXISTING trusted recompute over the imported points.
    const metrics = computeRouteMetrics(trimmed, spanS)
    const distanceM = metrics != null ? metrics.distanceM : null
    const durationS = spanS > 0 ? spanS : null

    const routePoints = normalizeRoutePoints(trimmed)
    const visibility = normalizeVisibility(body.visibility)
    const activityType = canonicalGpsType(body.activity_type)

    const activity = await prisma.gpsActivity.create({
      data: {
        userId,
        activityType,
        routePoints,
        distanceM,
        durationS,
        elevGainM: metrics?.elevGainM ?? null,
        avgSpeedMs: metrics?.avgSpeedMs ?? null,
        visibility,
        calories: null,
        startedAt,
        endedAt,
      },
    })

    await prisma.analyticsEvent.create({
      data: {
        userId,
        eventName: 'gps_activity_imported',
        props: {
          activityId: activity.id,
          format: parsedFile.format,
          pointCount: routePoints.length,
          recomputed: metrics != null,
          serverDistanceM: distanceM,
          source: body.filename ?? parsedFile.format,
        },
      },
    })

    const splits = computeSplits(routePoints, durationS ?? 0)

    return reply.code(201).send({
      activity: {
        id: activity.id,
        type: normalizeGpsActivity(activity).type,
        format: parsedFile.format,
        distanceM: activity.distanceM,
        durationS: activity.durationS,
        elevGainM: activity.elevGainM,
        avgSpeedMs: activity.avgSpeedMs,
        movingTimeS: metrics?.movingTimeS ?? null,
        movingPaceSecsPerKm: metrics?.movingPaceSecsPerKm ?? null,
        visibility: activity.visibility,
        startedAt: activity.startedAt.toISOString(),
        endedAt: activity.endedAt ? activity.endedAt.toISOString() : null,
        recomputed: metrics != null,
        pointCount: routePoints.length,
        splits,
      },
    })
  })

  /**
   * GET /v1/activities/feed — unified, time-descending activity feed for the
   * caller, normalized into ONE canonical shape across GPS sessions and completed
   * gym workouts (read-side only; no row is mutated). Useful for cross-type
   * analytics where a single timeline of effort is wanted.
   */
  app.get('/feed', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const [gpsActivities, workouts] = await Promise.all([
      prisma.gpsActivity.findMany({
        where: { userId },
        select: {
          id: true,
          userId: true,
          activityType: true,
          distanceM: true,
          durationS: true,
          calories: true,
          startedAt: true,
          endedAt: true,
        },
        orderBy: { startedAt: 'desc' },
        take: 200,
      }),
      prisma.workout.findMany({
        where: { userId, status: { in: ['completed', 'posted'] } },
        select: { id: true, userId: true, startedAt: true, endedAt: true },
        orderBy: { startedAt: 'desc' },
        take: 200,
      }),
    ])

    const feed = buildActivityFeed({ gpsActivities, workouts })
    return reply.send({ feed })
  })

  /**
   * GET /v1/activities/:id — fetch a single activity (own or shared).
   *
   * Privacy: `visibility` is enforced via `canViewActivity` — private is
   * owner-only, friends needs an accepted friendship, public is open. A viewer
   * who isn't allowed gets 404 (not 403) so private activities aren't even
   * acknowledged to exist. For NON-owner viewers the route polyline is fuzzed
   * with `fuzzRoutePoints` so the start/finish (home/gym) stay hidden; the owner
   * always gets full-precision points.
   */
  app.get('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId: viewerId } = request.user
    const { id } = request.params as { id: string }

    const activity = await prisma.gpsActivity.findUnique({ where: { id } })
    if (!activity) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Activitatea nu există',
        requestId: request.id,
      })
    }

    const isOwner = activity.userId === viewerId
    const isFriend =
      isOwner || activity.visibility !== 'friends'
        ? false
        : (await acceptedFriendIds(viewerId)).includes(activity.userId)

    if (!canViewActivity({ viewerId, ownerId: activity.userId, visibility: activity.visibility, isFriend })) {
      // Hide existence of activities the viewer can't see.
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Activitatea nu există',
        requestId: request.id,
      })
    }

    const fullPoints = normalizeRoutePoints(activity.routePoints)
    const routePoints = isOwner ? fullPoints : fuzzRoutePoints(fullPoints)

    // Splits are computed from the points the viewer is actually allowed to see:
    // the owner gets accurate full-route splits; a non-owner gets splits over
    // the fuzzed (start/finish-trimmed) polyline so the hidden home/finish
    // timing isn't reconstructable from the table.
    const splits = computeSplits(routePoints, activity.durationS ?? 0)

    // Moving time isn't a stored column, so recompute it from the points the
    // viewer is allowed to see (full for owner, fuzzed for non-owner) and the
    // trusted duration — additive, never overrides the stored elapsed durationS.
    const moving = movingTimeMetrics(routePoints, activity.durationS ?? 0)

    // Outdoor-PR summary is the viewer's own history, so only attach it for the
    // owner. Pure helper does the reduction; this just loads the rows.
    let outdoorPrs: OutdoorPrSummary | null = null
    if (isOwner) {
      const own = await prisma.gpsActivity.findMany({
        where: { userId: viewerId },
        select: { distanceM: true, durationS: true },
      })
      outdoorPrs = outdoorPrSummary(own)
    }

    return reply.send({
      activity: {
        id: activity.id,
        userId: activity.userId,
        type: normalizeGpsActivity(activity).type,
        distanceM: activity.distanceM,
        durationS: activity.durationS,
        calories: activity.calories,
        elevGainM: activity.elevGainM,
        avgSpeedMs: activity.avgSpeedMs,
        movingTimeS: moving.movingTimeS,
        movingPaceSecsPerKm: moving.movingPaceSecsPerKm,
        visibility: activity.visibility,
        startedAt: activity.startedAt.toISOString(),
        endedAt: activity.endedAt ? activity.endedAt.toISOString() : null,
        routePoints,
        fuzzed: !isOwner,
        isOwner,
        splits,
        outdoorPrs,
      },
    })
  })

  /** POST /v1/activities/cardio/complete — award game XP vs age/BW-adjusted WR pace. */
  app.post('/cardio/complete', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CardioCompleteSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'mode, distanceM, durationSec required',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const profile = await prisma.userProfile.findUnique({ where: { userId } })
    const userXp = resolveUserXpContext({
      bodyweightKg: profile?.bodyweightKg != null ? Number(profile.bodyweightKg) : null,
      birthYear: profile?.birthYear,
      sex: profile?.sex,
    })

    const { mode, distanceM, durationSec, source } = parsed.data
    const { sessionXp, breakdown } = computeCardioGameXp(mode, distanceM, durationSec, userXp)

    let gameXp = gameXpPayload(profile?.gameXpTotal ?? 0)
    if (profile && sessionXp > 0) {
      const newTotal = profile.gameXpTotal + sessionXp
      await prisma.userProfile.update({
        where: { userId },
        data: { gameXpTotal: newTotal },
      })
      gameXp = gameXpPayload(newTotal)
    }

    await prisma.analyticsEvent.create({
      data: {
        userId,
        eventName: 'cardio_completed',
        props: {
          mode,
          distanceM,
          durationSec,
          xpGain: sessionXp,
          source: source ?? 'app',
        },
      },
    })

    return reply.send({
      xpGain: sessionXp,
      xpBreakdown: breakdown,
      gameXp,
      pctOfWr: breakdown[0]?.pct ?? 0,
    })
  })

  app.get('/calendar', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CalendarQuery.safeParse(request.query)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'month=YYYY-MM, optional tzOffset (minute fata de UTC)',
        requestId: request.id,
      })
    }
    const { month, tzOffset } = parsed.data
    const [y, mo] = month.split('-').map(Number)
    const start = new Date(Date.UTC(y, mo - 1, 1, 0, 0, 0, 0))
    const end = new Date(Date.UTC(y, mo, 0, 23, 59, 59, 999))
    const padMs = 2 * 24 * 60 * 60 * 1000
    const startPad = new Date(start.getTime() - padMs)
    const endPad = new Date(end.getTime() + padMs)

    const [workouts, gpsActivities] = await Promise.all([
      prisma.workout.findMany({
        where: {
          userId,
          status: { in: ['completed', 'posted'] },
          startedAt: { gte: startPad, lte: endPad },
        },
        select: { id: true, startedAt: true },
        orderBy: { startedAt: 'asc' },
      }),
      prisma.gpsActivity.findMany({
        where: { userId, startedAt: { gte: startPad, lte: endPad } },
        select: {
          id: true,
          userId: true,
          activityType: true,
          distanceM: true,
          durationS: true,
          calories: true,
          startedAt: true,
          endedAt: true,
        },
        orderBy: { startedAt: 'asc' },
      }),
    ])

    const days: Record<
      string,
      {
        types: string[]
        workoutIds: string[]
        planned: Array<{ id: string; title: string; kind: string; status: string }>
        nutrition?: { calories: number; proteinG: number; carbsG: number; fatG: number; goal: string }
      }
    > = {}
    for (const w of workouts) {
      const key = ymdFromUtcWithOffset(w.startedAt, tzOffset)
      if (!key.startsWith(month)) continue
      if (!days[key]) days[key] = { types: [], workoutIds: [], planned: [] }
      if (!days[key].types.includes('gym')) days[key].types.push('gym')
      days[key].workoutIds.push(w.id)
    }
    for (const activity of gpsActivities) {
      const key = ymdFromUtcWithOffset(activity.startedAt, tzOffset)
      if (!key.startsWith(month)) continue
      if (!days[key]) days[key] = { types: [], workoutIds: [], planned: [] }
      const type = normalizeGpsActivity(activity).type
      if (!days[key].types.includes(type)) days[key].types.push(type)
    }

    const planned = await prisma.plannedWorkout.findMany({
      where: {
        userId,
        day: { gte: month + '-01', lte: month + '-31' },
      },
      orderBy: [{ day: 'asc' }, { createdAt: 'asc' }],
    })
    for (const p of planned) {
      if (!days[p.day]) days[p.day] = { types: [], workoutIds: [], planned: [], nutrition: undefined }
      if (!days[p.day].types.includes(p.kind)) days[p.day].types.push(p.kind)
      days[p.day].planned.push({
        id: p.id,
        title: p.title,
        kind: p.kind,
        status: p.status,
      })
    }

    // Add nutrition data for each day
    const nutritionDays = await prisma.nutritionPlanDay.findMany({
      where: {
        userId,
        day: { gte: month + '-01', lte: month + '-31' },
      },
      orderBy: { day: 'asc' },
    })
    for (const nd of nutritionDays) {
      if (!days[nd.day]) days[nd.day] = { types: [], workoutIds: [], planned: [], nutrition: undefined }
      days[nd.day].nutrition = {
        calories: nd.calories,
        proteinG: nd.proteinG,
        carbsG: nd.carbsG,
        fatG: nd.fatG,
        goal: nd.goal,
      }
    }

    return reply.send({ month, tzOffset, days })
  })
}
