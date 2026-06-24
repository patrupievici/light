import { describe, it, expect } from 'vitest'
import { Prisma } from '@prisma/client'
import {
  CreateMeasurementSchema,
  MEASUREMENT_TYPES,
  MEASUREMENT_UNITS,
  serializeMeasurement,
} from './body-measurements'

const baseRow = {
  id: 'r1',
  type: 'chest',
  unit: 'cm',
  measuredAt: new Date('2026-06-13T12:00:00.000Z'),
  source: 'app',
  createdAt: new Date('2026-06-13T12:00:01.000Z'),
  updatedAt: new Date('2026-06-13T12:00:02.000Z'),
}

describe('serializeMeasurement — Decimal/Date normalization', () => {
  it('coerces a Prisma.Decimal value to a plain JS number', () => {
    const out = serializeMeasurement({ ...baseRow, valueNum: new Prisma.Decimal('98.500') })
    expect(out.valueNum).toBe(98.5)
    expect(typeof out.valueNum).toBe('number')
  })

  it('coerces a string Decimal (the release-only crash shape) to a number', () => {
    const out = serializeMeasurement({ ...baseRow, valueNum: '42.250' })
    expect(out.valueNum).toBe(42.25)
    expect(typeof out.valueNum).toBe('number')
  })

  it('emits ISO strings for all timestamps', () => {
    const out = serializeMeasurement({ ...baseRow, valueNum: 1 })
    expect(out.measuredAt).toBe('2026-06-13T12:00:00.000Z')
    expect(out.createdAt).toBe('2026-06-13T12:00:01.000Z')
    expect(out.updatedAt).toBe('2026-06-13T12:00:02.000Z')
  })

  it('passes source through, including null', () => {
    expect(serializeMeasurement({ ...baseRow, valueNum: 1, source: null }).source).toBeNull()
    expect(serializeMeasurement({ ...baseRow, valueNum: 1, source: 'health' }).source).toBe('health')
  })
})

describe('CreateMeasurementSchema — controlled vocabulary + range', () => {
  it('accepts a valid metric body-fat reading', () => {
    const parsed = CreateMeasurementSchema.safeParse({
      type: 'body_fat',
      valueNum: 18.4,
      unit: 'pct',
      measuredAt: '2026-06-13T12:00:00.000Z',
      source: 'app',
    })
    expect(parsed.success).toBe(true)
  })

  it('coerces a numeric string value', () => {
    const parsed = CreateMeasurementSchema.safeParse({ type: 'weight', valueNum: '82.5', unit: 'kg' })
    expect(parsed.success).toBe(true)
    if (parsed.success) expect(parsed.data.valueNum).toBe(82.5)
  })

  it('makes measuredAt + source optional', () => {
    const parsed = CreateMeasurementSchema.safeParse({ type: 'arm', valueNum: 38, unit: 'cm' })
    expect(parsed.success).toBe(true)
    if (parsed.success) {
      expect(parsed.data.measuredAt).toBeUndefined()
      expect(parsed.data.source).toBeUndefined()
    }
  })

  it('rejects an unknown type', () => {
    expect(CreateMeasurementSchema.safeParse({ type: 'wingspan', valueNum: 5, unit: 'cm' }).success).toBe(false)
  })

  it('rejects an unknown unit', () => {
    expect(CreateMeasurementSchema.safeParse({ type: 'weight', valueNum: 80, unit: 'stone' }).success).toBe(false)
  })

  it('rejects values outside 0..1000', () => {
    expect(CreateMeasurementSchema.safeParse({ type: 'weight', valueNum: -1, unit: 'kg' }).success).toBe(false)
    expect(CreateMeasurementSchema.safeParse({ type: 'weight', valueNum: 1001, unit: 'kg' }).success).toBe(false)
  })

  it('exposes the exact controlled sets the prompt requires', () => {
    expect([...MEASUREMENT_TYPES]).toEqual([
      'weight',
      'body_fat',
      'chest',
      'waist',
      'hips',
      'arm',
      'thigh',
      'calf',
      'shoulders',
      'neck',
    ])
    expect([...MEASUREMENT_UNITS]).toEqual(['kg', 'lb', 'cm', 'in', 'pct'])
  })
})
