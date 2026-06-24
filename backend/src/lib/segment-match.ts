// ─── Segment path-following + direction validation ───────────────────────────
//
// When a recorded GPS activity is submitted as an effort on a named segment we
// must confirm the activity actually FOLLOWED the segment polyline in the
// correct DIRECTION — not merely passed near the two endpoints. A naïve
// endpoint-proximity check accepts reversed runs, shortcuts and off-path detours
// that happen to start/finish nearby, which corrupts the leaderboard.
//
// This module holds the pure, dependency-free geometry used by the matcher so it
// can be unit-tested in isolation. The matching strategy:
//
//   1. Walk the segment polyline vertex-by-vertex (the segment's `route_points`).
//   2. For each polyline vertex, scan the activity track for the closest sample
//      that lies AHEAD of the previous match (monotone cursor) and within the
//      corridor tolerance.
//   3. If every vertex is matched in order, the activity traversed the polyline
//      start→end inside the corridor → forward match.
//   4. Direction is derived from the same monotone walk: a reversed run cannot
//      satisfy the forward ordered scan (its samples appear in the opposite
//      order), so it is rejected. We additionally probe the reverse polyline to
//      label reversed efforts distinctly from genuinely off-path ones.
//
// Coordinates are in degrees (lat/lng). Distances are in metres. We use an
// equirectangular local projection for point-to-segment distance, which is
// accurate to well under a percent at the corridor scales involved (tens of
// metres) and is far cheaper than per-call Haversine on the inner loop.

/** Minimal lat/lng pair. Compatible with the activities `RoutePoint` shape. */
export type LatLng = { lat: number; lng: number }

const EARTH_RADIUS_M = 6_371_000
const DEG2RAD = Math.PI / 180

/** Default corridor half-width (m): how far off the polyline a sample may stray. */
export const DEFAULT_CORRIDOR_M = 25

/**
 * Default fraction of polyline vertices that must find an in-order, in-corridor
 * match for the traversal to count. Slightly below 1.0 to tolerate a single
 * dropped GPS fix at the very corridor edge without rejecting a legit effort.
 */
export const DEFAULT_MIN_COVERAGE = 0.8

/** Outcome label for an attempted segment match. */
export type MatchDirection = 'forward' | 'reversed' | 'off-path' | 'no-data'

export type SegmentMatchResult = {
  /** True only for a clean forward traversal that should be accepted. */
  matched: boolean
  direction: MatchDirection
  /** Fraction [0..1] of polyline vertices matched in order (forward attempt). */
  coverage: number
  /** Fraction matched in order against the reversed polyline (for labelling). */
  reverseCoverage: number
  /** Mean off-corridor distance (m) of the matched vertices, forward attempt. */
  meanDeviationM: number
}

export type SegmentMatchOptions = {
  corridorM?: number
  minCoverage?: number
}

// ─── Low-level geometry (pure) ───────────────────────────────────────────────

/**
 * Project a lat/lng to local planar metres around a reference latitude using an
 * equirectangular approximation. Good enough for the small corridors here and
 * lets us do cheap point-to-segment math in a Euclidean plane.
 */
function toLocalXY(p: LatLng, refLatRad: number): { x: number; y: number } {
  return {
    x: p.lng * DEG2RAD * Math.cos(refLatRad) * EARTH_RADIUS_M,
    y: p.lat * DEG2RAD * EARTH_RADIUS_M,
  }
}

/** Great-circle distance between two coordinates in metres (Haversine). */
export function haversineM(a: LatLng, b: LatLng): number {
  const dLat = (b.lat - a.lat) * DEG2RAD
  const dLng = (b.lng - a.lng) * DEG2RAD
  const lat1 = a.lat * DEG2RAD
  const lat2 = b.lat * DEG2RAD
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
  return EARTH_RADIUS_M * 2 * Math.asin(Math.min(1, Math.sqrt(h)))
}

/**
 * Shortest distance (m) from point `p` to the line segment `a`→`b`.
 * Handles the degenerate zero-length segment (a == b) as point distance.
 */
export function pointToSegmentM(p: LatLng, a: LatLng, b: LatLng): number {
  const refLatRad = ((a.lat + b.lat) / 2) * DEG2RAD
  const P = toLocalXY(p, refLatRad)
  const A = toLocalXY(a, refLatRad)
  const B = toLocalXY(b, refLatRad)

  const abx = B.x - A.x
  const aby = B.y - A.y
  const lenSq = abx * abx + aby * aby
  if (lenSq === 0) {
    // Degenerate segment: distance to the single point.
    const dx = P.x - A.x
    const dy = P.y - A.y
    return Math.sqrt(dx * dx + dy * dy)
  }
  // Clamp the projection parameter to [0,1] so we measure to the segment, not
  // the infinite line.
  let t = ((P.x - A.x) * abx + (P.y - A.y) * aby) / lenSq
  if (t < 0) t = 0
  else if (t > 1) t = 1
  const cx = A.x + t * abx
  const cy = A.y + t * aby
  const dx = P.x - cx
  const dy = P.y - cy
  return Math.sqrt(dx * dx + dy * dy)
}

/**
 * Shortest distance (m) from point `p` to a polyline (the nearest of its
 * constituent segments). For a single-vertex polyline this is point distance.
 */
export function pointToPolylineM(p: LatLng, polyline: LatLng[]): number {
  if (polyline.length === 0) return Number.POSITIVE_INFINITY
  if (polyline.length === 1) return haversineM(p, polyline[0])
  let best = Number.POSITIVE_INFINITY
  for (let i = 1; i < polyline.length; i++) {
    const d = pointToSegmentM(p, polyline[i - 1], polyline[i])
    if (d < best) best = d
  }
  return best
}

// ─── Ordered-progress (path-following) check ─────────────────────────────────

/**
 * Walk `polyline` vertex-by-vertex against `track`, advancing a monotone cursor
 * through the track so matches must occur in increasing order. A reversed or
 * out-of-order track cannot satisfy this scan. Returns the fraction of polyline
 * vertices matched within `corridorM`, plus the mean deviation of matches.
 *
 * Pure: no DB, no clock, no mutation of inputs.
 */
export function orderedProgress(
  polyline: LatLng[],
  track: LatLng[],
  corridorM: number,
): { coverage: number; meanDeviationM: number; matchedCount: number } {
  if (polyline.length === 0 || track.length === 0) {
    return { coverage: 0, meanDeviationM: Number.POSITIVE_INFINITY, matchedCount: 0 }
  }
  let cursor = 0
  let matched = 0
  let devSum = 0
  for (const vertex of polyline) {
    let bestDist = Number.POSITIVE_INFINITY
    let bestIdx = -1
    // Scan only forward from the cursor → enforces ordered traversal.
    for (let j = cursor; j < track.length; j++) {
      const d = haversineM(vertex, track[j])
      if (d < bestDist) {
        bestDist = d
        bestIdx = j
      }
    }
    if (bestIdx >= 0 && bestDist <= corridorM) {
      matched++
      devSum += bestDist
      cursor = bestIdx // never go backwards → monotone progress
    }
    // Unmatched vertex: leave cursor put so a later vertex can still match.
  }
  return {
    coverage: matched / polyline.length,
    meanDeviationM: matched > 0 ? devSum / matched : Number.POSITIVE_INFINITY,
    matchedCount: matched,
  }
}

// ─── Top-level matcher ───────────────────────────────────────────────────────

/**
 * Decide whether `track` (the activity's GPS samples) followed `polyline` (the
 * segment route) in the forward direction within a corridor.
 *
 * - `forward`  : ordered forward coverage ≥ minCoverage and ≥ reverse coverage.
 *                → `matched: true`.
 * - `reversed` : reverse coverage ≥ minCoverage and beats forward → run was
 *                done backwards. Rejected (`matched: false`).
 * - `off-path` : neither direction reaches minCoverage. Rejected.
 * - `no-data`  : insufficient geometry to judge. Rejected (caller decides
 *                whether to fall back to legacy behaviour).
 */
export function matchSegmentEffort(
  polyline: LatLng[],
  track: LatLng[],
  opts: SegmentMatchOptions = {},
): SegmentMatchResult {
  const corridorM = opts.corridorM ?? DEFAULT_CORRIDOR_M
  const minCoverage = opts.minCoverage ?? DEFAULT_MIN_COVERAGE

  if (polyline.length < 2 || track.length < 2) {
    return {
      matched: false,
      direction: 'no-data',
      coverage: 0,
      reverseCoverage: 0,
      meanDeviationM: Number.POSITIVE_INFINITY,
    }
  }

  const fwd = orderedProgress(polyline, track, corridorM)
  const reversed = polyline.slice().reverse()
  const rev = orderedProgress(reversed, track, corridorM)

  const forwardOk = fwd.coverage >= minCoverage
  const reverseOk = rev.coverage >= minCoverage

  let direction: MatchDirection
  let matched = false
  if (forwardOk && fwd.coverage >= rev.coverage) {
    direction = 'forward'
    matched = true
  } else if (reverseOk) {
    direction = 'reversed'
  } else {
    direction = 'off-path'
  }

  return {
    matched,
    direction,
    coverage: fwd.coverage,
    reverseCoverage: rev.coverage,
    meanDeviationM: fwd.meanDeviationM,
  }
}
