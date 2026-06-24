import { z } from 'zod'
import { deepSeekChat } from './deepseek.service'
import { parseJsonFromModel } from '../lib/ai-helpers'

const MacroEstimateSchema = z.object({
  calories: z.coerce.number().nonnegative().optional(),
  proteinG: z.coerce.number().nonnegative(),
  carbsG: z.coerce.number().nonnegative(),
  fatG: z.coerce.number().nonnegative(),
})

const MealItemSchema = z.object({
  text: z.string().min(1).max(400),
  /** Explicit weighed/measured portion only (grams, ml, cups, pieces) — not vague "a bowl". */
  portion: z.string().min(1).max(280).optional(),
  /** Estimated macros for this item at the stated portion only. */
  macros: MacroEstimateSchema.optional(),
  proteinChoices: z.array(z.string().min(1).max(120)).max(24).optional(),
})

const MealSchema = z.object({
  meal: z.enum(['breakfast', 'lunch', 'dinner', 'snack']),
  items: z.array(MealItemSchema).min(1).max(16),
})

const DaySchema = z.object({
  day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  meals: z.array(MealSchema),
})

const AiWeekSchema = z.object({
  days: z.array(DaySchema),
})

/** Require metric portions + macros so we reject flaky first-pass JSON and retry. */
function rawDayHasPortionMacros(day: z.infer<typeof DaySchema>): boolean {
  for (const m of day.meals) {
    for (const it of m.items) {
      const portionOk = typeof it.portion === 'string' && it.portion.trim().length >= 3
      const mg = it.macros
      const macrosOk =
        mg != null &&
        typeof mg === 'object' &&
        Number.isFinite(mg.proteinG) &&
        Number.isFinite(mg.carbsG) &&
        Number.isFinite(mg.fatG)
      if (!portionOk || !macrosOk) return false
    }
  }
  return true
}

export type NormalizedMacroEstimate = {
  calories: number
  proteinG: number
  carbsG: number
  fatG: number
}

export type NormalizedMealItem = {
  text: string
  portion?: string
  macros?: NormalizedMacroEstimate
  proteinChoices?: string[]
  selectedProtein?: string
}

export type NormalizedMealPlan = {
  meals: Array<{ meal: string; items: NormalizedMealItem[] }>
}

function dedupePreserveOrder(arr: string[]): string[] {
  const seen = new Set<string>()
  const out: string[] = []
  for (const s of arr) {
    const t = s.trim()
    const k = t.toLowerCase()
    if (!t || seen.has(k)) continue
    seen.add(k)
    out.push(t)
  }
  return out
}

function clampMacroNonNeg(n: unknown): number {
  const x = typeof n === 'number' ? n : Number(n)
  if (!Number.isFinite(x) || x < 0) return 0
  return Math.round(x)
}

function normalizeMacroEstimate(raw: z.infer<typeof MacroEstimateSchema>): NormalizedMacroEstimate {
  const proteinG = clampMacroNonNeg(raw.proteinG)
  const carbsG = clampMacroNonNeg(raw.carbsG)
  const fatG = clampMacroNonNeg(raw.fatG)
  let calories =
    raw.calories != null && Number.isFinite(raw.calories) ? clampMacroNonNeg(raw.calories) : undefined
  if (calories === undefined || calories === 0) {
    calories = proteinG * 4 + carbsG * 4 + fatG * 9
  }
  return { calories, proteinG, carbsG, fatG }
}

function normalizeDayPlan(raw: z.infer<typeof DaySchema>): NormalizedMealPlan {
  const meals = [...raw.meals].sort((a, b) => {
    const order = ['breakfast', 'lunch', 'dinner', 'snack'] as const
    return order.indexOf(a.meal) - order.indexOf(b.meal)
  })
  return {
    meals: meals.map((m) => ({
      meal: m.meal,
      items: m.items.map((it) => {
        const choices = it.proteinChoices?.length
          ? dedupePreserveOrder(it.proteinChoices)
          : undefined
        const selected = choices?.length ? choices[0] : undefined
        const portionRaw = typeof it.portion === 'string' ? it.portion.trim() : ''
        const portion = portionRaw.length > 0 ? portionRaw.slice(0, 280) : undefined
        const macros = it.macros ? normalizeMacroEstimate(it.macros) : undefined
        return {
          text: it.text.trim(),
          portion,
          macros,
          proteinChoices: choices,
          selectedProtein: selected,
        }
      }),
    })),
  }
}

/**
 * Returns a map day (YYYY-MM-DD) → meal plan, or null if AI disabled / parse failed.
 */
export async function generateWeeklyMealPlanWithDeepSeek(params: {
  weekDays: string[]
  macroRows: Array<{
    day: string
    calories: number
    proteinG: number
    carbsG: number
    fatG: number
    waterMl: number
  }>
  goal: string
}): Promise<Map<string, NormalizedMealPlan> | null> {
  if (!process.env.DEEPSEEK_API_KEY) return null

  const targets = params.macroRows.map((r) => ({
    day: r.day,
    kcal: r.calories,
    proteinG: r.proteinG,
    carbsG: r.carbsG,
    fatG: r.fatG,
    waterMl: r.waterMl,
  }))

  const system = `CRITICAL: Every human-readable string you output inside the JSON (food lines, protein names) must be ENGLISH ONLY — no Romanian, no other languages.

You are a practical sports nutrition assistant for strength training.
Output ONLY a single JSON object (no markdown fences, no commentary).
The JSON must match this shape (every item should include portion + macros):
{"days":[{"day":"YYYY-MM-DD","meals":[{"meal":"breakfast","items":[{"text":"Oats with whey","portion":"60 g dry oats + 200 ml milk + 30 g whey isolate","macros":{"proteinG":35,"carbsG":48,"fatG":9,"calories":389}}, ...]}, ...]}]}

Hard rules:
- There must be exactly one entry per date in DAYS, same dates and order as given.
- Each day has exactly 4 meals with meal names: breakfast, lunch, dinner, snack (once each).
- "items" is an array of 2–8 realistic foods per meal.
- EVERY item MUST include:
  - "text": short English food name (no vague "some rice" — name the food).
  - "portion": ONE explicit metric line — grams (g) cooked or dry as appropriate, millilitres (ml), or count (e.g. "2 large eggs"). No vague portions like "a bowl" or "a handful".
  - "macros": estimated nutrition for THAT portion only: proteinG, carbsG, fatG as numbers (grams), and "calories" (kcal) optional — if omitted, it will be derived from macros.
- Across all items in a day, sum of item calories/macros should approximate that day's TARGETS row (within ~15%); adjust portions until close.
- For lunch and dinner, include ONE item that lists the lean protein serving and also include "proteinChoices": array of 6–8 interchangeable lean proteins as strings (first choice = matches the protein in "text"); each protein choice in proteinChoices should imply a similar portion size when swapped.
- For breakfast / snack include "proteinChoices" when the protein is swappable (eggs vs yogurt vs shake); otherwise omit proteinChoices.
- Language: every string in "text", "portion", and every entry in "proteinChoices" MUST be English only. Do not use Romanian or any non-English language, even when GOAL_LABEL is not English.
- Keep "text" and "portion" concise but unambiguous.

DAYS=${JSON.stringify(params.weekDays)}
TARGETS=${JSON.stringify(targets)}
GOAL_LABEL=${JSON.stringify(params.goal)}`

  const userBase = `Generate the JSON now for all days in DAYS. Targets per day are in TARGETS matched by day.

You MUST output portion + macros on every single item (see system rules). Approximate macros are fine; they must reflect the stated portion.

IMPORTANT: All food names, portion lines, and protein choices in English only — e.g. portion "200 g cooked chicken breast", never Romanian or mixed languages.`

  attemptLoop: for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const user =
        attempt === 0
          ? userBase
          : `${userBase}

Retry: previous JSON was rejected. EVERY item must include non-empty "portion" (use g, ml, or piece counts) and "macros" with numeric proteinG, carbsG, fatG for that exact portion. Output valid JSON only.`

      const out = await deepSeekChat(
        [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        {
          maxTokens: 5200,
          temperature: attempt === 0 ? 0.25 : 0.15,
        },
      )

      const parsed = parseJsonFromModel(out.text)
      if (!parsed || typeof parsed !== 'object') continue
      const validated = AiWeekSchema.safeParse(parsed)
      if (!validated.success) continue

      const expected = new Set(params.weekDays)
      const byDayRaw = new Map(validated.data.days.map((d) => [d.day, d]))
      for (const ymd of params.weekDays) {
        const d = byDayRaw.get(ymd)
        if (!d || !rawDayHasPortionMacros(d)) continue attemptLoop
      }

      const byDay = new Map<string, NormalizedMealPlan>()
      for (const d of validated.data.days) {
        if (!expected.has(d.day)) continue
        byDay.set(d.day, normalizeDayPlan(d))
      }
      if (byDay.size !== params.weekDays.length) continue
      return byDay
    } catch {
      // retry
    }
  }
  return null
}

export const PatchMealPlanSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  mealPlan: z.object({
    meals: z
      .array(
        z.object({
          meal: z.string().min(2).max(32),
          items: z
            .array(
              z.object({
                text: z.string().min(1).max(500),
                portion: z.string().max(280).optional(),
                macros: MacroEstimateSchema.optional(),
                proteinChoices: z.array(z.string().max(120)).max(24).optional(),
                selectedProtein: z.string().max(120).optional(),
              }),
            )
            .min(1)
            .max(20),
        }),
      )
      .min(1)
      .max(8),
  }),
})
