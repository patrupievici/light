import { describe, it, expect } from 'vitest'

import {
  dedupeHealthSamples,
  valuesAreClose,
  windowOverlapRatio,
  DEFAULT_SOURCE_PRIORITY,
  type HealthSampleCandidate,
} from './health-dedup'

// The webhook ingestion path (integrations.ts) wires this in against Prisma;
// these tests cover the pure decision layer — overlap detection, value
// tolerance, source-priority winner selection, and the behavior-preserving
// single-source case.

const HOUR = 60 * 60 * 1000
// 2026-06-21T08:00:00Z as a base so windows are easy to reason about.
const T0 = Date.UTC(2026, 5, 21, 8, 0, 0)

function sample(overrides: Partial<HealthSampleCandidate> = {}): HealthSampleCandidate {
  return {
    key: overrides.key ?? 'k',
    metricType: overrides.metricType ?? 'activity',
    sourcePath: overrides.sourcePath ?? 'aggregator',
    provider: overrides.provider ?? null,
    startAt: overrides.startAt ?? T0,
    endAt: overrides.endAt ?? T0 + HOUR,
    value: overrides.value === undefined ? 1000 : overrides.value,
  }
}

describe('windowOverlapRatio', () => {
  it('returns 1 for identical windows', () => {
    expect(windowOverlapRatio(T0, T0 + HOUR, T0, T0 + HOUR)).toBe(1)
  })

  it('returns 0 for disjoint windows', () => {
    expect(windowOverlapRatio(T0, T0 + HOUR, T0 + 2 * HOUR, T0 + 3 * HOUR)).toBe(0)
  })

  it('normalizes by the shorter window', () => {
    // a = [0,2h], b = [0,1h]; intersection 1h / shorter 1h = 1.
    expect(windowOverlapRatio(T0, T0 + 2 * HOUR, T0, T0 + HOUR)).toBe(1)
  })

  it('reports a partial overlap as the fraction of the shorter window', () => {
    // a = [0,1h], b = [0.5h,1.5h]; intersection 0.5h / shorter 1h = 0.5.
    const r = windowOverlapRatio(T0, T0 + HOUR, T0 + HOUR / 2, T0 + 1.5 * HOUR)
    expect(r).toBeCloseTo(0.5, 5)
  })

  it('treats an instantaneous sample inside a window as overlapping', () => {
    expect(windowOverlapRatio(T0 + HOUR / 2, T0 + HOUR / 2, T0, T0 + HOUR)).toBe(1)
  })
})

describe('valuesAreClose', () => {
  it('treats a null on either side as compatible (time-only match)', () => {
    expect(valuesAreClose(null, 1000, 1, 0.05)).toBe(true)
    expect(valuesAreClose(1000, undefined, 1, 0.05)).toBe(true)
  })

  it('matches within absolute tolerance', () => {
    expect(valuesAreClose(100, 100.5, 1, 0)).toBe(true)
    expect(valuesAreClose(100, 102, 1, 0)).toBe(false)
  })

  it('matches within relative tolerance for large values', () => {
    // 10000 vs 10400 = 4% drift, under the 5% relative tolerance.
    expect(valuesAreClose(10000, 10400, 1, 0.05)).toBe(true)
    // 10000 vs 11000 = 10% drift, over tolerance.
    expect(valuesAreClose(10000, 11000, 1, 0.05)).toBe(false)
  })

  it('rejects non-finite values', () => {
    expect(valuesAreClose(NaN, 1, 1, 0.05)).toBe(false)
    expect(valuesAreClose(Infinity, 1, 1, 0.05)).toBe(false)
  })
})

describe('dedupeHealthSamples — single source (behavior-preserving)', () => {
  it('keeps every record when only one source is present', () => {
    const items = [
      sample({ key: 'a', startAt: T0, endAt: T0 + HOUR }),
      sample({ key: 'b', startAt: T0 + 2 * HOUR, endAt: T0 + 3 * HOUR }),
      sample({ key: 'c', startAt: T0 + 4 * HOUR, endAt: T0 + 5 * HOUR }),
    ]
    const { kept, dropped } = dedupeHealthSamples(items)
    expect(kept).toHaveLength(3)
    expect(dropped).toHaveLength(0)
  })

  it('does NOT merge same-source overlapping windows of different sizes', () => {
    // Two records from the SAME source that overlap would still be collapsed by
    // the same-sample relation — but cross-source dedup is the documented job.
    // Here we assert that genuinely distinct, non-overlapping records survive.
    const items = [
      sample({ key: 'a', sourcePath: 'aggregator', value: 1000 }),
      sample({
        key: 'b',
        sourcePath: 'aggregator',
        startAt: T0 + 10 * HOUR,
        endAt: T0 + 11 * HOUR,
        value: 2000,
      }),
    ]
    const { kept } = dedupeHealthSamples(items)
    expect(kept).toHaveLength(2)
  })

  it('returns an empty result for no candidates', () => {
    const { kept, dropped, groups } = dedupeHealthSamples([])
    expect(kept).toHaveLength(0)
    expect(dropped).toHaveLength(0)
    expect(groups).toHaveLength(0)
  })
})

describe('dedupeHealthSamples — cross-source collapse', () => {
  it('collapses the same run from native + aggregator and prefers native', () => {
    const native = sample({
      key: 'native',
      sourcePath: 'health_connect',
      startAt: T0,
      endAt: T0 + HOUR,
      value: 1000,
    })
    const agg = sample({
      key: 'agg',
      sourcePath: 'aggregator',
      provider: 'garmin',
      startAt: T0 + 60 * 1000, // shifted 1 min
      endAt: T0 + HOUR + 60 * 1000,
      value: 1010, // within relative tolerance
    })
    const { kept, dropped, groups } = dedupeHealthSamples([native, agg])
    expect(kept).toHaveLength(1)
    expect(kept[0].key).toBe('native')
    expect(dropped.map((d) => d.key)).toEqual(['agg'])
    expect(groups[0].merged.map((m) => m.key)).toEqual(['agg'])
  })

  it('does NOT collapse when values diverge beyond tolerance', () => {
    const native = sample({ key: 'native', sourcePath: 'health_connect', value: 1000 })
    const agg = sample({
      key: 'agg',
      sourcePath: 'aggregator',
      value: 5000, // way off — a genuinely different measurement
    })
    const { kept } = dedupeHealthSamples([native, agg])
    expect(kept).toHaveLength(2)
  })

  it('does NOT collapse when windows do not overlap enough', () => {
    const a = sample({ key: 'a', sourcePath: 'health_connect', startAt: T0, endAt: T0 + HOUR })
    const b = sample({
      key: 'b',
      sourcePath: 'aggregator',
      startAt: T0 + 0.9 * HOUR, // only 10% overlap, under 0.8 threshold
      endAt: T0 + 1.9 * HOUR,
      value: 1000,
    })
    const { kept } = dedupeHealthSamples([a, b])
    expect(kept).toHaveLength(2)
  })

  it('does NOT collapse different metric types in the same window', () => {
    const steps = sample({ key: 'steps', metricType: 'steps', sourcePath: 'health_connect', value: 1000 })
    const sleep = sample({ key: 'sleep', metricType: 'sleep', sourcePath: 'aggregator', value: 1000 })
    const { kept } = dedupeHealthSamples([steps, sleep])
    expect(kept).toHaveLength(2)
  })

  it('prefers native over aggregator over file_upload across three sources', () => {
    const fileUpload = sample({ key: 'file', sourcePath: 'file_upload', value: 1000 })
    const agg = sample({ key: 'agg', sourcePath: 'aggregator', value: 1000 })
    const native = sample({ key: 'native', sourcePath: 'huawei_health_kit', value: 1000 })
    const { kept } = dedupeHealthSamples([fileUpload, agg, native])
    expect(kept).toHaveLength(1)
    expect(kept[0].key).toBe('native')
  })

  it('chains via single-link clustering (native ~ agg ~ upload) into one group', () => {
    // native and upload don't directly overlap enough, but the aggregator window
    // bridges them — all three are the same sample.
    const native = sample({ key: 'native', sourcePath: 'health_connect', startAt: T0, endAt: T0 + HOUR, value: 1000 })
    const agg = sample({
      key: 'agg',
      sourcePath: 'aggregator',
      startAt: T0 + 0.15 * HOUR,
      endAt: T0 + 1.15 * HOUR,
      value: 1000,
    })
    const upload = sample({
      key: 'upload',
      sourcePath: 'file_upload',
      startAt: T0 + 0.3 * HOUR,
      endAt: T0 + 1.3 * HOUR,
      value: 1000,
    })
    const { kept, groups } = dedupeHealthSamples([native, agg, upload])
    expect(kept).toHaveLength(1)
    expect(kept[0].key).toBe('native')
    expect(groups[0].merged.map((m) => m.key).sort()).toEqual(['agg', 'upload'])
  })

  it('falls back to the longer window when sources tie on priority', () => {
    const short = sample({
      key: 'short',
      sourcePath: 'aggregator',
      provider: 'fitbit',
      startAt: T0,
      endAt: T0 + HOUR,
      value: 1000,
    })
    const long = sample({
      key: 'long',
      sourcePath: 'aggregator',
      provider: 'garmin',
      startAt: T0,
      endAt: T0 + 1.2 * HOUR,
      value: 1000,
    })
    const { kept } = dedupeHealthSamples([short, long])
    expect(kept).toHaveLength(1)
    expect(kept[0].key).toBe('long')
  })

  it('is deterministic regardless of input order', () => {
    const native = sample({ key: 'native', sourcePath: 'health_connect', value: 1000 })
    const agg = sample({ key: 'agg', sourcePath: 'aggregator', value: 1000 })
    const a = dedupeHealthSamples([native, agg]).kept.map((k) => k.key)
    const b = dedupeHealthSamples([agg, native]).kept.map((k) => k.key)
    expect(a).toEqual(b)
    expect(a).toEqual(['native'])
  })

  it('treats unknown source paths as lowest priority', () => {
    const known = sample({ key: 'known', sourcePath: 'aggregator', value: 1000 })
    const unknown = sample({ key: 'unknown', sourcePath: 'some_future_source', value: 1000 })
    const { kept } = dedupeHealthSamples([unknown, known])
    expect(kept).toHaveLength(1)
    expect(kept[0].key).toBe('known')
  })

  it('matches on time alone when one side has no value', () => {
    const native = sample({ key: 'native', sourcePath: 'health_connect', value: null })
    const agg = sample({ key: 'agg', sourcePath: 'aggregator', value: 1000 })
    const { kept } = dedupeHealthSamples([native, agg])
    expect(kept).toHaveLength(1)
    expect(kept[0].key).toBe('native')
  })

  it('honors a custom source priority', () => {
    const native = sample({ key: 'native', sourcePath: 'health_connect', value: 1000 })
    const agg = sample({ key: 'agg', sourcePath: 'aggregator', value: 1000 })
    // Invert the default so the aggregator wins.
    const { kept } = dedupeHealthSamples([native, agg], {
      sourcePriority: ['aggregator', 'health_connect'],
    })
    expect(kept[0].key).toBe('agg')
  })

  it('accepts Date instances as well as epoch ms', () => {
    const native = sample({
      key: 'native',
      sourcePath: 'health_connect',
      startAt: new Date(T0),
      endAt: new Date(T0 + HOUR),
      value: 1000,
    })
    const agg = sample({
      key: 'agg',
      sourcePath: 'aggregator',
      startAt: new Date(T0),
      endAt: new Date(T0 + HOUR),
      value: 1000,
    })
    const { kept } = dedupeHealthSamples([native, agg])
    expect(kept).toHaveLength(1)
    expect(kept[0].key).toBe('native')
  })
})

describe('DEFAULT_SOURCE_PRIORITY', () => {
  it('ranks device-native paths ahead of aggregator and uploads', () => {
    expect(DEFAULT_SOURCE_PRIORITY.indexOf('health_connect')).toBeLessThan(
      DEFAULT_SOURCE_PRIORITY.indexOf('aggregator'),
    )
    expect(DEFAULT_SOURCE_PRIORITY.indexOf('aggregator')).toBeLessThan(
      DEFAULT_SOURCE_PRIORITY.indexOf('file_upload'),
    )
  })
})
