import { describe, it, expect } from 'vitest'
import {
  haversineM,
  pointToSegmentM,
  pointToPolylineM,
  orderedProgress,
  matchSegmentEffort,
  downsampleEven,
  MAX_MATCH_POINTS,
  DEFAULT_CORRIDOR_M,
  type LatLng,
} from './segment-match'

// A short straight-ish polyline near 45°N. ~0.001° lat ≈ 111 m; we step in lat
// so the corridor maths stay easy to reason about.
const SEGMENT: LatLng[] = [
  { lat: 45.0000, lng: 25.0 },
  { lat: 45.0010, lng: 25.0 },
  { lat: 45.0020, lng: 25.0 },
  { lat: 45.0030, lng: 25.0 },
  { lat: 45.0040, lng: 25.0 },
]

/** Build a denser track that follows `pts` order, optionally offset east (m). */
function densify(pts: LatLng[], offsetM = 0): LatLng[] {
  // ~1 m ≈ 1 / (111320 * cos(lat)) degrees of longitude at 45°N.
  const lngPerM = 1 / (111_320 * Math.cos((45 * Math.PI) / 180))
  const out: LatLng[] = []
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i]
    out.push({ lat: a.lat, lng: a.lng + offsetM * lngPerM })
    const b = pts[i + 1]
    if (b) {
      out.push({
        lat: (a.lat + b.lat) / 2,
        lng: (a.lng + b.lng) / 2 + offsetM * lngPerM,
      })
    }
  }
  return out
}

describe('haversineM', () => {
  it('is zero for identical points', () => {
    expect(haversineM({ lat: 45, lng: 25 }, { lat: 45, lng: 25 })).toBe(0)
  })

  it('measures ~111 m per 0.001° latitude', () => {
    const d = haversineM({ lat: 45, lng: 25 }, { lat: 45.001, lng: 25 })
    expect(d).toBeGreaterThan(110)
    expect(d).toBeLessThan(113)
  })
})

describe('pointToSegmentM', () => {
  const a: LatLng = { lat: 45.0, lng: 25.0 }
  const b: LatLng = { lat: 45.002, lng: 25.0 }

  it('is ~0 for a point on the segment', () => {
    expect(pointToSegmentM({ lat: 45.001, lng: 25.0 }, a, b)).toBeLessThan(1)
  })

  it('measures perpendicular offset for a point beside the segment', () => {
    // ~10 m east of the midpoint.
    const lngPerM = 1 / (111_320 * Math.cos((45 * Math.PI) / 180))
    const p: LatLng = { lat: 45.001, lng: 25.0 + 10 * lngPerM }
    const d = pointToSegmentM(p, a, b)
    expect(d).toBeGreaterThan(9)
    expect(d).toBeLessThan(11)
  })

  it('clamps to the nearer endpoint past the segment ends', () => {
    // Well before `a` along the line → distance ≈ distance to `a`.
    const p: LatLng = { lat: 44.999, lng: 25.0 }
    const d = pointToSegmentM(p, a, b)
    const toA = haversineM(p, a)
    expect(Math.abs(d - toA)).toBeLessThan(1)
  })

  it('handles a degenerate zero-length segment as point distance', () => {
    const p: LatLng = { lat: 45.001, lng: 25.0 }
    expect(pointToSegmentM(p, a, a)).toBeCloseTo(haversineM(p, a), 1)
  })
})

describe('pointToPolylineM', () => {
  it('returns the nearest-segment distance', () => {
    const onPath: LatLng = { lat: 45.0025, lng: 25.0 }
    expect(pointToPolylineM(onPath, SEGMENT)).toBeLessThan(1)
  })

  it('is infinite for an empty polyline', () => {
    expect(pointToPolylineM({ lat: 45, lng: 25 }, [])).toBe(Number.POSITIVE_INFINITY)
  })
})

describe('orderedProgress', () => {
  it('reaches full coverage for an in-order on-path track', () => {
    const r = orderedProgress(SEGMENT, densify(SEGMENT), DEFAULT_CORRIDOR_M)
    expect(r.coverage).toBe(1)
    expect(r.meanDeviationM).toBeLessThan(1)
  })

  it('drops coverage when the track is reversed (cursor cannot rewind)', () => {
    const r = orderedProgress(SEGMENT, densify(SEGMENT.slice().reverse()), DEFAULT_CORRIDOR_M)
    expect(r.coverage).toBeLessThan(1)
  })
})

describe('matchSegmentEffort', () => {
  it('accepts a clean forward traversal', () => {
    const res = matchSegmentEffort(SEGMENT, densify(SEGMENT))
    expect(res.matched).toBe(true)
    expect(res.direction).toBe('forward')
    expect(res.coverage).toBeGreaterThanOrEqual(0.8)
  })

  it('rejects a reversed traversal', () => {
    const res = matchSegmentEffort(SEGMENT, densify(SEGMENT.slice().reverse()))
    expect(res.matched).toBe(false)
    expect(res.direction).toBe('reversed')
    expect(res.reverseCoverage).toBeGreaterThanOrEqual(res.coverage)
  })

  it('rejects an off-path track that only grazes the endpoints', () => {
    // A track ~200 m east of the polyline — far outside the 25 m corridor.
    const res = matchSegmentEffort(SEGMENT, densify(SEGMENT, 200))
    expect(res.matched).toBe(false)
    expect(res.direction).toBe('off-path')
    expect(res.coverage).toBeLessThan(0.8)
  })

  it('rejects a partial traversal that covers only the first half', () => {
    // Track follows the segment but stops at the midpoint → < minCoverage.
    const half = SEGMENT.slice(0, 2)
    const res = matchSegmentEffort(SEGMENT, densify(half))
    expect(res.matched).toBe(false)
    expect(res.direction).toBe('off-path')
    expect(res.coverage).toBeLessThan(0.8)
  })

  it('returns no-data when geometry is insufficient (legacy fallback)', () => {
    expect(matchSegmentEffort([], densify(SEGMENT)).direction).toBe('no-data')
    expect(matchSegmentEffort(SEGMENT, []).direction).toBe('no-data')
    expect(matchSegmentEffort(SEGMENT, [{ lat: 45, lng: 25 }]).direction).toBe('no-data')
  })

  it('caps a huge track so matching stays fast and still forward-matches', () => {
    // A track with far more than MAX_MATCH_POINTS samples must be downsampled
    // before the O(n·m) scan; a densely-sampled forward run still matches.
    const huge: LatLng[] = []
    const n = MAX_MATCH_POINTS * 5
    for (let i = 0; i < n; i++) {
      const f = i / (n - 1)
      huge.push({ lat: 45.0 + 0.004 * f, lng: 25.0 })
    }
    const start = Date.now()
    const res = matchSegmentEffort(SEGMENT, huge)
    expect(Date.now() - start).toBeLessThan(1000)
    expect(res.matched).toBe(true)
    expect(res.direction).toBe('forward')
  })
})

describe('downsampleEven', () => {
  it('returns the input unchanged when within the cap', () => {
    expect(downsampleEven(SEGMENT, 100)).toBe(SEGMENT)
  })

  it('caps to at most `cap` points, keeping first and last', () => {
    const pts: LatLng[] = Array.from({ length: 10_000 }, (_, i) => ({
      lat: 45 + i * 1e-5,
      lng: 25,
    }))
    const out = downsampleEven(pts, MAX_MATCH_POINTS)
    expect(out.length).toBe(MAX_MATCH_POINTS)
    expect(out[0]).toBe(pts[0])
    expect(out[out.length - 1]).toBe(pts[pts.length - 1])
  })
})
