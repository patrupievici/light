import { describe, it, expect } from 'vitest'

import {
  computePlateStack,
  parsePlateInventory,
  DEFAULT_BARBELL_KG,
} from './plate-calculator'

describe('parsePlateInventory', () => {
  it('parses a flat kg array (each entry = one pair)', () => {
    expect(parsePlateInventory([20, 20, 10, 5])).toEqual([
      { kg: 20, pairs: 2 },
      { kg: 10, pairs: 1 },
      { kg: 5, pairs: 1 },
    ])
  })

  it('parses { kg, pairs } objects', () => {
    expect(parsePlateInventory([{ kg: 25, pairs: 3 }, { kg: 10, pairs: 2 }])).toEqual([
      { kg: 25, pairs: 3 },
      { kg: 10, pairs: 2 },
    ])
  })

  it('drops invalid / non-positive entries', () => {
    expect(parsePlateInventory([0, -5, 'x', { kg: 'no' }, { kg: 20, pairs: 0 }, 15])).toEqual([
      { kg: 15, pairs: 1 },
    ])
  })

  it('returns null for non-arrays and empty/all-invalid input', () => {
    expect(parsePlateInventory(null)).toBeNull()
    expect(parsePlateInventory({})).toBeNull()
    expect(parsePlateInventory([])).toBeNull()
    expect(parsePlateInventory([0, -1])).toBeNull()
  })

  it('sorts largest plate first', () => {
    const parsed = parsePlateInventory([5, 25, 10])
    expect(parsed?.map((p) => p.kg)).toEqual([25, 10, 5])
  })
})

describe('computePlateStack — unlimited standard set', () => {
  it('builds an exact 100kg from a 20kg bar', () => {
    const r = computePlateStack({ targetKg: 100, barbellKg: 20 })
    expect(r.achievableKg).toBe(100)
    expect(r.exact).toBe(true)
    expect(r.deltaKg).toBe(0)
    // per side = 40kg = 25 + 15  (greedy largest-first)
    expect(r.perSideKg).toEqual([25, 15])
  })

  it('defaults the bar to DEFAULT_BARBELL_KG when unset', () => {
    const r = computePlateStack({ targetKg: DEFAULT_BARBELL_KG })
    expect(r.barbellKg).toBe(DEFAULT_BARBELL_KG)
    expect(r.perSideKg).toEqual([])
    expect(r.exact).toBe(true)
  })

  it('clamps a sub-bar target to the bar', () => {
    const r = computePlateStack({ targetKg: 10, barbellKg: 20 })
    expect(r.achievableKg).toBe(20)
    expect(r.perSideKg).toEqual([])
    expect(r.deltaKg).toBe(10) // achievable(20) - target(10)
    expect(r.exact).toBe(false)
  })

  it('rounds DOWN to the nearest achievable when target is not makeable', () => {
    // 20 bar, target 103 → per side 41.5 → 25+15+1.25 = 41.25 → total 102.5
    const r = computePlateStack({ targetKg: 103, barbellKg: 20 })
    expect(r.achievableKg).toBe(102.5)
    expect(r.exact).toBe(false)
    expect(r.deltaKg).toBeLessThan(0) // under the requested target
  })
})

describe('computePlateStack — bounded inventory', () => {
  it('never asks for a plate the user does not own', () => {
    // Only one pair of 20s and one pair of 10s. Target 100 (per side 40) cannot
    // be made exactly → 20 + 10 = 30 per side → 80 total.
    const r = computePlateStack({
      targetKg: 100,
      barbellKg: 20,
      inventory: [
        { kg: 20, pairs: 1 },
        { kg: 10, pairs: 1 },
      ],
    })
    expect(r.perSideKg).toEqual([20, 10])
    expect(r.achievableKg).toBe(80)
    expect(r.exact).toBe(false)
  })

  it('uses multiple pairs of the same plate when owned', () => {
    const r = computePlateStack({
      targetKg: 120,
      barbellKg: 20,
      inventory: [{ kg: 25, pairs: 3 }],
    })
    // per side target 50 → two 25s = 50 → exact 120
    expect(r.perSideKg).toEqual([25, 25])
    expect(r.achievableKg).toBe(120)
    expect(r.exact).toBe(true)
  })

  it('falls back to the unlimited standard set when inventory is empty', () => {
    const r = computePlateStack({ targetKg: 60, barbellKg: 20, inventory: [] })
    expect(r.achievableKg).toBe(60)
    expect(r.exact).toBe(true)
  })

  it('honors a custom bar weight', () => {
    const r = computePlateStack({ targetKg: 75, barbellKg: 15 })
    // per side 30 = 25 + 5
    expect(r.perSideKg).toEqual([25, 5])
    expect(r.achievableKg).toBe(75)
  })

  it('never overshoots the target', () => {
    const r = computePlateStack({
      targetKg: 95,
      barbellKg: 20,
      inventory: [{ kg: 25, pairs: 2 }],
    })
    expect(r.achievableKg).toBeLessThanOrEqual(95)
  })
})
