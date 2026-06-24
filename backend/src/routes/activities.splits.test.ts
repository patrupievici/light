import { describe, it, expect } from 'vitest'
import {
  computeSplits,
  outdoorPrSummary,
  haversineMeters,
  METERS_PER_MILE,
  MIN_PACE_PR_DISTANCE_M,
  KNOWN_PR_DISTANCES_M,
  type RoutePoint,
} from './activities'

/**
 * Build a straight north-bound route of `count` points spaced `stepDeg` apart in
 * latitude, with evenly spaced timestamps spanning `totalS` seconds. 0.001° lat
 * ≈ 111.2 m, so the default step lays down ~111 m hops — handy for hitting a
 * 1 km boundary near the 9th hop.
 */
function line(
  count: number,
  { stepDeg = 0.001, totalS = 0, ele }: { stepDeg?: number; totalS?: number; ele?: (i: number) => number } = {},
): RoutePoint[] {
  return Array.from({ length: count }, (_, i) => ({
    lat: 45.0 + i * stepDeg,
    lng: 25.0,
    t: totalS > 0 ? Math.round((i / Math.max(1, count - 1)) * totalS * 1000) : null,
    ele: ele ? ele(i) : null,
  }))
}

describe('computeSplits', () => {
  it('returns [] for too few points or a sub-split route', () => {
    expect(computeSplits([], 60)).toEqual([])
    expect(computeSplits([{ lat: 45, lng: 25 }], 60)).toEqual([])
    // ~222 m total — under one 1 km split, so only a trailing partial appears.
    const tiny = computeSplits(line(3), 60)
    expect(tiny).toHaveLength(1)
    expect(tiny[0].partial).toBe(true)
  })

  it('returns [] for a non-positive split distance', () => {
    expect(computeSplits(line(20), 600, 0)).toEqual([])
    expect(computeSplits(line(20), 600, -100)).toEqual([])
  })

  it('cuts a ~2 km route into two full km splits plus a partial', () => {
    // 19 hops × ~111.2 m ≈ 2113 m over 600 s.
    const route = line(20, { totalS: 600 })
    const splits = computeSplits(route, 600)
    expect(splits.length).toBe(3)
    expect(splits[0].index).toBe(1)
    expect(splits[1].index).toBe(2)
    // First two are full 1 km splits.
    expect(splits[0].distanceM).toBeGreaterThan(990)
    expect(splits[0].distanceM).toBeLessThan(1010)
    expect(splits[0].partial).toBe(false)
    expect(splits[1].partial).toBe(false)
    // Last is the leftover partial < 1 km.
    expect(splits[2].partial).toBe(true)
    expect(splits[2].distanceM).toBeLessThan(1000)
  })

  it('split distances sum to the full route distance', () => {
    const route = line(20, { totalS: 600 })
    let total = 0
    for (let i = 1; i < route.length; i++) {
      total += haversineMeters(route[i - 1].lat, route[i - 1].lng, route[i].lat, route[i].lng)
    }
    const splits = computeSplits(route, 600)
    const summed = splits.reduce((s, x) => s + x.distanceM, 0)
    expect(summed).toBeCloseTo(total, 0)
  })

  it('derives a sensible pace for an even-tempo run', () => {
    // Even tempo → every full km split has ≈ the same pace.
    const route = line(20, { totalS: 600 })
    const splits = computeSplits(route, 600)
    const fullSplits = splits.filter((s) => !s.partial)
    expect(fullSplits.length).toBe(2)
    // ~111.2 m/hop, ~31.6 s/hop → ~284 s/km. Allow a tolerance for interpolation.
    for (const s of fullSplits) {
      expect(s.paceSecsPerKm).toBeGreaterThan(250)
      expect(s.paceSecsPerKm).toBeLessThan(320)
    }
    // The two full-km times are within a few seconds of each other.
    expect(Math.abs(fullSplits[0].timeS - fullSplits[1].timeS)).toBeLessThan(5)
  })

  it('falls back to evenly distributed time when points lack timestamps', () => {
    const route = line(20) // no timestamps
    const splits = computeSplits(route, 600)
    expect(splits.length).toBe(3)
    // Total time across splits ≈ the supplied elapsed seconds.
    const totalTime = splits.reduce((s, x) => s + x.timeS, 0)
    expect(totalTime).toBeGreaterThan(560)
    expect(totalTime).toBeLessThanOrEqual(600)
    expect(splits[0].paceSecsPerKm).toBeGreaterThan(0)
  })

  it('reports zero pace/time when elapsed is unknown and no timestamps', () => {
    const splits = computeSplits(line(20), 0)
    expect(splits.length).toBe(3)
    for (const s of splits) {
      expect(s.timeS).toBe(0)
      expect(s.paceSecsPerKm).toBe(0)
      expect(s.distanceM).toBeGreaterThan(0)
    }
  })

  it('supports mile splits via METERS_PER_MILE', () => {
    // ~2113 m ≈ 1.31 miles → one full mile split + a partial.
    const route = line(20, { totalS: 600 })
    const splits = computeSplits(route, 600, METERS_PER_MILE)
    expect(splits.length).toBe(2)
    expect(splits[0].partial).toBe(false)
    expect(splits[0].distanceM).toBeGreaterThan(METERS_PER_MILE - 10)
    expect(splits[0].distanceM).toBeLessThan(METERS_PER_MILE + 10)
    expect(splits[1].partial).toBe(true)
  })

  it('accumulates per-split elevation gain, ignoring noise and descents', () => {
    // Steady +5 m per hop on the way up for the first km, flat after.
    const route = line(20, {
      totalS: 600,
      ele: (i) => (i <= 9 ? 100 + i * 5 : 145),
    })
    const splits = computeSplits(route, 600)
    // First km climbed ~45 m; later splits are flat.
    expect(splits[0].elevGainM).toBeGreaterThan(35)
    expect(splits[1].elevGainM).toBeLessThan(5)
  })

  it('keeps timestamps monotonic against an out-of-order sample', () => {
    const route = line(20, { totalS: 600 })
    // Rewind one sample's clock; split times must not go negative.
    route[10] = { ...route[10], t: 0 }
    const splits = computeSplits(route, 600)
    for (const s of splits) {
      expect(s.timeS).toBeGreaterThanOrEqual(0)
    }
  })
})

describe('outdoorPrSummary', () => {
  it('returns empty bests for no qualifying activities', () => {
    const s = outdoorPrSummary([
      { distanceM: null, durationS: 100 },
      { distanceM: 1000, durationS: null },
      { distanceM: 0, durationS: 100 },
      { distanceM: 1000, durationS: 0 },
    ])
    expect(s.fastestPaceSecsPerKm).toBeNull()
    expect(s.longestDistanceM).toBeNull()
    expect(s.knownDistances).toEqual([])
    expect(s.qualifyingActivities).toBe(0)
  })

  it('picks the longest distance and fastest qualifying pace', () => {
    const s = outdoorPrSummary([
      { distanceM: 5000, durationS: 1500 }, // 300 s/km
      { distanceM: 3000, durationS: 780 }, // 260 s/km (fastest)
      { distanceM: 12000, durationS: 4200 }, // longest, 350 s/km
    ])
    expect(s.longestDistanceM).toBe(12000)
    expect(s.fastestPaceSecsPerKm).toBe(260)
    expect(s.qualifyingActivities).toBe(3)
  })

  it('ignores tiny activities for the pace PR but still counts distance', () => {
    const s = outdoorPrSummary([
      { distanceM: MIN_PACE_PR_DISTANCE_M - 1, durationS: 30 }, // too short for pace PR
      { distanceM: 2000, durationS: 600 }, // 300 s/km
    ])
    // The 100 m blip's absurd pace must not become the record.
    expect(s.fastestPaceSecsPerKm).toBe(300)
    expect(s.qualifyingActivities).toBe(2)
    expect(s.longestDistanceM).toBe(2000)
  })

  it('reports fastest known-distance PRs only for distances reached', () => {
    const s = outdoorPrSummary([
      { distanceM: 6000, durationS: 1800 }, // reaches 1k + 5k @ 300 s/km
      { distanceM: 1200, durationS: 312 }, // reaches 1k @ 260 s/km (faster 1k)
    ])
    const byDist = Object.fromEntries(s.knownDistances.map((k) => [k.distanceM, k]))
    expect(byDist[1000].paceSecsPerKm).toBe(260) // best 1k from the faster run
    expect(byDist[1000].timeS).toBe(260)
    expect(byDist[5000].paceSecsPerKm).toBe(300)
    expect(byDist[5000].timeS).toBe(1500)
    // No 10k PR — nobody reached 10 km.
    expect(byDist[10000]).toBeUndefined()
  })

  it('known distances come back sorted ascending', () => {
    const s = outdoorPrSummary([{ distanceM: 11000, durationS: 3300 }])
    expect(s.knownDistances.map((k) => k.distanceM)).toEqual([...KNOWN_PR_DISTANCES_M])
  })
})
