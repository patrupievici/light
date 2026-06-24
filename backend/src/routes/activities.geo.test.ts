import { describe, it, expect } from 'vitest'
import {
  haversineMeters,
  normalizeRoutePoints,
  filterOutlierPoints,
  elevationGainMeters,
  computeRouteMetrics,
  canViewActivity,
  normalizeVisibility,
  fuzzRoutePoints,
  ROUTE_FUZZ_RADIUS_M,
  MAX_PLAUSIBLE_SPEED_MS,
  type RoutePoint,
} from './activities'

describe('haversineMeters', () => {
  it('returns 0 for identical points', () => {
    expect(haversineMeters(45, 25, 45, 25)).toBe(0)
  })

  it('matches a known short distance within 1%', () => {
    // ~111.3 m per 0.001° of latitude near the equator-ish band.
    const d = haversineMeters(45.0, 25.0, 45.001, 25.0)
    expect(d).toBeGreaterThan(110)
    expect(d).toBeLessThan(113)
  })

  it('matches a known longer distance (London → Paris ≈ 343 km)', () => {
    const d = haversineMeters(51.5074, -0.1278, 48.8566, 2.3522)
    expect(d).toBeGreaterThan(340_000)
    expect(d).toBeLessThan(346_000)
  })
})

describe('normalizeRoutePoints', () => {
  it('keeps valid {lat,lng} points and drops invalid ones', () => {
    const pts = normalizeRoutePoints([
      { lat: 45, lng: 25 },
      { lat: 999, lng: 25 }, // bad lat
      { lat: 45 }, // missing lng
      { latitude: 46, longitude: 26 }, // alias shape
      'garbage',
      null,
    ])
    expect(pts).toHaveLength(2)
    expect(pts[0]).toMatchObject({ lat: 45, lng: 25 })
    expect(pts[1]).toMatchObject({ lat: 46, lng: 26 })
  })

  it('parses optional elevation and timestamp aliases', () => {
    const pts = normalizeRoutePoints([{ lat: 45, lng: 25, elevation: 100, ts: 1000 }])
    expect(pts[0].ele).toBe(100)
    expect(pts[0].t).toBe(1000)
  })

  it('returns [] for non-array input', () => {
    expect(normalizeRoutePoints(undefined)).toEqual([])
    expect(normalizeRoutePoints({ lat: 1 })).toEqual([])
  })
})

describe('filterOutlierPoints', () => {
  it('keeps all points when speeds are plausible', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0 },
      { lat: 45.0001, lng: 25.0 }, // ~11 m
      { lat: 45.0002, lng: 25.0 },
    ]
    const { kept, dropped } = filterOutlierPoints(pts, 5) // 5 s/hop → ~2.2 m/s
    expect(kept).toHaveLength(3)
    expect(dropped).toBe(0)
  })

  it('drops a teleport spike that implies impossible speed', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0 },
      { lat: 46.0, lng: 25.0 }, // ~111 km in one 1 s hop → absurd
      { lat: 45.0001, lng: 25.0 },
    ]
    const { kept, dropped } = filterOutlierPoints(pts, 1)
    expect(dropped).toBe(1)
    expect(kept).toHaveLength(2)
    // the kept point after the spike is the realistic one near the start
    expect(kept[1].lat).toBeCloseTo(45.0001, 4)
  })

  it('uses per-point timestamps when available', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0, t: 0 },
      { lat: 45.01, lng: 25.0, t: 60_000 }, // ~1.1 km over 60 s ≈ 18.5 m/s → ok
    ]
    const { dropped } = filterOutlierPoints(pts, 1)
    expect(dropped).toBe(0)
  })

  it('rejects the same hop when no time delta and short fallback dt', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0 },
      { lat: 45.01, lng: 25.0 }, // ~1.1 km in 1 s → way over the cap
    ]
    const { dropped } = filterOutlierPoints(pts, 1)
    expect(dropped).toBe(1)
  })

  it('returns the single point unchanged', () => {
    const pts: RoutePoint[] = [{ lat: 45, lng: 25 }]
    expect(filterOutlierPoints(pts, 1)).toEqual({ kept: pts, dropped: 0 })
  })
})

describe('elevationGainMeters', () => {
  it('sums only positive rises above the noise threshold', () => {
    const pts: RoutePoint[] = [
      { lat: 0, lng: 0, ele: 100 },
      { lat: 0, lng: 0, ele: 110 }, // +10
      { lat: 0, lng: 0, ele: 105 }, // descent ignored
      { lat: 0, lng: 0, ele: 130 }, // +25
      { lat: 0, lng: 0, ele: 130.4 }, // +0.4 noise ignored
    ]
    expect(elevationGainMeters(pts)).toBe(35)
  })

  it('returns 0 when no altitude data present', () => {
    const pts: RoutePoint[] = [
      { lat: 0, lng: 0 },
      { lat: 0, lng: 0 },
    ]
    expect(elevationGainMeters(pts)).toBe(0)
  })
})

describe('computeRouteMetrics', () => {
  it('returns null for fewer than 2 usable points', () => {
    expect(computeRouteMetrics([{ lat: 45, lng: 25 }], 60)).toBeNull()
    expect(computeRouteMetrics([], 60)).toBeNull()
    expect(computeRouteMetrics(undefined, 60)).toBeNull()
  })

  it('computes distance, avg speed and elevation from a clean route', () => {
    const pts = [
      { lat: 45.0, lng: 25.0, ele: 100 },
      { lat: 45.001, lng: 25.0, ele: 110 }, // ~111 m, +10 m
      { lat: 45.002, lng: 25.0, ele: 115 }, // ~111 m, +5 m
    ]
    const m = computeRouteMetrics(pts, 60)!
    expect(m).not.toBeNull()
    expect(m.distanceM).toBeGreaterThan(220)
    expect(m.distanceM).toBeLessThan(224)
    expect(m.elevGainM).toBe(15)
    expect(m.avgSpeedMs).toBeCloseTo(m.distanceM / 60, 2)
    expect(m.droppedPoints).toBe(0)
    expect(m.usedPoints).toBe(3)
  })

  it('excludes outlier-inflated distance from the total', () => {
    const clean = [
      { lat: 45.0, lng: 25.0 },
      { lat: 45.001, lng: 25.0 },
    ]
    const withSpike = [
      { lat: 45.0, lng: 25.0 },
      { lat: 48.0, lng: 25.0 }, // teleport spike
      { lat: 45.001, lng: 25.0 },
    ]
    const cleanM = computeRouteMetrics(clean, 60)!
    const spikedM = computeRouteMetrics(withSpike, 60)!
    expect(spikedM.droppedPoints).toBe(1)
    // After dropping the spike the distance is close to the clean route, not inflated.
    expect(spikedM.distanceM).toBeLessThan(cleanM.distanceM * 1.1)
  })

  it('handles elapsedS=0 without dividing by zero', () => {
    const m = computeRouteMetrics(
      [
        { lat: 45.0, lng: 25.0 },
        { lat: 45.001, lng: 25.0 },
      ],
      0,
    )!
    expect(m.avgSpeedMs).toBe(0)
    expect(m.distanceM).toBeGreaterThan(0)
  })
})

describe('MAX_PLAUSIBLE_SPEED_MS sanity', () => {
  it('is a positive cap in a reasonable range', () => {
    expect(MAX_PLAUSIBLE_SPEED_MS).toBeGreaterThan(20)
    expect(MAX_PLAUSIBLE_SPEED_MS).toBeLessThan(100)
  })
})

describe('normalizeVisibility', () => {
  it('passes through the three known values', () => {
    expect(normalizeVisibility('private')).toBe('private')
    expect(normalizeVisibility('friends')).toBe('friends')
    expect(normalizeVisibility('public')).toBe('public')
  })

  it('defaults unknown/garbage to private (privacy by default)', () => {
    expect(normalizeVisibility('everyone')).toBe('private')
    expect(normalizeVisibility('')).toBe('private')
    expect(normalizeVisibility(null)).toBe('private')
    expect(normalizeVisibility(undefined)).toBe('private')
    expect(normalizeVisibility(42)).toBe('private')
  })
})

describe('canViewActivity', () => {
  const owner = 'owner-1'
  const other = 'viewer-2'

  it('owner always sees their own activity regardless of visibility', () => {
    for (const visibility of ['private', 'friends', 'public', 'garbage']) {
      expect(canViewActivity({ viewerId: owner, ownerId: owner, visibility, isFriend: false })).toBe(true)
    }
  })

  it('public is visible to anyone', () => {
    expect(canViewActivity({ viewerId: other, ownerId: owner, visibility: 'public', isFriend: false })).toBe(true)
  })

  it('friends is visible only to accepted friends', () => {
    expect(canViewActivity({ viewerId: other, ownerId: owner, visibility: 'friends', isFriend: true })).toBe(true)
    expect(canViewActivity({ viewerId: other, ownerId: owner, visibility: 'friends', isFriend: false })).toBe(false)
  })

  it('private is hidden from everyone but the owner', () => {
    expect(canViewActivity({ viewerId: other, ownerId: owner, visibility: 'private', isFriend: true })).toBe(false)
    expect(canViewActivity({ viewerId: other, ownerId: owner, visibility: 'private', isFriend: false })).toBe(false)
  })

  it('unknown visibility is treated as private for non-owners', () => {
    expect(canViewActivity({ viewerId: other, ownerId: owner, visibility: 'wat', isFriend: true })).toBe(false)
  })
})

describe('fuzzRoutePoints', () => {
  // A ~1 km north-bound straight line: 0.001° lat ≈ 111 m per hop, 10 hops.
  const longRoute: RoutePoint[] = Array.from({ length: 11 }, (_, i) => ({
    lat: 45.0 + i * 0.001,
    lng: 25.0,
  }))

  it('trims both ends so the original start/finish are not exposed', () => {
    const out = fuzzRoutePoints(longRoute, ROUTE_FUZZ_RADIUS_M)
    expect(out.length).toBeGreaterThan(0)
    expect(out.length).toBeLessThan(longRoute.length)
    // First/last returned points differ from the true endpoints (home hidden).
    expect(out[0]).not.toEqual(longRoute[0])
    expect(out[out.length - 1]).not.toEqual(longRoute[longRoute.length - 1])
  })

  it('removes at least ~200 m of polyline from each end', () => {
    const out = fuzzRoutePoints(longRoute, ROUTE_FUZZ_RADIUS_M)
    const startGap = haversineMeters(longRoute[0].lat, longRoute[0].lng, out[0].lat, out[0].lng)
    const last = out[out.length - 1]
    const trueLast = longRoute[longRoute.length - 1]
    const endGap = haversineMeters(trueLast.lat, trueLast.lng, last.lat, last.lng)
    expect(startGap).toBeGreaterThan(ROUTE_FUZZ_RADIUS_M)
    expect(endGap).toBeGreaterThan(ROUTE_FUZZ_RADIUS_M)
  })

  it('keeps the interior of the route intact', () => {
    const out = fuzzRoutePoints(longRoute, ROUTE_FUZZ_RADIUS_M)
    // every kept point is one of the originals (we trim, never invent)
    for (const p of out) {
      expect(longRoute).toContainEqual(p)
    }
  })

  it('collapses a too-short route to a single midpoint (no precise endpoints)', () => {
    const shortRoute: RoutePoint[] = [
      { lat: 45.0, lng: 25.0 },
      { lat: 45.0001, lng: 25.0 }, // ~11 m total — far under 2×200 m
      { lat: 45.0002, lng: 25.0 },
    ]
    const out = fuzzRoutePoints(shortRoute, ROUTE_FUZZ_RADIUS_M)
    expect(out).toHaveLength(1)
    expect(out[0]).not.toEqual(shortRoute[0])
    expect(out[0]).not.toEqual(shortRoute[shortRoute.length - 1])
  })

  it('handles ≤2 points without leaking a precise endpoint', () => {
    expect(fuzzRoutePoints([], ROUTE_FUZZ_RADIUS_M)).toEqual([])
    expect(fuzzRoutePoints([{ lat: 45, lng: 25 }], ROUTE_FUZZ_RADIUS_M)).toHaveLength(1)
    expect(
      fuzzRoutePoints([{ lat: 45, lng: 25 }, { lat: 45.5, lng: 25 }], ROUTE_FUZZ_RADIUS_M),
    ).toHaveLength(1)
  })

  it('with radius 0 returns the full route (owner-equivalent)', () => {
    expect(fuzzRoutePoints(longRoute, 0)).toEqual(longRoute)
  })

  it('ROUTE_FUZZ_RADIUS_M is ~200 m', () => {
    expect(ROUTE_FUZZ_RADIUS_M).toBeGreaterThanOrEqual(150)
    expect(ROUTE_FUZZ_RADIUS_M).toBeLessThanOrEqual(300)
  })
})
