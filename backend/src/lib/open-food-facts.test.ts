import { describe, it, expect } from 'vitest'
import {
  macrosPer100gFromOffNutriments,
  mapOffProductToUsdaShaped,
  lookupOffByBarcode,
  searchOffByName,
} from './open-food-facts'

describe('macrosPer100gFromOffNutriments', () => {
  it('reads kcal directly when present', () => {
    const m = macrosPer100gFromOffNutriments({
      'energy-kcal_100g': 250,
      proteins_100g: 12,
      fat_100g: 8,
      carbohydrates_100g: 30,
    })
    expect(m).toEqual({ kcal: 250, proteinG: 12, fatG: 8, carbsG: 30 })
  })

  it('converts kJ to kcal when kcal is absent', () => {
    // 1046 kJ / 4.184 ≈ 250 kcal
    const m = macrosPer100gFromOffNutriments({ 'energy-kj_100g': 1046 })
    expect(m.kcal).toBeCloseTo(250, 0)
  })

  it('falls back to energy_100g (kJ) when neither kcal nor kj keys exist', () => {
    const m = macrosPer100gFromOffNutriments({ energy_100g: 2092 })
    expect(m.kcal).toBeCloseTo(500, 0)
  })

  it('parses comma-decimal strings and floors negatives to 0', () => {
    const m = macrosPer100gFromOffNutriments({
      'energy-kcal_100g': '180,5',
      proteins_100g: '-3',
      fat_100g: '4,2',
    })
    expect(m.kcal).toBeCloseTo(180.5)
    expect(m.proteinG).toBe(0)
    expect(m.fatG).toBeCloseTo(4.2)
  })

  it('handles null/undefined nutriments', () => {
    expect(macrosPer100gFromOffNutriments(null)).toEqual({ kcal: 0, proteinG: 0, fatG: 0, carbsG: 0 })
    expect(macrosPer100gFromOffNutriments(undefined)).toEqual({ kcal: 0, proteinG: 0, fatG: 0, carbsG: 0 })
  })
})

describe('mapOffProductToUsdaShaped', () => {
  it('maps a complete product to the USDA search row shape', () => {
    const out = mapOffProductToUsdaShaped({
      code: '737628064502',
      product_name: 'Thai Peanut Noodle',
      brands: 'Annie Chun',
      nutriments: {
        'energy-kcal_100g': 400,
        proteins_100g: 10,
        fat_100g: 12,
        carbohydrates_100g: 60,
      },
    })
    expect(out).not.toBeNull()
    expect(out!.fdcId).toBe('off:737628064502')
    expect(out!.description).toBe('Thai Peanut Noodle')
    expect(out!.dataType).toBe('Open Food Facts')
    expect(out!.brandOwner).toBe('Annie Chun')
    expect(out!.gtinUpc).toBe('737628064502')
    const byName = Object.fromEntries(out!.foodNutrients.map((n) => [n.nutrientName, n.value]))
    expect(byName.Energy).toBe(400)
    expect(byName.Protein).toBe(10)
    expect(byName['Total lipid (fat)']).toBe(12)
    expect(byName['Carbohydrate, by difference']).toBe(60)
  })

  it('falls back through product_name_en / generic_name', () => {
    const out = mapOffProductToUsdaShaped({
      generic_name: 'Generic Yogurt',
      nutriments: { 'energy-kcal_100g': 60, proteins_100g: 4 },
    })
    expect(out!.description).toBe('Generic Yogurt')
  })

  it('returns null for a product with no name', () => {
    expect(mapOffProductToUsdaShaped({ nutriments: { 'energy-kcal_100g': 100 } })).toBeNull()
  })

  it('returns null for a product with all-zero macros (placeholder)', () => {
    expect(mapOffProductToUsdaShaped({ product_name: 'Empty', nutriments: {} })).toBeNull()
  })

  it('derives a stable slug id when no barcode is present', () => {
    const out = mapOffProductToUsdaShaped({
      product_name: 'Plain Oats',
      nutriments: { 'energy-kcal_100g': 380, carbohydrates_100g: 67 },
    })
    expect(out!.fdcId).toBe('off:plain-oats')
    expect(out!.gtinUpc).toBeUndefined()
  })
})

describe('lookupOffByBarcode (injected fetch)', () => {
  it('maps a found product (status 1)', async () => {
    const fetchJson = async () => ({
      status: 1,
      product: {
        code: '111',
        product_name: 'Cola',
        nutriments: { 'energy-kcal_100g': 42, carbohydrates_100g: 10.6 },
      },
    })
    const out = await lookupOffByBarcode('00000111', { fetchJson })
    expect(out).toHaveLength(1)
    expect(out[0].description).toBe('Cola')
  })

  it('returns [] on a missing product (status 0)', async () => {
    const out = await lookupOffByBarcode('99999999', { fetchJson: async () => ({ status: 0 }) })
    expect(out).toEqual([])
  })

  it('returns [] for too-short barcodes without hitting the network', async () => {
    let called = false
    const out = await lookupOffByBarcode('123', {
      fetchJson: async () => {
        called = true
        return null
      },
    })
    expect(out).toEqual([])
    expect(called).toBe(false)
  })

  it('returns [] when fetch fails (null)', async () => {
    const out = await lookupOffByBarcode('00000111', { fetchJson: async () => null })
    expect(out).toEqual([])
  })
})

describe('searchOffByName (injected fetch)', () => {
  it('maps the products array, dedupes, and drops macro-less rows', async () => {
    const fetchJson = async () => ({
      products: [
        { code: '1', product_name: 'A', nutriments: { 'energy-kcal_100g': 100 } },
        { code: '1', product_name: 'A dup', nutriments: { 'energy-kcal_100g': 100 } }, // same id → deduped
        { product_name: 'No macros', nutriments: {} }, // dropped
        { code: '2', product_name: 'B', nutriments: { 'energy-kcal_100g': 200 } },
      ],
    })
    const out = await searchOffByName('snack', { fetchJson })
    expect(out.map((o) => o.fdcId)).toEqual(['off:1', 'off:2'])
  })

  it('routes an all-digit query to the barcode lookup', async () => {
    const out = await searchOffByName('00000111', {
      fetchJson: async (url: string) => {
        expect(url).toContain('/api/v2/product/00000111.json')
        return { status: 1, product: { code: '111', product_name: 'Barcode Food', nutriments: { 'energy-kcal_100g': 50 } } }
      },
    })
    expect(out).toHaveLength(1)
    expect(out[0].description).toBe('Barcode Food')
  })

  it('returns [] on empty query', async () => {
    expect(await searchOffByName('   ')).toEqual([])
  })

  it('returns [] when the response has no products array', async () => {
    expect(await searchOffByName('x', { fetchJson: async () => ({}) })).toEqual([])
    expect(await searchOffByName('x', { fetchJson: async () => null })).toEqual([])
  })

  it('honors the pageSize cap', async () => {
    const products = Array.from({ length: 10 }, (_, i) => ({
      code: String(i),
      product_name: `P${i}`,
      nutriments: { 'energy-kcal_100g': 100 + i },
    }))
    const out = await searchOffByName('many', { pageSize: 3, fetchJson: async () => ({ products }) })
    expect(out).toHaveLength(3)
  })
})
