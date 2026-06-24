import { describe, it, expect } from 'vitest'

import {
  applyProgressionScheme,
  normalizeProgressionScheme,
  metPrescription,
  DOUBLE_REP_MIN,
  DOUBLE_REP_MAX,
  REPS_SUM_THRESHOLD,
  type SchemeInput,
} from './progression-schemes'
import { autoregulateLoad, type AutoregInput } from './progressive-overload'

function autoreg(overrides: Partial<AutoregInput> = {}): AutoregInput {
  return {
    level: overrides.level ?? 'beginner',
    isCompound: overrides.isCompound ?? true,
    lastWeight: overrides.lastWeight ?? 100,
    lastReps: overrides.lastReps ?? 8,
    lastRpe: overrides.lastRpe ?? null,
  }
}

function input(overrides: Partial<SchemeInput> = {}): SchemeInput {
  const ar = overrides.autoreg ?? autoreg()
  return {
    scheme: overrides.scheme ?? 'auto',
    level: overrides.level ?? ar.level,
    isCompound: overrides.isCompound ?? ar.isCompound,
    autoreg: ar,
    prescription: overrides.prescription ?? null,
    actual: overrides.actual ?? null,
  }
}

describe('normalizeProgressionScheme', () => {
  it('accepts the four known schemes', () => {
    expect(normalizeProgressionScheme('auto')).toBe('auto')
    expect(normalizeProgressionScheme('linear')).toBe('linear')
    expect(normalizeProgressionScheme('double')).toBe('double')
    expect(normalizeProgressionScheme('reps_sum')).toBe('reps_sum')
  })

  it('falls back to auto for unknown / null / non-string', () => {
    expect(normalizeProgressionScheme('nope')).toBe('auto')
    expect(normalizeProgressionScheme(null)).toBe('auto')
    expect(normalizeProgressionScheme(undefined)).toBe('auto')
    expect(normalizeProgressionScheme(42)).toBe('auto')
    expect(normalizeProgressionScheme('')).toBe('auto')
  })
})

describe('auto scheme reproduces autoregulateLoad EXACTLY', () => {
  // The non-negotiable invariant: progressionScheme=auto must equal today.
  const cases: AutoregInput[] = [
    autoreg({ lastRpe: null }), // linear fallback
    autoreg({ lastRpe: 9.7 }), // deload
    autoreg({ lastRpe: 8.5 }), // hold
    autoreg({ lastRpe: 5.5 }), // accelerate
    autoreg({ lastRpe: 7.0 }), // normal bump
    autoreg({ level: 'advanced', lastRpe: 5.0 }), // advanced, no bump
    autoreg({ level: 'intermediate', isCompound: false, lastRpe: 6.0, lastWeight: 40 }),
  ]
  for (const [i, ar] of cases.entries()) {
    it(`case ${i} matches autoregulateLoad output`, () => {
      const direct = autoregulateLoad(ar)
      const viaScheme = applyProgressionScheme(input({ scheme: 'auto', autoreg: ar }))
      expect(viaScheme.suggestedWeightKg).toBe(direct.suggestedWeightKg)
      expect(viaScheme.source).toBe(direct.source)
      expect(viaScheme.reason).toBe(direct.reason)
      expect(viaScheme.scheme).toBe('auto')
    })
  }

  it('auto ignores the adherence gate (carries deload/hold from RPE)', () => {
    // Even with a "missed" prescription, auto must behave exactly like autoreg.
    const ar = autoreg({ lastRpe: 5.0 })
    const r = applyProgressionScheme(
      input({
        scheme: 'auto',
        autoreg: ar,
        prescription: { targetReps: 12, targetRpe: 7, targetWeightKg: 100 },
        actual: { reps: 5, rpe: 5, weightKg: 100 }, // clearly missed
      }),
    )
    expect(r).toMatchObject({
      suggestedWeightKg: autoregulateLoad(ar).suggestedWeightKg,
      source: 'progression',
    })
  })
})

describe('metPrescription (adherence gate)', () => {
  it('permissive when prescription or actual is missing', () => {
    expect(metPrescription(null, { reps: 1, rpe: 10, weightKg: 0 })).toBe(true)
    expect(metPrescription({ targetReps: 8, targetRpe: 8, targetWeightKg: 100 }, null)).toBe(true)
  })

  it('met = hit target reps at/under target RPE', () => {
    const p = { targetReps: 8, targetRpe: 8, targetWeightKg: 100 }
    expect(metPrescription(p, { reps: 8, rpe: 8, weightKg: 100 })).toBe(true)
    expect(metPrescription(p, { reps: 10, rpe: 7, weightKg: 100 })).toBe(true)
  })

  it('missed when reps short', () => {
    const p = { targetReps: 8, targetRpe: 8, targetWeightKg: 100 }
    expect(metPrescription(p, { reps: 6, rpe: 7, weightKg: 100 })).toBe(false)
  })

  it('missed when RPE over the ceiling', () => {
    const p = { targetReps: 8, targetRpe: 8, targetWeightKg: 100 }
    expect(metPrescription(p, { reps: 8, rpe: 9, weightKg: 100 })).toBe(false)
  })

  it('RPE ignored when no ceiling prescribed or none logged', () => {
    expect(metPrescription({ targetReps: 8, targetRpe: null, targetWeightKg: 100 }, { reps: 8, rpe: 10, weightKg: 100 })).toBe(true)
    expect(metPrescription({ targetReps: 8, targetRpe: 8, targetWeightKg: 100 }, { reps: 8, rpe: null, weightKg: 100 })).toBe(true)
  })
})

describe('linear scheme', () => {
  it('adds the level bump when the prescription was met', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'linear',
        autoreg: autoreg({ level: 'beginner', isCompound: true, lastWeight: 100, lastReps: 8 }),
        prescription: { targetReps: 8, targetRpe: null, targetWeightKg: 100 },
        actual: { reps: 8, rpe: null, weightKg: 100 },
      }),
    )
    expect(r.suggestedWeightKg).toBe(102.5) // +2.5 beginner compound
    expect(r.source).toBe('progression')
  })

  it('holds when the prescription was missed (adherence gate)', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'linear',
        autoreg: autoreg({ level: 'beginner', isCompound: true, lastWeight: 100, lastReps: 5 }),
        prescription: { targetReps: 8, targetRpe: null, targetWeightKg: 100 },
        actual: { reps: 5, rpe: null, weightKg: 100 },
      }),
    )
    expect(r.suggestedWeightKg).toBe(100)
    expect(r.source).toBe('hold')
  })

  it('advanced holds load even on success', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'linear',
        autoreg: autoreg({ level: 'advanced', isCompound: true, lastWeight: 180, lastReps: 5 }),
        prescription: { targetReps: 5, targetRpe: null, targetWeightKg: 180 },
        actual: { reps: 5, rpe: null, weightKg: 180 },
      }),
    )
    expect(r.suggestedWeightKg).toBe(180)
    expect(r.source).toBe('progression')
  })
})

describe('double progression scheme', () => {
  it('climbs reps within the band at the same load', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'double',
        autoreg: autoreg({ lastWeight: 60, lastReps: 9 }),
        prescription: { targetReps: 9, targetRpe: null, targetWeightKg: 60 },
        actual: { reps: 9, rpe: null, weightKg: 60 },
      }),
    )
    expect(r.suggestedWeightKg).toBe(60)
    expect(r.suggestedReps).toBe(10) // 9 -> 10, toward the band max
    expect(r.source).toBe('progression')
  })

  it('adds load and resets reps once the top of the band is cleared', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'double',
        autoreg: autoreg({ level: 'beginner', isCompound: true, lastWeight: 60, lastReps: DOUBLE_REP_MAX }),
        prescription: { targetReps: DOUBLE_REP_MAX, targetRpe: null, targetWeightKg: 60 },
        actual: { reps: DOUBLE_REP_MAX, rpe: null, weightKg: 60 },
      }),
    )
    expect(r.suggestedWeightKg).toBe(62.5)
    expect(r.suggestedReps).toBe(DOUBLE_REP_MIN)
  })

  it('caps the climbing rep target at the band max', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'double',
        autoreg: autoreg({ lastWeight: 60, lastReps: DOUBLE_REP_MAX - 1 }),
        prescription: { targetReps: DOUBLE_REP_MAX - 1, targetRpe: null, targetWeightKg: 60 },
        actual: { reps: DOUBLE_REP_MAX - 1, rpe: null, weightKg: 60 },
      }),
    )
    expect(r.suggestedReps).toBe(DOUBLE_REP_MAX)
  })

  it('holds when the gate fails (missed reps)', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'double',
        autoreg: autoreg({ lastWeight: 60, lastReps: 6 }),
        prescription: { targetReps: 10, targetRpe: null, targetWeightKg: 60 },
        actual: { reps: 6, rpe: null, weightKg: 60 },
      }),
    )
    expect(r.source).toBe('hold')
    expect(r.suggestedWeightKg).toBe(60)
  })
})

describe('reps_sum scheme', () => {
  it('adds load once total working reps cross the threshold', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'reps_sum',
        autoreg: autoreg({ level: 'beginner', isCompound: true, lastWeight: 100, lastReps: 9 }),
        prescription: { targetReps: 8, targetRpe: null, targetWeightKg: 100 },
        actual: { reps: 9, rpe: null, weightKg: 100, totalWorkReps: REPS_SUM_THRESHOLD + 2 },
      }),
    )
    expect(r.suggestedWeightKg).toBe(102.5)
    expect(r.source).toBe('progression')
  })

  it('holds when total reps below the threshold even if per-set target met', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'reps_sum',
        autoreg: autoreg({ lastWeight: 100, lastReps: 8 }),
        prescription: { targetReps: 8, targetRpe: null, targetWeightKg: 100 },
        actual: { reps: 8, rpe: null, weightKg: 100, totalWorkReps: REPS_SUM_THRESHOLD - 5 },
      }),
    )
    expect(r.suggestedWeightKg).toBe(100)
    expect(r.source).toBe('hold')
  })

  it('falls back to single-set reps when totalWorkReps absent', () => {
    const r = applyProgressionScheme(
      input({
        scheme: 'reps_sum',
        autoreg: autoreg({ lastWeight: 100, lastReps: 8 }),
        prescription: { targetReps: 8, targetRpe: null, targetWeightKg: 100 },
        actual: { reps: 8, rpe: null, weightKg: 100 },
      }),
    )
    // 8 < threshold → hold
    expect(r.source).toBe('hold')
  })
})
