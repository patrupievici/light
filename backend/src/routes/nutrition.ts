import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { Prisma } from '@prisma/client'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import {
  generateWeeklyMealPlanWithDeepSeek,
  PatchMealPlanSchema,
  type NormalizedMealPlan,
} from '../services/meal-plan-ai.service'
import { computeNutritionDayXp } from '../services/nutrition-xp.service'
import { resolveUserXpContext } from '../services/cardio-xp.service'
import { gameXpPayload } from '../services/gym-xp.service'
import { searchOffByName, type UsdaShapedFood } from '../lib/open-food-facts'

const DateParam = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)

const PutDaySchema = z.object({
  date: DateParam,
  entries: z.array(z.unknown()).default([]),
  waterMl: z.coerce.number().int().min(0).max(100_000).default(0),
  weightKg: z.coerce.number().min(20).max(400).optional().nullable(),
})

const GeneratePlanSchema = z.object({
  tzOffset: z.coerce.number().int().min(-840).max(840).optional().default(0),
  force: z.boolean().optional().default(false),
})

const WeekQuerySchema = z.object({
  weekStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  tzOffset: z.coerce.number().int().min(-840).max(840).optional().default(0),
})

function ymdFromUtcWithOffset(d: Date, offsetMin: number): string {
  const x = new Date(d.getTime() + offsetMin * 60 * 1000)
  const y = x.getUTCFullYear()
  const m = String(x.getUTCMonth() + 1).padStart(2, '0')
  const day = String(x.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function dateFromYmdUtc(ymd: string): Date {
  const [y, m, d] = ymd.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d, 0, 0, 0, 0))
}

function mondayOfWeek(ymd: string): string {
  const d = dateFromYmdUtc(ymd)
  const wd = d.getUTCDay()
  const shift = wd === 0 ? 6 : wd - 1
  d.setUTCDate(d.getUTCDate() - shift)
  return ymdFromUtcWithOffset(d, 0)
}

function buildWeekDays(weekStart: string): string[] {
  const start = dateFromYmdUtc(weekStart)
  const out: string[] = []
  for (let i = 0; i < 7; i++) {
    const d = new Date(start.getTime())
    d.setUTCDate(start.getUTCDate() + i)
    out.push(ymdFromUtcWithOffset(d, 0))
  }
  return out
}

function payloadFromRow(payload: unknown) {
  const p = (payload ?? {}) as Record<string, unknown>
  return {
    entries: Array.isArray(p.entries) ? p.entries : [],
    waterMl: typeof p.waterMl === 'number' ? p.waterMl : 0,
    weightKg: p.weightKg == null || p.weightKg === undefined ? null : Number(p.weightKg),
  }
}

const USDA_FDC_BASE = 'https://api.nal.usda.gov/fdc/v1'

const UsdaProxySearchSchema = z.object({
  query: z.string().min(1).max(200),
  pageSize: z.coerce.number().int().min(1).max(50).optional(),
  pageNumber: z.coerce.number().int().min(1).optional(),
  dataType: z.array(z.string()).optional(),
})

function usdaApiKey(): string | null {
  const k = process.env.USDA_API_KEY?.trim()
  return k && k.length > 0 ? k : null
}

/**
 * Count usable USDA hits in a parsed search response. A "usable" hit is one the
 * app can actually log — it has a description AND at least one positive macro.
 * Branded rows with all-zero nutrients (placeholder entries) don't count, so we
 * still reach for the Open Food Facts fallback when USDA returns only noise.
 */
function usableUsdaFoodCount(parsed: unknown): number {
  if (!parsed || typeof parsed !== 'object') return 0
  const foods = (parsed as { foods?: unknown }).foods
  if (!Array.isArray(foods)) return 0
  let n = 0
  for (const f of foods) {
    if (!f || typeof f !== 'object') continue
    const desc = (f as { description?: unknown }).description
    if (typeof desc !== 'string' || desc.trim().length === 0) continue
    const nutrients = (f as { foodNutrients?: unknown }).foodNutrients
    const hasMacro =
      Array.isArray(nutrients) &&
      nutrients.some((x) => x && typeof x === 'object' && Number((x as { value?: unknown }).value) > 0)
    if (hasMacro) n++
  }
  return n
}

/**
 * Minimum usable USDA hits before we SKIP the Open Food Facts merge. Below this,
 * OFF is queried and its rows appended — this is the EU-coverage fix: a search
 * like "Nutella" often returns one generic USDA spread entry (so the old
 * `> 0`-only fallback hid OFF entirely), while OFF carries the actual branded
 * EU product. USDA rows still come first (clean generic macros); OFF fills the
 * branded/European long tail. When USDA already returns a rich page we skip OFF
 * to avoid the extra call.
 */
const MIN_USDA_HITS_BEFORE_OFF = 8

/**
 * Splice Open Food Facts rows into a USDA-shaped search response. OFF rows are
 * appended AFTER any USDA rows so clean generic macros stay on top, but OFF is
 * now merged whenever USDA is thin (< MIN_USDA_HITS_BEFORE_OFF) — not only when
 * USDA is empty — so European branded products are findable. On any OFF failure
 * the original USDA response is returned unchanged.
 */
async function withOffFallback(
  parsed: unknown,
  query: string,
  log: FastifyInstance['log'],
): Promise<unknown> {
  if (usableUsdaFoodCount(parsed) >= MIN_USDA_HITS_BEFORE_OFF) return parsed
  let offFoods: UsdaShapedFood[] = []
  try {
    offFoods = await searchOffByName(query, { pageSize: 25 })
  } catch (e: unknown) {
    log.warn({ err: e instanceof Error ? e.message : String(e) }, 'OFF fallback failed')
    return parsed
  }
  if (offFoods.length === 0) return parsed
  const base =
    parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : {}
  const existing = Array.isArray(base.foods) ? base.foods : []
  return { ...base, foods: [...existing, ...offFoods] }
}

// ── BMI / TDEE goal-suggestion math (pure, transparent) ──────────────────────
// Mifflin-St Jeor is the most accurate published BMR equation for the general
// population. We expose every input + intermediate so the suggestion endpoint
// can return a fully "explainable" payload (per the explainability principle) —
// nothing is a black box and nothing is auto-applied.

export type GoalKey =
  | 'fat_loss'
  | 'maintenance'
  | 'hypertrophy'
  | 'strength'
  | 'calisthenics'
  | 'explosive_power'

export type ActivityKey = 'sedentary' | 'light' | 'moderate' | 'active' | 'very_active'

/** Standard activity multipliers applied to BMR to get TDEE. */
export const ACTIVITY_MULTIPLIERS: Record<ActivityKey, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
  very_active: 1.9,
}

/** Mifflin-St Jeor BMR (kcal/day). `sex` defaults to a neutral average. */
export function mifflinStJeorBmr(args: {
  weightKg: number
  heightCm: number
  ageYears: number
  sex?: string | null
}): number {
  const base = 10 * args.weightKg + 6.25 * args.heightCm - 5 * args.ageYears
  const s = (args.sex ?? '').toLowerCase()
  // male +5, female -161; for unknown/other use the midpoint (-78) so neither
  // sex is silently assumed.
  const sexConstant = s === 'male' ? 5 : s === 'female' ? -161 : -78
  return base + sexConstant
}

/** kcal delta applied to TDEE per goal (caloric strategy, not a hard rule). */
export function goalCalorieDelta(goal: GoalKey, tdee: number): number {
  switch (goal) {
    case 'fat_loss':
      // ~20% deficit, but never deeper than 750 kcal/day.
      return -Math.min(750, Math.round(tdee * 0.2))
    case 'hypertrophy':
      return 250
    case 'strength':
      return 150
    case 'explosive_power':
      return 100
    case 'calisthenics':
    case 'maintenance':
    default:
      return 0
  }
}

/**
 * Full transparent suggestion: BMR → TDEE → goal-adjusted calories → macro
 * split. Protein is body-weight driven (1.8 g/kg, a widely-cited strength
 * target); fat is 25% of calories; carbs fill the remainder. All rounded to
 * friendly integers. Returns the breakdown so the client can render the "why".
 */
export function computeNutritionSuggestion(args: {
  weightKg: number
  heightCm: number
  ageYears: number
  sex?: string | null
  activity: ActivityKey
  goal: GoalKey
}): {
  bmr: number
  tdee: number
  activityMultiplier: number
  calorieDelta: number
  calories: number
  proteinG: number
  fatG: number
  carbsG: number
  bmi: number | null
} {
  const bmr = Math.round(mifflinStJeorBmr(args))
  const activityMultiplier = ACTIVITY_MULTIPLIERS[args.activity]
  const tdee = Math.round(bmr * activityMultiplier)
  const calorieDelta = goalCalorieDelta(args.goal, tdee)
  // Floor at 1200 kcal — never suggest a clinically unsafe deficit.
  const calories = Math.max(1200, tdee + calorieDelta)

  const proteinG = Math.round(args.weightKg * 1.8)
  const fatG = Math.round((calories * 0.25) / 9)
  const carbsKcal = Math.max(0, calories - proteinG * 4 - fatG * 9)
  const carbsG = Math.round(carbsKcal / 4)

  const heightM = args.heightCm / 100
  const bmi = heightM > 0 ? Math.round((args.weightKg / (heightM * heightM)) * 10) / 10 : null

  return { bmr, tdee, activityMultiplier, calorieDelta, calories, proteinG, fatG, carbsG, bmi }
}

const VALID_GOALS: readonly GoalKey[] = [
  'fat_loss',
  'maintenance',
  'hypertrophy',
  'strength',
  'calisthenics',
  'explosive_power',
]

const SuggestionQuerySchema = z.object({
  // Optional overrides; omitted fields fall back to the user's stored profile.
  weightKg: z.coerce.number().min(30).max(250).optional(),
  heightCm: z.coerce.number().min(100).max(250).optional(),
  ageYears: z.coerce.number().int().min(13).max(100).optional(),
  sex: z.enum(['male', 'female', 'other']).optional(),
  activity: z
    .enum(['sedentary', 'light', 'moderate', 'active', 'very_active'])
    .optional()
    .default('moderate'),
  goal: z.enum(VALID_GOALS as unknown as [GoalKey, ...GoalKey[]]).optional(),
})

// ── Saved meal templates ─────────────────────────────────────────────────────
const TemplateItemSchema = z.object({
  name: z.string().min(1).max(120),
  grams: z.coerce.number().min(0).max(5000).optional(),
  calories: z.coerce.number().min(0).max(20_000).optional(),
  proteinG: z.coerce.number().min(0).max(2000).optional(),
  carbsG: z.coerce.number().min(0).max(2000).optional(),
  fatG: z.coerce.number().min(0).max(2000).optional(),
  meal: z.string().max(32).optional(),
})

const CreateTemplateSchema = z.object({
  name: z.string().trim().min(1).max(80),
  items: z.array(TemplateItemSchema).min(1).max(40),
})

const ApplyTemplateSchema = z.object({
  date: DateParam,
  meal: z.string().max(32).optional(),
})

export async function nutritionRoutes(app: FastifyInstance) {
  // POST /v1/nutrition/usda/foods/search — proxy (cheia USDA doar pe server).
  app.post('/usda/foods/search', { preHandler: authenticate }, async (request, reply) => {
    const key = usdaApiKey()
    if (!key) {
      return reply.code(503).send({
        error: 'USDA_NOT_CONFIGURED',
        message: 'Set USDA_API_KEY in server environment (.env).',
        requestId: request.id,
      })
    }
    const parsed = UsdaProxySearchSchema.safeParse(request.body ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Expected JSON { query, pageSize?, pageNumber?, dataType? }',
        requestId: request.id,
      })
    }
    const body = {
      query: parsed.data.query,
      pageSize: parsed.data.pageSize ?? 30,
      pageNumber: parsed.data.pageNumber ?? 1,
      dataType: parsed.data.dataType ?? ['Foundation', 'SR Legacy', 'Survey (FNDDS)'],
    }
    const url = `${USDA_FDC_BASE}/foods/search?api_key=${encodeURIComponent(key)}`
    let upstream: Response
    try {
      upstream = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify(body),
      })
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e)
      app.log.warn({ err: msg }, 'USDA proxy POST failed')
      // USDA itself is unreachable — try Open Food Facts before giving up so a
      // single-provider outage doesn't black out food search entirely.
      const fb = await withOffFallback({ foods: [] }, parsed.data.query, app.log)
      if (usableUsdaFoodCount(fb) > 0) return reply.send(fb)
      return reply.code(502).send({
        error: 'USDA_UPSTREAM',
        message: msg,
        requestId: request.id,
      })
    }
    const text = await upstream.text()
    if (!upstream.ok) {
      const code =
        upstream.status === 429 ? 429 : upstream.status >= 500 ? 502 : upstream.status
      return reply.code(code).send({
        error: 'USDA_UPSTREAM',
        message: text.slice(0, 500),
        requestId: request.id,
      })
    }
    let parsedBody: unknown
    try {
      parsedBody = JSON.parse(text) as unknown
    } catch {
      return reply.code(502).send({
        error: 'USDA_BAD_RESPONSE',
        message: 'Invalid JSON from USDA',
        requestId: request.id,
      })
    }
    // Behavior-preserving when USDA already has usable hits; only reaches for the
    // OFF fallback when USDA missed (or returned all-zero noise).
    return reply.send(await withOffFallback(parsedBody, parsed.data.query, app.log))
  })

  // GET /v1/nutrition/usda/food/:fdcId — proxy detail (barcode flow).
  app.get<{ Params: { fdcId: string } }>('/usda/food/:fdcId', { preHandler: authenticate }, async (request, reply) => {
    const key = usdaApiKey()
    if (!key) {
      return reply.code(503).send({
        error: 'USDA_NOT_CONFIGURED',
        message: 'Set USDA_API_KEY in server environment (.env).',
        requestId: request.id,
      })
    }
    const idParsed = z.coerce.number().int().positive().safeParse(request.params.fdcId)
    if (!idParsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Invalid fdcId',
        requestId: request.id,
      })
    }
    const fdcId = idParsed.data
    const url = `${USDA_FDC_BASE}/food/${fdcId}?api_key=${encodeURIComponent(key)}`
    let upstream: Response
    try {
      upstream = await fetch(url)
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e)
      return reply.code(502).send({
        error: 'USDA_UPSTREAM',
        message: msg,
        requestId: request.id,
      })
    }
    const text = await upstream.text()
    if (!upstream.ok) {
      const code = upstream.status >= 500 ? 502 : upstream.status
      return reply.code(code).send({
        error: 'USDA_UPSTREAM',
        message: text.slice(0, 500),
        requestId: request.id,
      })
    }
    try {
      return reply.send(JSON.parse(text) as unknown)
    } catch {
      return reply.code(502).send({
        error: 'USDA_BAD_RESPONSE',
        message: 'Invalid JSON from USDA',
        requestId: request.id,
      })
    }
  })

  // POST /v1/nutrition/plan/generate-weekly
  app.post('/plan/generate-weekly', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = GeneratePlanSchema.safeParse(request.body ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body invalid',
        requestId: request.id,
      })
    }

    try {
      const { tzOffset, force } = parsed.data
      const todayYmd = ymdFromUtcWithOffset(new Date(), tzOffset)
      const weekStart = mondayOfWeek(todayYmd)
      const weekDays = buildWeekDays(weekStart)

      const existing = await prisma.nutritionPlanDay.findMany({
        where: { userId, weekStart },
        orderBy: { day: 'asc' },
      })
      if (existing.length === 7 && !force) {
        return reply.send({ weekStart, generated: false, plan: existing })
      }

      const [profile, tp] = await Promise.all([
        prisma.userProfile.findUnique({ where: { userId } }),
        prisma.userTrainingProfile.findUnique({ where: { userId } }),
      ])
      const goal = tp?.primaryGoal ?? 'maintenance'
      const trainingDays = Math.min(6, Math.max(1, tp?.daysPerWeek ?? 4))
      const baseCalories = profile?.dailyCalories ?? 2200
      const baseProtein = Number(profile?.dailyProtein ?? 150)
      const baseCarbs = Number(profile?.dailyCarbs ?? 250)
      const baseFat = Number(profile?.dailyFat ?? 70)
      const water = profile?.dailyWaterMl ?? 2500

      const trainCalAdj =
        goal === 'fat_loss'
          ? -50
          : goal === 'hypertrophy'
            ? 150
            : goal === 'strength'
              ? 120
              : 80
      const restCalAdj = goal === 'fat_loss' ? -180 : -100

      const weekPlan = weekDays.map((day, idx) => {
        const isTraining = idx < trainingDays
        const calories = Math.max(1200, baseCalories + (isTraining ? trainCalAdj : restCalAdj))
        const protein = Math.max(60, Math.round(baseProtein))
        const fat = Math.max(30, Math.round(baseFat + (isTraining ? 0 : -5)))
        const carbs = Math.max(60, Math.round((calories - protein * 4 - fat * 9) / 4))
        return {
          day,
          calories,
          protein,
          carbs,
          fat,
          water,
        }
      })

      let aiMealsByDay: Map<string, NormalizedMealPlan> | null = null
      try {
        aiMealsByDay = await generateWeeklyMealPlanWithDeepSeek({
          weekDays,
          macroRows: weekPlan.map((d) => ({
            day: d.day,
            calories: d.calories,
            proteinG: d.protein,
            carbsG: d.carbs,
            fatG: d.fat,
            waterMl: d.water,
          })),
          goal,
        })
      } catch {
        aiMealsByDay = null
      }

      // Upsert per day keyed on the (userId, day) unique. The previous code
      // did deleteMany({ userId, weekStart }) + create per day, but the unique
      // key is (userId, day) — NOT weekStart. A stale row for the same day
      // under a different weekStart (timezone drift / legacy data) survived the
      // delete and made create() throw P2002. Upsert is idempotent, race-safe,
      // and rewrites weekStart so any drifted row self-heals.
      await prisma.$transaction(async (tx) => {
        for (const d of weekPlan) {
          const mealPlanJson = aiMealsByDay?.get(d.day) ?? null
          const base = {
            userId,
            day: d.day,
            weekStart,
            goal,
            calories: d.calories,
            proteinG: d.protein,
            carbsG: d.carbs,
            fatG: d.fat,
            waterMl: d.water,
            ...(mealPlanJson
              ? { mealPlan: mealPlanJson as unknown as Prisma.InputJsonValue }
              : {}),
          }
          await tx.nutritionPlanDay.upsert({
            where: { userId_day: { userId, day: d.day } },
            create: base,
            update: base,
          })
        }
      })

      const saved = await prisma.nutritionPlanDay.findMany({
        where: { userId, weekStart },
        orderBy: { day: 'asc' },
      })
      return reply.send({ weekStart, generated: true, plan: saved })
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e)
      // Full detail (message + stack) stays server-side only. NEVER echo the
      // raw error to the client — it previously leaked the compiled file path,
      // source lines and Prisma internals into a red box shown to end users.
      app.log.error({ err: e }, 'nutrition plan generate-weekly failed')
      const isProd = process.env.NODE_ENV === 'production'
      return reply.code(500).send({
        error: 'NUTRITION_PLAN_FAILED',
        message: isProd
          ? 'Nu am putut genera planul tău acum. Încearcă din nou în câteva momente.'
          : msg,
        requestId: request.id,
      })
    }
  })

  // GET /v1/nutrition/plan/week?weekStart=YYYY-MM-DD
  app.get('/plan/week', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = WeekQuerySchema.safeParse(request.query ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Invalid query',
        requestId: request.id,
      })
    }
    const weekStart =
      parsed.data.weekStart ?? mondayOfWeek(ymdFromUtcWithOffset(new Date(), parsed.data.tzOffset))
    const plan = await prisma.nutritionPlanDay.findMany({
      where: { userId, weekStart },
      orderBy: { day: 'asc' },
    })
    return reply.send({ weekStart, plan })
  })

  // PATCH /v1/nutrition/plan/day — meal_plan JSON edits (protein swaps, etc.)
  app.patch('/plan/day', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = PatchMealPlanSchema.safeParse(request.body ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body: date (YYYY-MM-DD), mealPlan.meals[]',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const { date, mealPlan } = parsed.data
    const row = await prisma.nutritionPlanDay.findUnique({
      where: { userId_day: { userId, day: date } },
    })
    if (!row) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'No plan day for that date',
        requestId: request.id,
      })
    }
    const updated = await prisma.nutritionPlanDay.update({
      where: { userId_day: { userId, day: date } },
      data: { mealPlan: mealPlan as unknown as Prisma.InputJsonValue },
    })
    return reply.send(updated)
  })

  // GET /v1/nutrition/day?date=YYYY-MM-DD
  app.get('/day', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { date?: string }
    const parsed = DateParam.safeParse(q.date)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Query: date=YYYY-MM-DD',
        requestId: request.id,
      })
    }
    const row = await prisma.nutritionLogDay.findUnique({
      where: { userId_day: { userId, day: parsed.data } },
    })
    if (!row) {
      return reply.send({
        date: parsed.data,
        entries: [],
        waterMl: 0,
        weightKg: null,
        updatedAt: null,
      })
    }
    const inner = payloadFromRow(row.payload)
    return reply.send({
      date: parsed.data,
      ...inner,
      updatedAt: row.updatedAt.toISOString(),
    })
  })

  // PUT /v1/nutrition/day — replace ziua (sync cu app)
  app.put('/day', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = PutDaySchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body: date, entries[], waterMl, weightKg?',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const { date, entries, waterMl, weightKg } = parsed.data
    const payload = {
      entries,
      waterMl,
      weightKg: weightKg ?? null,
    } as Prisma.InputJsonValue
    const row = await prisma.nutritionLogDay.upsert({
      where: { userId_day: { userId, day: date } },
      create: { userId, day: date, payload },
      update: { payload },
    })
    const inner = payloadFromRow(row.payload)
    return reply.send({
      date,
      ...inner,
      updatedAt: row.updatedAt.toISOString(),
    })
  })

  // GET /v1/nutrition/days?from=YYYY-MM-DD&to=YYYY-MM-DD (max 62 zile)
  app.get('/days', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { from?: string; to?: string }
    const from = DateParam.safeParse(q.from)
    const to = DateParam.safeParse(q.to)
    if (!from.success || !to.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Query: from=YYYY-MM-DD&to=YYYY-MM-DD',
        requestId: request.id,
      })
    }
    if (from.data > to.data) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'from must be <= to',
        requestId: request.id,
      })
    }
    const [y1, m1, d1] = from.data.split('-').map(Number)
    const [y2, m2, d2] = to.data.split('-').map(Number)
    const t1 = Date.UTC(y1, m1 - 1, d1)
    const t2 = Date.UTC(y2, m2 - 1, d2)
    const span = (t2 - t1) / 86400000
    if (span > 62) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Max 62 days per request',
        requestId: request.id,
      })
    }

    const rows = await prisma.nutritionLogDay.findMany({
      where: { userId, day: { gte: from.data, lte: to.data } },
      orderBy: { day: 'asc' },
    })
    const data = rows.map((row) => {
      const inner = payloadFromRow(row.payload)
      return {
        date: row.day,
        ...inner,
        updatedAt: row.updatedAt.toISOString(),
      }
    })
    return reply.send({ data })
  })

  // POST /v1/nutrition/claim-xp
  // Award XP for the user's nutrition day (defaults to today in their local
  // tz). Idempotent per day via an analyticsEvent `nutrition_xp_claimed` —
  // calling twice the same day returns the already-claimed amount with
  // `alreadyClaimed: true` so the UI can show a tooltip instead of double XP.
  app.post('/claim-xp', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const body = (request.body as Record<string, unknown>) ?? {}
    const tzOff = Number(body.tzOffset ?? 0)
    const tzOffset = Number.isFinite(tzOff) ? Math.max(-840, Math.min(840, tzOff)) : 0
    const dayParam = typeof body.date === 'string' ? body.date : undefined
    const day = dayParam && /^\d{4}-\d{2}-\d{2}$/.test(dayParam)
      ? dayParam
      : ymdFromUtcWithOffset(new Date(), tzOffset)

    // Idempotency: did we already claim XP for this day?
    const existing = await prisma.analyticsEvent.findFirst({
      where: {
        userId,
        eventName: 'nutrition_xp_claimed',
        props: { path: ['day'], equals: day } as unknown as Prisma.JsonFilter,
      },
      orderBy: { eventTime: 'desc' },
    })
    if (existing) {
      const props = (existing.props as Record<string, unknown> | null) ?? {}
      return reply.send({
        alreadyClaimed: true,
        day,
        xpAwarded: Number(props.xpAwarded ?? 0),
        breakdown: props.breakdown ?? [],
      })
    }

    const [profile, logDay] = await Promise.all([
      prisma.userProfile.findUnique({ where: { userId } }),
      prisma.nutritionLogDay.findUnique({ where: { userId_day: { userId, day } } }),
    ])
    if (!profile) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Profile missing' })
    }

    // Sum actuals from the day's entries.
    const payload = (logDay?.payload as Record<string, unknown> | null) ?? {}
    const entries = Array.isArray(payload.entries) ? payload.entries : []
    const actual = entries.reduce(
      (acc, raw) => {
        const e = (raw && typeof raw === 'object') ? (raw as Record<string, unknown>) : {}
        acc.calories += Number(e.calories ?? 0) || 0
        acc.proteinG += Number(e.proteinG ?? e.protein_g ?? e.protein ?? 0) || 0
        acc.carbsG += Number(e.carbsG ?? e.carbs_g ?? e.carbs ?? 0) || 0
        acc.fatG += Number(e.fatG ?? e.fat_g ?? e.fat ?? 0) || 0
        return acc
      },
      { calories: 0, proteinG: 0, carbsG: 0, fatG: 0 },
    )

    const ctx = resolveUserXpContext({
      bodyweightKg: profile.bodyweightKg as unknown as number | null,
      birthYear: profile.birthYear,
      sex: profile.sex,
    })

    const result = computeNutritionDayXp(
      {
        calories: profile.dailyCalories,
        proteinG: profile.dailyProtein as unknown as number | null,
        carbsG: profile.dailyCarbs as unknown as number | null,
        fatG: profile.dailyFat as unknown as number | null,
      },
      actual,
      ctx,
    )

    if (result.sessionXp <= 0) {
      // Nothing earned — don't record a claim event yet, leave room for the
      // user to log more food today and try again.
      return reply.send({
        alreadyClaimed: false,
        day,
        xpAwarded: 0,
        breakdown: result.breakdown,
        bonusApplied: false,
        ageMultiplier: result.ageMultiplier,
        gameXp: gameXpPayload(profile.gameXpTotal ?? 0),
        message: 'No macro on target yet today.',
      })
    }

    const newTotal = (profile.gameXpTotal ?? 0) + result.sessionXp
    await prisma.$transaction([
      prisma.userProfile.update({
        where: { userId },
        data: { gameXpTotal: newTotal },
      }),
      prisma.analyticsEvent.create({
        data: {
          userId,
          eventName: 'nutrition_xp_claimed',
          props: {
            day,
            xpAwarded: result.sessionXp,
            ageMultiplier: result.ageMultiplier,
            bonusApplied: result.bonusApplied,
            breakdown: result.breakdown as unknown as Prisma.InputJsonValue,
          } as unknown as Prisma.InputJsonValue,
        },
      }),
    ])

    return reply.send({
      alreadyClaimed: false,
      day,
      xpAwarded: result.sessionXp,
      breakdown: result.breakdown,
      bonusApplied: result.bonusApplied,
      ageMultiplier: result.ageMultiplier,
      gameXp: gameXpPayload(newTotal),
    })
  })

  // ── Saved meal templates (per-user CRUD + apply) ───────────────────────────

  // GET /v1/nutrition/templates — the user's saved templates (newest first).
  app.get('/templates', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const rows = await prisma.nutritionMealTemplate.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    })
    return reply.send({
      templates: rows.map((r) => ({
        id: r.id,
        name: r.name,
        items: Array.isArray(r.itemsJson) ? r.itemsJson : [],
        createdAt: r.createdAt.toISOString(),
        updatedAt: r.updatedAt.toISOString(),
      })),
    })
  })

  // POST /v1/nutrition/templates — create a template from a set of items.
  app.post('/templates', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CreateTemplateSchema.safeParse(request.body ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body: { name, items[] }',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const created = await prisma.nutritionMealTemplate.create({
      data: {
        userId,
        name: parsed.data.name,
        itemsJson: parsed.data.items as unknown as Prisma.InputJsonValue,
      },
    })
    return reply.code(201).send({
      id: created.id,
      name: created.name,
      items: parsed.data.items,
      createdAt: created.createdAt.toISOString(),
      updatedAt: created.updatedAt.toISOString(),
    })
  })

  // DELETE /v1/nutrition/templates/:id — delete one of the user's templates.
  app.delete<{ Params: { id: string } }>(
    '/templates/:id',
    { preHandler: authenticate },
    async (request, reply) => {
      const { userId } = request.user
      const id = request.params.id
      // deleteMany scoped to (id, userId) so a user can never delete another
      // user's template — count 0 ⇒ not found (or not theirs).
      const res = await prisma.nutritionMealTemplate.deleteMany({ where: { id, userId } })
      if (res.count === 0) {
        return reply.code(404).send({
          error: 'NOT_FOUND',
          message: 'Template not found',
          requestId: request.id,
        })
      }
      return reply.send({ deleted: true, id })
    },
  )

  // POST /v1/nutrition/templates/:id/apply — append the template's items to the
  // diary for `date`, preserving every existing entry (additive, idempotent per
  // call only in that re-applying appends again — same as logging twice).
  app.post<{ Params: { id: string } }>(
    '/templates/:id/apply',
    { preHandler: authenticate },
    async (request, reply) => {
      const { userId } = request.user
      const id = request.params.id
      const parsed = ApplyTemplateSchema.safeParse(request.body ?? {})
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'Body: { date: YYYY-MM-DD, meal? }',
          requestId: request.id,
          details: parsed.error.flatten(),
        })
      }
      const { date } = parsed.data
      const tpl = await prisma.nutritionMealTemplate.findFirst({ where: { id, userId } })
      if (!tpl) {
        return reply.code(404).send({
          error: 'NOT_FOUND',
          message: 'Template not found',
          requestId: request.id,
        })
      }

      const items = Array.isArray(tpl.itemsJson) ? (tpl.itemsJson as unknown[]) : []
      const nowIso = new Date().toISOString()
      const newEntries = items
        .map((raw, idx) => templateItemToDiaryEntry(raw, parsed.data.meal, nowIso, idx))
        .filter((e): e is Record<string, unknown> => e != null)

      const existing = await prisma.nutritionLogDay.findUnique({
        where: { userId_day: { userId, day: date } },
      })
      const prev = payloadFromRow(existing?.payload)
      const mergedEntries = [...prev.entries, ...newEntries]
      const payload = {
        entries: mergedEntries,
        waterMl: prev.waterMl,
        weightKg: prev.weightKg,
      } as Prisma.InputJsonValue

      const row = await prisma.nutritionLogDay.upsert({
        where: { userId_day: { userId, day: date } },
        create: { userId, day: date, payload },
        update: { payload },
      })
      const inner = payloadFromRow(row.payload)
      return reply.send({
        date,
        applied: newEntries.length,
        ...inner,
        updatedAt: row.updatedAt.toISOString(),
      })
    },
  )

  // ── BMI / TDEE goal suggestion (read-only, opt-in, never auto-applied) ──────
  // GET /v1/nutrition/goal-suggestion — a transparent computed target the user
  // can accept (PATCH /v1/me/profile is unchanged) or ignore. We NEVER write
  // the profile here; this is a pure suggestion with a full "why" breakdown.
  app.get('/goal-suggestion', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = SuggestionQuerySchema.safeParse(request.query ?? {})
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Query: weightKg?, heightCm?, ageYears?, sex?, activity?, goal?',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const [profile, tp] = await Promise.all([
      prisma.userProfile.findUnique({ where: { userId } }),
      prisma.userTrainingProfile.findUnique({ where: { userId } }),
    ])

    const weightKg =
      parsed.data.weightKg ??
      (profile?.bodyweightKg != null ? Number(profile.bodyweightKg) : undefined)
    const heightCm =
      parsed.data.heightCm ??
      (profile?.heightCm != null ? Number(profile.heightCm) : undefined)
    const currentYear = new Date().getUTCFullYear()
    const ageYears =
      parsed.data.ageYears ??
      (profile?.birthYear != null ? currentYear - profile.birthYear : undefined)
    const sex = parsed.data.sex ?? profile?.sex ?? null

    const missing: string[] = []
    if (weightKg == null) missing.push('weightKg')
    if (heightCm == null) missing.push('heightCm')
    if (ageYears == null) missing.push('ageYears')
    if (missing.length > 0) {
      // Not an error the client should treat as a failure — it's a prompt to
      // collect the missing demographics. 422 keeps it distinct from 400.
      return reply.code(422).send({
        error: 'PROFILE_INCOMPLETE',
        message: 'Need weight, height and age to compute a suggestion.',
        missing,
        requestId: request.id,
      })
    }

    const rawGoal = parsed.data.goal ?? (tp?.primaryGoal as GoalKey | undefined)
    const goal: GoalKey =
      rawGoal && VALID_GOALS.includes(rawGoal) ? rawGoal : 'maintenance'

    const s = computeNutritionSuggestion({
      weightKg: weightKg as number,
      heightCm: heightCm as number,
      ageYears: ageYears as number,
      sex,
      activity: parsed.data.activity,
      goal,
    })

    return reply.send({
      // The suggestion the user MAY accept.
      suggestion: {
        calories: s.calories,
        proteinG: s.proteinG,
        carbsG: s.carbsG,
        fatG: s.fatG,
      },
      // Full transparency: every input + intermediate, so the UI shows the why.
      inputs: {
        weightKg,
        heightCm,
        ageYears,
        sex,
        activity: parsed.data.activity,
        goal,
      },
      explain: {
        equation: 'Mifflin-St Jeor',
        bmr: s.bmr,
        activityMultiplier: s.activityMultiplier,
        tdee: s.tdee,
        calorieDelta: s.calorieDelta,
        bmi: s.bmi,
        proteinPerKg: 1.8,
        fatPctOfCalories: 0.25,
      },
      // Explicit: the client must apply this via PATCH /v1/me/profile.
      autoApplied: false,
      requestId: request.id,
    })
  })
}

/**
 * Convert a saved-template item into a diary MealEntry-shaped object that BOTH
 * the strict app parser (MealEntry.fromJson → nested FoodItem) and the lenient
 * claim-xp summer (top-level calories/proteinG/…) can read. Items carry totals;
 * we derive a per-100 g FoodItem from `grams` (defaulting to a 100 g serving so
 * the totals == per-100 g values when grams is absent). Returns null on garbage.
 */
export function templateItemToDiaryEntry(
  raw: unknown,
  defaultMeal: string | undefined,
  loggedAtIso: string,
  index: number,
): Record<string, unknown> | null {
  if (!raw || typeof raw !== 'object') return null
  const it = raw as Record<string, unknown>
  const name = typeof it.name === 'string' ? it.name.trim() : ''
  if (name.length === 0) return null

  const num = (v: unknown): number => {
    const n = Number(v)
    return Number.isFinite(n) && n > 0 ? n : 0
  }
  const grams = num(it.grams) > 0 ? num(it.grams) : 100
  const calories = num(it.calories)
  const proteinG = num(it.proteinG)
  const carbsG = num(it.carbsG)
  const fatG = num(it.fatG)
  const per100 = (total: number) => (grams > 0 ? (total * 100) / grams : total)
  const meal =
    (typeof it.meal === 'string' && it.meal.trim().length > 0 ? it.meal.trim() : undefined) ??
    defaultMeal ??
    'snack'

  return {
    id: `tpl_${loggedAtIso}_${index}`,
    food: {
      id: `tpl_${name.toLowerCase().replace(/\s+/g, '-').slice(0, 48)}`,
      name,
      brand: 'Saved meal',
      caloriesPer100g: per100(calories),
      proteinPer100g: per100(proteinG),
      fatPer100g: per100(fatG),
      carbsPer100g: per100(carbsG),
    },
    grams,
    meal,
    loggedAt: loggedAtIso,
    // Denormalized totals for the lenient XP summer (kept consistent with grams).
    calories,
    proteinG,
    carbsG,
    fatG,
  }
}
