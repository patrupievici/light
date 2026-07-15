import { describe, it, expect } from 'vitest'
import {
  classifyGpsType,
  canonicalGpsType,
  normalizeGpsActivity,
  normalizeWorkout,
  buildActivityFeed,
  WALK_MAX_SPEED_MS,
  RUN_MAX_SPEED_MS,
  type NormalizableGpsActivity,
  type NormalizableWorkout,
} from './activity-normalize'

const T0 = new Date('2026-06-01T06:00:00Z')

function gps(over: Partial<NormalizableGpsActivity> = {}): NormalizableGpsActivity {
  return {
    id: 'g1',
    userId: 'u1',
    distanceM: 5000,
    durationS: 1500, // 5 km in 25 min → ~3.33 m/s → run
    calories: 300,
    startedAt: T0,
    endedAt: null,
    ...over,
  }
}

describe('classifyGpsType', () => {
  it('classifies walking pace as walk', () => {
    // 1.5 m/s, well under the walk ceiling.
    expect(classifyGpsType(1500, 1000)).toBe('walk')
    expect(WALK_MAX_SPEED_MS).toBeGreaterThan(0)
  })

  it('classifies running pace as run', () => {
    expect(classifyGpsType(5000, 1500)).toBe('run') // ~3.33 m/s
  })

  it('classifies fast pace as ride', () => {
    // 10 m/s, above the run ceiling → wheels.
    expect(classifyGpsType(10000, 1000)).toBe('ride')
    expect(RUN_MAX_SPEED_MS).toBeGreaterThan(WALK_MAX_SPEED_MS)
  })

  it('falls back to cardio when distance/duration are unusable', () => {
    expect(classifyGpsType(null, 1000)).toBe('cardio')
    expect(classifyGpsType(5000, null)).toBe('cardio')
    expect(classifyGpsType(0, 0)).toBe('cardio')
  })
})

describe('canonicalGpsType', () => {
  it('normalizes cycling aliases and rejects unknown values', () => {
    expect(canonicalGpsType('bike')).toBe('ride')
    expect(canonicalGpsType('cycle')).toBe('ride')
    expect(canonicalGpsType('swimming')).toBe('swim')
    expect(canonicalGpsType('unknown')).toBeNull()
  })
})

describe('normalizeGpsActivity', () => {
  it('prefers the explicit sport over speed inference', () => {
    const dto = normalizeGpsActivity(
      gps({ activityType: 'ride', distanceM: 10_000, durationS: 3_600 }),
    )
    expect(dto.type).toBe('ride')
  })

  it('maps a GPS activity to the canonical shape', () => {
    const dto = normalizeGpsActivity(gps())
    expect(dto).toEqual({
      id: 'g1',
      userId: 'u1',
      type: 'run',
      startedAt: T0.toISOString(),
      durationS: 1500,
      distanceM: 5000,
      calories: 300,
      source: 'gps',
    })
  })

  it('prefers the started→ended span over the stored durationS', () => {
    const dto = normalizeGpsActivity(
      gps({ durationS: 999, endedAt: new Date('2026-06-01T06:10:00Z') }),
    )
    expect(dto.durationS).toBe(600) // 10 min span beats the stored 999
  })

  it('nulls out non-positive distance and negative calories', () => {
    const dto = normalizeGpsActivity(gps({ distanceM: 0, calories: -5 }))
    expect(dto.distanceM).toBeNull()
    expect(dto.calories).toBeNull()
  })
})

describe('normalizeWorkout', () => {
  it('maps a completed workout as gym with no distance/calories', () => {
    const w: NormalizableWorkout = {
      id: 'w1',
      userId: 'u1',
      startedAt: T0,
      endedAt: new Date('2026-06-01T07:00:00Z'),
    }
    const dto = normalizeWorkout(w)
    expect(dto).toEqual({
      id: 'w1',
      userId: 'u1',
      type: 'gym',
      startedAt: T0.toISOString(),
      durationS: 3600,
      distanceM: null,
      calories: null,
      source: 'gym',
    })
  })

  it('returns null duration when there is no end time', () => {
    const dto = normalizeWorkout({ id: 'w2', userId: 'u1', startedAt: T0, endedAt: null })
    expect(dto.durationS).toBeNull()
  })
})

describe('buildActivityFeed', () => {
  it('merges both sources and sorts newest first', () => {
    const feed = buildActivityFeed({
      gpsActivities: [
        gps({ id: 'old', startedAt: new Date('2026-05-01T06:00:00Z') }),
        gps({ id: 'new', startedAt: new Date('2026-06-10T06:00:00Z') }),
      ],
      workouts: [
        { id: 'mid', userId: 'u1', startedAt: new Date('2026-06-05T06:00:00Z'), endedAt: null },
      ],
    })
    expect(feed.map((a) => a.id)).toEqual(['new', 'mid', 'old'])
    expect(feed.map((a) => a.source)).toEqual(['gps', 'gym', 'gps'])
  })

  it('handles missing inputs gracefully', () => {
    expect(buildActivityFeed({})).toEqual([])
  })
})
