import { describe, it, expect } from 'vitest'

import {
  resolveReconcileIntervalMs,
  createRunGuard,
} from './webhook-reconcile-cron.service'

const MIN = 60 * 1000
const DAY = 24 * 60 * 60 * 1000

describe('resolveReconcileIntervalMs', () => {
  it('defaults to 15 minutes when unset', () => {
    expect(resolveReconcileIntervalMs(undefined)).toBe(15 * MIN)
  })

  it('defaults on empty / blank / non-numeric input', () => {
    expect(resolveReconcileIntervalMs('')).toBe(15 * MIN)
    expect(resolveReconcileIntervalMs('   ')).toBe(15 * MIN)
    expect(resolveReconcileIntervalMs('abc')).toBe(15 * MIN)
  })

  it('honours a valid numeric override (with surrounding whitespace)', () => {
    expect(resolveReconcileIntervalMs('30')).toBe(30 * MIN)
    expect(resolveReconcileIntervalMs('  5 ')).toBe(5 * MIN)
  })

  it('falls back to default for zero / negative (no hot loop)', () => {
    // Non-positive values are treated as invalid → default (15 min), which is
    // already above the 1-minute floor, so the loop can never run hot.
    expect(resolveReconcileIntervalMs('0')).toBe(15 * MIN)
    expect(resolveReconcileIntervalMs('-10')).toBe(15 * MIN)
  })

  it('clamps an absurd value down to the one-day ceiling', () => {
    expect(resolveReconcileIntervalMs('999999')).toBe(DAY)
  })

  it('rounds fractional minutes to whole milliseconds', () => {
    expect(resolveReconcileIntervalMs('1.5')).toBe(Math.round(1.5 * MIN))
  })
})

describe('createRunGuard', () => {
  it('acquires when idle and reports running', () => {
    const g = createRunGuard()
    expect(g.isRunning).toBe(false)
    expect(g.tryAcquire()).toBe(true)
    expect(g.isRunning).toBe(true)
  })

  it('refuses a second acquire while busy (overlap skip)', () => {
    const g = createRunGuard()
    expect(g.tryAcquire()).toBe(true)
    expect(g.tryAcquire()).toBe(false)
    expect(g.tryAcquire()).toBe(false)
  })

  it('can be re-acquired after release', () => {
    const g = createRunGuard()
    g.tryAcquire()
    g.release()
    expect(g.isRunning).toBe(false)
    expect(g.tryAcquire()).toBe(true)
  })
})
