import { describe, it, expect } from 'vitest'
import {
  routeDistanceMeters,
  haversineMeters,
  movingTimeMetrics,
  computeRouteMetrics,
  MOVING_SPEED_THRESHOLD_MS,
  type RoutePoint,
} from './activities'

describe('routeDistanceMeters (unified distance)', () => {
  it('returns 0 for fewer than two points', () => {
    expect(routeDistanceMeters([])).toBe(0)
    expect(routeDistanceMeters([{ lat: 45, lng: 25 }])).toBe(0)
  })

  it('sums Haversine hops over consecutive points', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0 },
      { lat: 45.001, lng: 25.0 },
      { lat: 45.002, lng: 25.0 },
    ]
    const expected =
      haversineMeters(45.0, 25.0, 45.001, 25.0) +
      haversineMeters(45.001, 25.0, 45.002, 25.0)
    expect(routeDistanceMeters(pts)).toBeCloseTo(expected, 6)
  })

  it('is the single algorithm computeRouteMetrics distance routes through', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0 },
      { lat: 45.001, lng: 25.0 },
      { lat: 45.002, lng: 25.0 },
    ]
    const m = computeRouteMetrics(pts, 60)!
    // computeRouteMetrics rounds to 2 decimals; the helper is the raw source.
    expect(m.distanceM).toBeCloseTo(Math.round(routeDistanceMeters(pts) * 100) / 100, 6)
  })
})

describe('movingTimeMetrics', () => {
  it('returns zeroes for fewer than two points or no elapsed', () => {
    expect(movingTimeMetrics([], 60)).toEqual({ movingTimeS: 0, movingPaceSecsPerKm: 0 })
    expect(movingTimeMetrics([{ lat: 45, lng: 25 }], 60)).toEqual({
      movingTimeS: 0,
      movingPaceSecsPerKm: 0,
    })
    expect(
      movingTimeMetrics(
        [
          { lat: 45, lng: 25, t: 0 },
          { lat: 45.001, lng: 25, t: 10_000 },
        ],
        0,
      ),
    ).toEqual({ movingTimeS: 0, movingPaceSecsPerKm: 0 })
  })

  it('excludes a stationary (paused) segment from moving time', () => {
    // Hop 1: ~111 m over 60 s ≈ 1.85 m/s (moving).
    // Hop 2: 0 m over 120 s (standing still — below the floor → auto-paused).
    // Hop 3: ~111 m over 60 s ≈ 1.85 m/s (moving).
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0, t: 0 },
      { lat: 45.001, lng: 25.0, t: 60_000 },
      { lat: 45.001, lng: 25.0, t: 180_000 }, // didn't move for 120 s
      { lat: 45.002, lng: 25.0, t: 240_000 },
    ]
    const { movingTimeS } = movingTimeMetrics(pts, 240)
    // Only the two 60 s moving hops count; the 120 s pause is excluded.
    expect(movingTimeS).toBe(120)
  })

  it('moving time never exceeds elapsed for a continuously moving track', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0, t: 0 },
      { lat: 45.001, lng: 25.0, t: 60_000 },
      { lat: 45.002, lng: 25.0, t: 120_000 },
    ]
    const { movingTimeS } = movingTimeMetrics(pts, 120)
    expect(movingTimeS).toBe(120)
  })

  it('derives moving pace (s/km) from distance over moving time', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0, t: 0 },
      { lat: 45.001, lng: 25.0, t: 60_000 }, // ~111 m moving
      { lat: 45.001, lng: 25.0, t: 180_000 }, // pause
      { lat: 45.002, lng: 25.0, t: 240_000 }, // ~111 m moving
    ]
    const movingDist =
      haversineMeters(45.0, 25.0, 45.001, 25.0) + haversineMeters(45.001, 25.0, 45.002, 25.0)
    const { movingTimeS, movingPaceSecsPerKm } = movingTimeMetrics(pts, 240)
    const expectedPace = Math.round((movingTimeS / movingDist) * 1000)
    expect(movingPaceSecsPerKm).toBe(expectedPace)
  })

  it('moving pace is faster (lower s/km) than elapsed pace when paused', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0, t: 0 },
      { lat: 45.001, lng: 25.0, t: 60_000 },
      { lat: 45.001, lng: 25.0, t: 180_000 }, // 120 s pause
      { lat: 45.002, lng: 25.0, t: 240_000 },
    ]
    const elapsedS = 240
    const dist = routeDistanceMeters(pts)
    const elapsedPace = (elapsedS / dist) * 1000
    const { movingPaceSecsPerKm } = movingTimeMetrics(pts, elapsedS)
    expect(movingPaceSecsPerKm).toBeLessThan(elapsedPace)
  })

  it('falls back to elapsed when timing cannot distinguish a pause (no timestamps, all below floor)', () => {
    // Two points ~11 m apart distributed over 120 s → ~0.09 m/s, below the floor,
    // but with no timestamps we can't prove a pause, so moving time = elapsed.
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0 },
      { lat: 45.0001, lng: 25.0 },
    ]
    const { movingTimeS } = movingTimeMetrics(pts, 120)
    expect(movingTimeS).toBe(120)
  })

  it('counts genuine slow walking as moving (above the floor)', () => {
    // ~111 m over 120 s ≈ 0.93 m/s — slow walk, comfortably above the floor.
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0, t: 0 },
      { lat: 45.001, lng: 25.0, t: 120_000 },
    ]
    const { movingTimeS } = movingTimeMetrics(pts, 120)
    expect(movingTimeS).toBe(120)
  })

  it('MOVING_SPEED_THRESHOLD_MS sits below a slow walk', () => {
    expect(MOVING_SPEED_THRESHOLD_MS).toBeGreaterThan(0)
    expect(MOVING_SPEED_THRESHOLD_MS).toBeLessThan(1) // < ~3.6 km/h
  })
})

describe('computeRouteMetrics moving-time fields', () => {
  it('reports moving time below elapsed when the track contains a pause', () => {
    const pts: RoutePoint[] = [
      { lat: 45.0, lng: 25.0, t: 0 },
      { lat: 45.001, lng: 25.0, t: 60_000 },
      { lat: 45.001, lng: 25.0, t: 180_000 }, // 120 s stationary
      { lat: 45.002, lng: 25.0, t: 240_000 },
    ]
    const m = computeRouteMetrics(pts, 240)!
    expect(m.movingTimeS).toBe(120)
    expect(m.movingTimeS).toBeLessThan(240) // elapsed
    expect(m.movingPaceSecsPerKm).toBeGreaterThan(0)
  })

  it('preserves existing distance/elevation/avgSpeed outputs (additive change)', () => {
    const pts = [
      { lat: 45.0, lng: 25.0, ele: 100 },
      { lat: 45.001, lng: 25.0, ele: 110 },
      { lat: 45.002, lng: 25.0, ele: 115 },
    ]
    const m = computeRouteMetrics(pts, 60)!
    expect(m.distanceM).toBeGreaterThan(220)
    expect(m.distanceM).toBeLessThan(224)
    expect(m.elevGainM).toBe(15)
    expect(m.avgSpeedMs).toBeCloseTo(m.distanceM / 60, 2)
    expect(m.usedPoints).toBe(3)
  })
})
