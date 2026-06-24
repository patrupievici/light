/**
 * Open Food Facts (OFF) client — a fallback food source behind the existing
 * USDA-shaped food-resolution abstraction.
 *
 * USDA FoodData Central is the primary source, but it misses a large slice of
 * non-US branded/packaged products and many barcodes. Open Food Facts is an
 * open, crowd-sourced database (ODbL) that fills those gaps. This module is a
 * clean-room implementation: it speaks the documented OFF v2 product endpoint
 * and the legacy CGI search endpoint, and maps results into the SAME shape the
 * app already consumes from the USDA proxy (`{ foods: [...] }`, each food with
 * `fdcId`, `description`, `dataType`, `foodNutrients[]` per 100 g). That lets
 * the app's existing parser read OFF hits with zero client changes.
 *
 * All network paths are graceful: any network failure, non-200, malformed JSON,
 * or empty result resolves to an empty list (never throws to the caller). The
 * route treats this strictly as a fallback — it is only consulted when USDA
 * returns nothing useful.
 *
 * Sources (public API docs only — no source code studied/copied):
 *   - https://world.openfoodfacts.org/data
 *   - https://openfoodfacts.github.io/openfoodfacts-server/api/
 */

/** A USDA-search-shaped food row (matches what the app's USDA parser reads). */
export interface UsdaShapedFood {
  fdcId: string
  description: string
  dataType: string
  brandOwner?: string
  gtinUpc?: string
  foodNutrients: Array<{ nutrientName: string; unitName: string; value: number }>
}

/** The minimal slice of an OFF product we read. */
export interface OffProduct {
  code?: unknown
  product_name?: unknown
  product_name_en?: unknown
  generic_name?: unknown
  brands?: unknown
  image_url?: unknown
  image_front_url?: unknown
  nutriments?: Record<string, unknown> | null
}

const OFF_BASE = 'https://world.openfoodfacts.org'

// OFF asks all API clients to send a descriptive UA so abusive/anonymous
// traffic can be told apart from real apps. (Documented requirement.)
const OFF_USER_AGENT = 'Zvelt/1.0 (fitness app; nutrition fallback)'

const OFF_TIMEOUT_MS = 6000

function asString(v: unknown): string | undefined {
  if (typeof v === 'string') {
    const t = v.trim()
    return t.length > 0 ? t : undefined
  }
  if (typeof v === 'number' && Number.isFinite(v)) return String(v)
  return undefined
}

function asNumber(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v
  if (typeof v === 'string') {
    // OFF occasionally stores numbers as strings with a comma decimal.
    const n = Number.parseFloat(v.replace(',', '.'))
    return Number.isFinite(n) ? n : 0
  }
  return 0
}

/**
 * Per-100 g macros from an OFF `nutriments` object. OFF keys are well-defined:
 * `<nutrient>_100g`. Energy is preferred as kcal; if only kJ is present we
 * convert (1 kcal = 4.184 kJ). Negative/garbage values are floored to 0.
 */
export function macrosPer100gFromOffNutriments(
  nutriments: Record<string, unknown> | null | undefined,
): { kcal: number; proteinG: number; fatG: number; carbsG: number } {
  const n = nutriments ?? {}
  let kcal = asNumber(n['energy-kcal_100g'])
  if (kcal <= 0) {
    const kj = asNumber(n['energy-kj_100g'])
    if (kj > 0) kcal = kj / 4.184
    else {
      // `energy_100g` is in kJ when `energy-kcal_100g` is absent.
      const energy = asNumber(n['energy_100g'])
      if (energy > 0) kcal = energy / 4.184
    }
  }
  const proteinG = asNumber(n['proteins_100g'])
  const fatG = asNumber(n['fat_100g'])
  const carbsG = asNumber(n['carbohydrates_100g'])
  const clamp = (x: number) => (x > 0 ? x : 0)
  return { kcal: clamp(kcal), proteinG: clamp(proteinG), fatG: clamp(fatG), carbsG: clamp(carbsG) }
}

function offDisplayName(p: OffProduct): string | undefined {
  return asString(p.product_name) ?? asString(p.product_name_en) ?? asString(p.generic_name)
}

/**
 * Map a single OFF product into the USDA-search row shape the app already
 * parses. Returns `null` when the product has no name or no usable macros (so
 * empty/placeholder OFF entries never pollute the result list).
 */
export function mapOffProductToUsdaShaped(p: OffProduct): UsdaShapedFood | null {
  const name = offDisplayName(p)
  if (!name) return null
  const macros = macrosPer100gFromOffNutriments(p.nutriments)
  if (macros.kcal <= 0 && macros.proteinG <= 0 && macros.fatG <= 0 && macros.carbsG <= 0) {
    return null
  }
  const code = asString(p.code)
  const brand = asString(p.brands)
  return {
    // Namespaced id so it never collides with a numeric USDA fdcId. The app
    // builds `usda_fdc_<fdcId>` for its FoodItem id; an `off:` prefix keeps OFF
    // hits uniquely identifiable while flowing through the same code path.
    fdcId: code ? `off:${code}` : `off:${name.toLowerCase().replace(/\s+/g, '-').slice(0, 48)}`,
    description: name,
    dataType: 'Open Food Facts',
    ...(brand ? { brandOwner: brand } : {}),
    ...(code ? { gtinUpc: code } : {}),
    foodNutrients: [
      { nutrientName: 'Energy', unitName: 'kcal', value: macros.kcal },
      { nutrientName: 'Protein', unitName: 'g', value: macros.proteinG },
      { nutrientName: 'Total lipid (fat)', unitName: 'g', value: macros.fatG },
      { nutrientName: 'Carbohydrate, by difference', unitName: 'g', value: macros.carbsG },
    ],
  }
}

function isDigits(s: string): boolean {
  return /^\d+$/.test(s)
}

async function offFetchJson(url: string): Promise<unknown | null> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), OFF_TIMEOUT_MS)
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': OFF_USER_AGENT, Accept: 'application/json' },
      signal: controller.signal,
    })
    if (!res.ok) return null
    const text = await res.text()
    try {
      return JSON.parse(text) as unknown
    } catch {
      return null
    }
  } catch {
    // Network failure / timeout / abort — fallback stays silent by design.
    return null
  } finally {
    clearTimeout(timer)
  }
}

/**
 * Look up a single packaged product by barcode (GTIN/UPC/EAN). Returns at most
 * one USDA-shaped food, or `[]` on miss/failure.
 */
export async function lookupOffByBarcode(
  barcode: string,
  deps: { fetchJson?: (url: string) => Promise<unknown | null> } = {},
): Promise<UsdaShapedFood[]> {
  const digits = (barcode ?? '').replace(/\D/g, '')
  if (digits.length < 8) return []
  const fetchJson = deps.fetchJson ?? offFetchJson
  const url = `${OFF_BASE}/api/v2/product/${digits}.json?fields=code,product_name,product_name_en,generic_name,brands,image_url,image_front_url,nutriments`
  const json = (await fetchJson(url)) as { status?: unknown; product?: OffProduct } | null
  if (!json || typeof json !== 'object') return []
  // OFF returns status: 1 when found, 0 when missing.
  if (Number(json.status) !== 1 || !json.product) return []
  const mapped = mapOffProductToUsdaShaped(json.product)
  return mapped ? [mapped] : []
}

/**
 * Search OFF by free-text name. Returns up to `pageSize` USDA-shaped foods, or
 * `[]` on miss/failure. If the query is all digits it is treated as a barcode.
 */
export async function searchOffByName(
  query: string,
  opts: { pageSize?: number; fetchJson?: (url: string) => Promise<unknown | null> } = {},
): Promise<UsdaShapedFood[]> {
  const q = (query ?? '').trim()
  if (q.length === 0) return []
  if (isDigits(q)) return lookupOffByBarcode(q, { fetchJson: opts.fetchJson })

  const fetchJson = opts.fetchJson ?? offFetchJson
  const pageSize = Math.max(1, Math.min(50, opts.pageSize ?? 25))
  const params = new URLSearchParams({
    search_terms: q,
    search_simple: '1',
    action: 'process',
    json: '1',
    page_size: String(pageSize),
    fields: 'code,product_name,product_name_en,generic_name,brands,image_url,image_front_url,nutriments',
  })
  const url = `${OFF_BASE}/cgi/search.pl?${params.toString()}`
  const json = (await fetchJson(url)) as { products?: unknown } | null
  if (!json || typeof json !== 'object' || !Array.isArray(json.products)) return []

  const out: UsdaShapedFood[] = []
  const seen = new Set<string>()
  for (const raw of json.products as unknown[]) {
    if (!raw || typeof raw !== 'object') continue
    const mapped = mapOffProductToUsdaShaped(raw as OffProduct)
    if (!mapped) continue
    if (seen.has(mapped.fdcId)) continue
    seen.add(mapped.fdcId)
    out.push(mapped)
    if (out.length >= pageSize) break
  }
  return out
}
