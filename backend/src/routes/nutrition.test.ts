import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// We mock prisma so the route's REAL validation + serialization + scoping logic
// runs end-to-end, while the DB layer is a set of spies (same pattern as
// gdpr.test.ts / messages.test.ts). The XP helpers are mocked to deterministic
// returns so the claim-xp tests exercise the route's idempotency state machine
// rather than the XP math (which has its own pure-function tests).
// vi.mock factories are hoisted above const declarations, so the spies they
// reference must be created with vi.hoisted (which runs first) — otherwise the
// factory hits a TDZ "cannot access before initialization" when the route's
// `import '../lib/prisma'` is resolved during setup.
const {
  nutritionPlanDay,
  nutritionLogDay,
  nutritionMealTemplate,
  userProfile,
  userTrainingProfile,
  analyticsEvent,
  transaction,
  generateWeeklyMealPlanWithDeepSeek,
  computeNutritionDayXp,
} = vi.hoisted(() => ({
  nutritionPlanDay: { findMany: vi.fn(), findUnique: vi.fn(), update: vi.fn(), upsert: vi.fn() },
  nutritionLogDay: { findUnique: vi.fn(), findMany: vi.fn(), upsert: vi.fn() },
  nutritionMealTemplate: {
    findMany: vi.fn(),
    findFirst: vi.fn(),
    create: vi.fn(),
    deleteMany: vi.fn(),
  },
  userProfile: { findUnique: vi.fn(), update: vi.fn() },
  userTrainingProfile: { findUnique: vi.fn() },
  analyticsEvent: { findFirst: vi.fn(), create: vi.fn() },
  transaction: vi.fn(),
  generateWeeklyMealPlanWithDeepSeek: vi.fn(),
  computeNutritionDayXp: vi.fn(),
}))

vi.mock('../lib/prisma', () => ({
  prisma: {
    nutritionPlanDay,
    nutritionLogDay,
    nutritionMealTemplate,
    userProfile,
    userTrainingProfile,
    analyticsEvent,
    $transaction: (...a: unknown[]) => transaction(...a),
  },
}))

let meId = 'u1'
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: meId, email: `${meId}@t.dev` }
  },
}))

// Keep the AI meal generation out of the unit: a unit must never reach DeepSeek.
// PatchMealPlanSchema is used by the route at import time, so keep the real one.
vi.mock('../services/meal-plan-ai.service', async () => {
  const actual = await vi.importActual<typeof import('../services/meal-plan-ai.service')>(
    '../services/meal-plan-ai.service',
  )
  return {
    ...actual,
    generateWeeklyMealPlanWithDeepSeek: (...a: unknown[]) =>
      generateWeeklyMealPlanWithDeepSeek(...a),
  }
})

// XP helpers — deterministic stubs so claim-xp tests assert flow, not math.
vi.mock('../services/nutrition-xp.service', () => ({
  computeNutritionDayXp: (...a: unknown[]) => computeNutritionDayXp(...a),
}))
vi.mock('../services/cardio-xp.service', () => ({
  resolveUserXpContext: () => ({ ageMultiplier: 1, weightFactor: 1, sex: 'male' }),
}))
vi.mock('../services/gym-xp.service', () => ({
  gameXpPayload: (total: number) => ({ total }),
}))

// OFF fallback is a real lib but must never hit the network in a unit. Default
// to "no OFF results" so the USDA-only behavior is unchanged; individual tests
// override searchOffByName when they assert fallback wiring.
const { searchOffByName } = vi.hoisted(() => ({ searchOffByName: vi.fn() }))
vi.mock('../lib/open-food-facts', () => ({
  searchOffByName: (...a: unknown[]) => searchOffByName(...a),
}))

import {
  nutritionRoutes,
  computeNutritionSuggestion,
  mifflinStJeorBmr,
  goalCalorieDelta,
  templateItemToDiaryEntry,
} from './nutrition'

async function buildApp() {
  const app = Fastify()
  await app.register(nutritionRoutes, { prefix: '/v1/nutrition' })
  await app.ready()
  return app
}

beforeEach(() => {
  meId = 'u1'
  delete process.env.USDA_API_KEY
  for (const m of [nutritionPlanDay, nutritionLogDay, nutritionMealTemplate, userProfile, userTrainingProfile, analyticsEvent]) {
    Object.values(m).forEach((fn) => (fn as ReturnType<typeof vi.fn>).mockReset())
  }
  transaction.mockReset()
  generateWeeklyMealPlanWithDeepSeek.mockReset().mockResolvedValue(null)
  computeNutritionDayXp.mockReset()
  searchOffByName.mockReset().mockResolvedValue([])
})

// ── USDA proxy gating ────────────────────────────────────────────────────────
describe('USDA proxy — configuration + validation gates', () => {
  it('503 USDA_NOT_CONFIGURED when no API key is set (search)', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/usda/foods/search',
      payload: { query: 'chicken' },
    })
    expect(res.statusCode).toBe(503)
    expect(res.json()).toMatchObject({ error: 'USDA_NOT_CONFIGURED' })
    await app.close()
  })

  it('400 VALIDATION_ERROR when the search body is missing query (key present)', async () => {
    process.env.USDA_API_KEY = 'test-key'
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/usda/foods/search',
      payload: { pageSize: 10 },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })

  it('400 VALIDATION_ERROR on a non-numeric fdcId in the detail proxy', async () => {
    process.env.USDA_API_KEY = 'test-key'
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/usda/food/not-a-number' })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })
})

// ── GET /day — empty-state + payload coercion ────────────────────────────────
describe('GET /v1/nutrition/day — read + offline empty state', () => {
  it('400 when date is not YYYY-MM-DD', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/day?date=2026-6-1' })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(nutritionLogDay.findUnique).not.toHaveBeenCalled()
    await app.close()
  })

  it('returns an empty day (no row) without crashing the client', async () => {
    nutritionLogDay.findUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/day?date=2026-06-13' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({
      date: '2026-06-13',
      entries: [],
      waterMl: 0,
      weightKg: null,
      updatedAt: null,
    })
    // Read is scoped to the authed user + the requested day.
    expect(nutritionLogDay.findUnique).toHaveBeenCalledWith({
      where: { userId_day: { userId: 'u1', day: '2026-06-13' } },
    })
    await app.close()
  })

  it('normalizes a stored payload (string weightKg → number, missing fields → defaults)', async () => {
    nutritionLogDay.findUnique.mockResolvedValue({
      payload: { entries: [{ text: 'eggs' }], weightKg: '82.5' }, // waterMl missing
      updatedAt: new Date('2026-06-13T08:00:00.000Z'),
    })
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/day?date=2026-06-13' })
    const body = res.json()
    expect(body.entries).toEqual([{ text: 'eggs' }])
    expect(body.waterMl).toBe(0)
    expect(body.weightKg).toBe(82.5)
    expect(typeof body.weightKg).toBe('number')
    expect(body.updatedAt).toBe('2026-06-13T08:00:00.000Z')
    await app.close()
  })
})

// ── PUT /day — sync upsert (offline replay) ──────────────────────────────────
describe('PUT /v1/nutrition/day — sync upsert', () => {
  it('400 VALIDATION_ERROR when weightKg is below the allowed range', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'PUT',
      url: '/v1/nutrition/day',
      payload: { date: '2026-06-13', entries: [], waterMl: 0, weightKg: 5 },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(nutritionLogDay.upsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('upserts the day scoped to (userId, day) and echoes the normalized payload', async () => {
    nutritionLogDay.upsert.mockResolvedValue({
      payload: { entries: [{ text: 'rice' }], waterMl: 500, weightKg: 80 },
      updatedAt: new Date('2026-06-13T10:00:00.000Z'),
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'PUT',
      url: '/v1/nutrition/day',
      payload: { date: '2026-06-13', entries: [{ text: 'rice' }], waterMl: 500, weightKg: 80 },
    })
    expect(res.statusCode).toBe(200)
    const args = nutritionLogDay.upsert.mock.calls[0][0]
    expect(args.where).toEqual({ userId_day: { userId: 'u1', day: '2026-06-13' } })
    // The upsert is keyed so a re-pushed offline write overwrites rather than dupes.
    expect(args.create).toMatchObject({ userId: 'u1', day: '2026-06-13' })
    const body = res.json()
    expect(body).toMatchObject({ date: '2026-06-13', waterMl: 500, weightKg: 80 })
    await app.close()
  })

  it('coerces a missing weightKg to null in the persisted payload', async () => {
    nutritionLogDay.upsert.mockResolvedValue({
      payload: { entries: [], waterMl: 0, weightKg: null },
      updatedAt: new Date('2026-06-13T10:00:00.000Z'),
    })
    const app = await buildApp()
    await app.inject({
      method: 'PUT',
      url: '/v1/nutrition/day',
      payload: { date: '2026-06-13', entries: [], waterMl: 0 },
    })
    const args = nutritionLogDay.upsert.mock.calls[0][0]
    expect(args.create.payload.weightKg).toBeNull()
    expect(args.update.payload.weightKg).toBeNull()
    await app.close()
  })
})

// ── GET /days — bounded range query ──────────────────────────────────────────
describe('GET /v1/nutrition/days — range guards + scoping', () => {
  it('400 when from > to', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: '/v1/nutrition/days?from=2026-06-20&to=2026-06-10',
    })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(nutritionLogDay.findMany).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 when the range exceeds 62 days', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: '/v1/nutrition/days?from=2026-01-01&to=2026-06-01',
    })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })

  it('queries within range scoped to the user and maps payloads', async () => {
    nutritionLogDay.findMany.mockResolvedValue([
      { day: '2026-06-10', payload: { entries: [], waterMl: 250, weightKg: '79.9' }, updatedAt: new Date('2026-06-10T00:00:00.000Z') },
    ])
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: '/v1/nutrition/days?from=2026-06-10&to=2026-06-12',
    })
    expect(res.statusCode).toBe(200)
    expect(nutritionLogDay.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1', day: { gte: '2026-06-10', lte: '2026-06-12' } },
      orderBy: { day: 'asc' },
    })
    expect(res.json().data[0]).toMatchObject({ date: '2026-06-10', waterMl: 250, weightKg: 79.9 })
    await app.close()
  })
})

// ── GET /plan/week — per-user scoping ────────────────────────────────────────
describe('GET /v1/nutrition/plan/week — per-user scoping', () => {
  it('scopes the plan lookup to the authed user + given weekStart', async () => {
    meId = 'someone-else'
    nutritionPlanDay.findMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: '/v1/nutrition/plan/week?weekStart=2026-06-08',
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ weekStart: '2026-06-08', plan: [] })
    expect(nutritionPlanDay.findMany).toHaveBeenCalledWith({
      where: { userId: 'someone-else', weekStart: '2026-06-08' },
      orderBy: { day: 'asc' },
    })
    await app.close()
  })
})

// ── PATCH /plan/day — meal plan edit ─────────────────────────────────────────
describe('PATCH /v1/nutrition/plan/day — meal plan edits', () => {
  it('404 NOT_FOUND when no plan day exists for the date', async () => {
    nutritionPlanDay.findUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/v1/nutrition/plan/day',
      payload: { date: '2026-06-13', mealPlan: { meals: [{ meal: 'lunch', items: [{ text: 'rice' }] }] } },
    })
    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    // We never update a row that doesn't belong to / exist for this user.
    expect(nutritionPlanDay.update).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 VALIDATION_ERROR on a malformed mealPlan body', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/v1/nutrition/plan/day',
      payload: { date: '2026-06-13', mealPlan: { meals: [] } }, // meals must have >=1
    })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(nutritionPlanDay.findUnique).not.toHaveBeenCalled()
    await app.close()
  })
})

// ── POST /claim-xp — idempotency state machine ───────────────────────────────
describe('POST /v1/nutrition/claim-xp — idempotency', () => {
  it('returns alreadyClaimed when an XP event exists for the day (no double award)', async () => {
    analyticsEvent.findFirst.mockResolvedValue({
      props: { day: '2026-06-13', xpAwarded: 42, breakdown: [{ macro: 'protein' }] },
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/claim-xp',
      payload: { date: '2026-06-13' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ alreadyClaimed: true, day: '2026-06-13', xpAwarded: 42 })
    // Idempotency short-circuits BEFORE any profile/log read or write.
    expect(userProfile.findUnique).not.toHaveBeenCalled()
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })

  it('404 NOT_FOUND when the user has no profile', async () => {
    analyticsEvent.findFirst.mockResolvedValue(null)
    userProfile.findUnique.mockResolvedValue(null)
    nutritionLogDay.findUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/claim-xp',
      payload: { date: '2026-06-13' },
    })
    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })

  it('awards no XP and records NO claim event when nothing is on target yet', async () => {
    analyticsEvent.findFirst.mockResolvedValue(null)
    userProfile.findUnique.mockResolvedValue({
      dailyCalories: 2200, dailyProtein: 150, dailyCarbs: 250, dailyFat: 70,
      bodyweightKg: 80, birthYear: 1984, sex: 'male', gameXpTotal: 100,
    })
    nutritionLogDay.findUnique.mockResolvedValue({ payload: { entries: [] } })
    computeNutritionDayXp.mockReturnValue({ sessionXp: 0, breakdown: [], ageMultiplier: 1, bonusApplied: false })
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/claim-xp',
      payload: { date: '2026-06-13' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ alreadyClaimed: false, xpAwarded: 0 })
    // No claim event is persisted, so the user can log more and retry today.
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })

  it('awards XP and writes the claim event in a single transaction when on target', async () => {
    analyticsEvent.findFirst.mockResolvedValue(null)
    userProfile.findUnique.mockResolvedValue({
      dailyCalories: 2200, dailyProtein: 150, dailyCarbs: 250, dailyFat: 70,
      bodyweightKg: 80, birthYear: 1984, sex: 'male', gameXpTotal: 100,
    })
    nutritionLogDay.findUnique.mockResolvedValue({
      payload: { entries: [{ calories: 600, proteinG: 50, carbsG: 60, fatG: 20 }] },
    })
    computeNutritionDayXp.mockReturnValue({ sessionXp: 30, breakdown: [{ macro: 'protein' }], ageMultiplier: 1, bonusApplied: true })
    transaction.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/claim-xp',
      payload: { date: '2026-06-13' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ alreadyClaimed: false, day: '2026-06-13', xpAwarded: 30, bonusApplied: true })
    // The update + claim-event create happen atomically.
    expect(transaction).toHaveBeenCalledOnce()
    await app.close()
  })
})

// ── OFF fallback wiring ──────────────────────────────────────────────────────
describe('USDA search — Open Food Facts fallback', () => {
  it('does NOT call OFF when USDA returns a rich page of hits', async () => {
    process.env.USDA_API_KEY = 'k'
    // 8+ usable USDA hits (>= MIN_USDA_HITS_BEFORE_OFF) → OFF merge is skipped.
    const usdaBody = JSON.stringify({
      foods: Array.from({ length: 8 }, (_, i) => ({
        description: `Chicken ${i}`,
        foodNutrients: [{ nutrientName: 'Energy', value: 165 }],
      })),
    })
    const spy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(usdaBody, { status: 200 }))
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/usda/foods/search',
      payload: { query: 'chicken' },
    })
    expect(res.statusCode).toBe(200)
    expect(searchOffByName).not.toHaveBeenCalled()
    expect(res.json().foods).toHaveLength(8)
    spy.mockRestore()
    await app.close()
  })

  it('merges OFF after USDA when USDA returns only a few hits (EU coverage)', async () => {
    process.env.USDA_API_KEY = 'k'
    // One thin generic USDA hit (< MIN_USDA_HITS_BEFORE_OFF) → OFF is queried and
    // its branded EU rows are appended so the actual product is findable.
    const spy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          foods: [{ description: 'Generic hazelnut spread', foodNutrients: [{ nutrientName: 'Energy', value: 500 }] }],
        }),
        { status: 200 },
      ),
    )
    searchOffByName.mockResolvedValue([
      { fdcId: 'off:nutella', description: 'Nutella', foodNutrients: [{ nutrientName: 'Energy', value: 539 }] },
    ])
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/usda/foods/search',
      payload: { query: 'nutella' },
    })
    expect(res.statusCode).toBe(200)
    expect(searchOffByName).toHaveBeenCalledWith('nutella', { pageSize: 25 })
    const foods = res.json().foods
    expect(foods).toHaveLength(2) // USDA generic first, OFF appended
    expect(foods[0].description).toBe('Generic hazelnut spread')
    expect(foods[1].fdcId).toBe('off:nutella')
    spy.mockRestore()
    await app.close()
  })

  it('appends OFF rows after USDA when USDA returns zero usable hits', async () => {
    process.env.USDA_API_KEY = 'k'
    const spy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify({ foods: [] }), { status: 200 }))
    searchOffByName.mockResolvedValue([
      {
        fdcId: 'off:123',
        description: 'Off Bar',
        dataType: 'Open Food Facts',
        foodNutrients: [{ nutrientName: 'Energy', unitName: 'kcal', value: 250 }],
      },
    ])
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/usda/foods/search',
      payload: { query: 'obscure bar' },
    })
    expect(res.statusCode).toBe(200)
    expect(searchOffByName).toHaveBeenCalledWith('obscure bar', { pageSize: 25 })
    const foods = res.json().foods
    expect(foods).toHaveLength(1)
    expect(foods[0].fdcId).toBe('off:123')
    spy.mockRestore()
    await app.close()
  })

  it('falls back to OFF when USDA upstream is unreachable', async () => {
    process.env.USDA_API_KEY = 'k'
    const spy = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('ECONNREFUSED'))
    searchOffByName.mockResolvedValue([
      {
        fdcId: 'off:9',
        description: 'Fallback Food',
        dataType: 'Open Food Facts',
        foodNutrients: [{ nutrientName: 'Energy', unitName: 'kcal', value: 100 }],
      },
    ])
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/usda/foods/search',
      payload: { query: 'x' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().foods[0].fdcId).toBe('off:9')
    spy.mockRestore()
    await app.close()
  })
})

// ── Saved meal templates ─────────────────────────────────────────────────────
describe('Meal templates — CRUD + apply', () => {
  it('lists the user templates scoped + serialized', async () => {
    nutritionMealTemplate.findMany.mockResolvedValue([
      {
        id: 't1',
        name: 'Breakfast',
        itemsJson: [{ name: 'Oats' }],
        createdAt: new Date('2026-06-10T00:00:00.000Z'),
        updatedAt: new Date('2026-06-10T00:00:00.000Z'),
      },
    ])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/templates' })
    expect(res.statusCode).toBe(200)
    expect(nutritionMealTemplate.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      orderBy: { createdAt: 'desc' },
    })
    expect(res.json().templates[0]).toMatchObject({ id: 't1', name: 'Breakfast' })
    await app.close()
  })

  it('400 when creating a template with no items', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/templates',
      payload: { name: 'Empty', items: [] },
    })
    expect(res.statusCode).toBe(400)
    expect(nutritionMealTemplate.create).not.toHaveBeenCalled()
    await app.close()
  })

  it('creates a template scoped to the user (201)', async () => {
    nutritionMealTemplate.create.mockResolvedValue({
      id: 't9',
      name: 'Lunch',
      createdAt: new Date('2026-06-13T00:00:00.000Z'),
      updatedAt: new Date('2026-06-13T00:00:00.000Z'),
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/templates',
      payload: { name: 'Lunch', items: [{ name: 'Rice', grams: 200, calories: 260 }] },
    })
    expect(res.statusCode).toBe(201)
    expect(nutritionMealTemplate.create.mock.calls[0][0].data).toMatchObject({ userId: 'u1', name: 'Lunch' })
    expect(res.json()).toMatchObject({ id: 't9', name: 'Lunch' })
    await app.close()
  })

  it('404 when deleting a template that is not the user (deleteMany count 0)', async () => {
    nutritionMealTemplate.deleteMany.mockResolvedValue({ count: 0 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/nutrition/templates/nope' })
    expect(res.statusCode).toBe(404)
    expect(nutritionMealTemplate.deleteMany).toHaveBeenCalledWith({ where: { id: 'nope', userId: 'u1' } })
    await app.close()
  })

  it('applies a template by appending diary entries to the existing day', async () => {
    nutritionMealTemplate.findFirst.mockResolvedValue({
      id: 't1',
      userId: 'u1',
      itemsJson: [{ name: 'Rice', grams: 200, calories: 260, proteinG: 5, carbsG: 56, fatG: 1 }],
    })
    nutritionLogDay.findUnique.mockResolvedValue({
      payload: { entries: [{ text: 'existing' }], waterMl: 500, weightKg: 80 },
    })
    nutritionLogDay.upsert.mockImplementation(async ({ create }: { create: { payload: unknown } }) => ({
      payload: create.payload,
      updatedAt: new Date('2026-06-13T12:00:00.000Z'),
    }))
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/templates/t1/apply',
      payload: { date: '2026-06-13', meal: 'lunch' },
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.applied).toBe(1)
    // Existing entry preserved + one appended; water/weight untouched.
    expect(body.entries).toHaveLength(2)
    expect(body.waterMl).toBe(500)
    expect(body.weightKg).toBe(80)
    const appended = body.entries[1]
    expect(appended.calories).toBe(260)
    expect(appended.food.caloriesPer100g).toBeCloseTo(130) // 260 over 200g → 130/100g
    await app.close()
  })

  it('404 applying a template that does not belong to the user', async () => {
    nutritionMealTemplate.findFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/templates/x/apply',
      payload: { date: '2026-06-13' },
    })
    expect(res.statusCode).toBe(404)
    expect(nutritionLogDay.upsert).not.toHaveBeenCalled()
    await app.close()
  })
})

// ── Goal suggestion endpoint (opt-in, never auto-applied) ────────────────────
describe('GET /goal-suggestion — read-only suggestion', () => {
  it('422 PROFILE_INCOMPLETE when demographics are missing', async () => {
    userProfile.findUnique.mockResolvedValue({ bodyweightKg: 80 }) // no height/age
    userTrainingProfile.findUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/goal-suggestion' })
    expect(res.statusCode).toBe(422)
    expect(res.json()).toMatchObject({ error: 'PROFILE_INCOMPLETE' })
    expect(res.json().missing).toContain('heightCm')
    await app.close()
  })

  it('returns a transparent suggestion and never writes the profile', async () => {
    userProfile.findUnique.mockResolvedValue({
      bodyweightKg: 80,
      heightCm: 180,
      birthYear: 1990,
      sex: 'male',
    })
    userTrainingProfile.findUnique.mockResolvedValue({ primaryGoal: 'fat_loss' })
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: '/v1/nutrition/goal-suggestion?activity=moderate',
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.autoApplied).toBe(false)
    expect(body.explain.equation).toBe('Mifflin-St Jeor')
    expect(body.inputs.goal).toBe('fat_loss')
    expect(body.suggestion.calories).toBeLessThan(body.explain.tdee) // deficit applied
    // Read-only: profile is never updated by this endpoint.
    expect(userProfile.update).not.toHaveBeenCalled()
    await app.close()
  })

  it('query overrides take precedence over stored profile', async () => {
    userProfile.findUnique.mockResolvedValue({ bodyweightKg: 80, heightCm: 180, birthYear: 1990, sex: 'male' })
    userTrainingProfile.findUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: '/v1/nutrition/goal-suggestion?weightKg=100&goal=hypertrophy&activity=active',
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().inputs.weightKg).toBe(100)
    expect(res.json().inputs.goal).toBe('hypertrophy')
    await app.close()
  })
})

// ── Pure TDEE / suggestion math ──────────────────────────────────────────────
describe('Mifflin-St Jeor + TDEE math (pure)', () => {
  it('matches the published male BMR formula', () => {
    // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
    expect(mifflinStJeorBmr({ weightKg: 80, heightCm: 180, ageYears: 30, sex: 'male' })).toBeCloseTo(1780)
  })

  it('applies the female constant', () => {
    // ... - 161 = 1780 - 5 - 161 → use male base then swap: base = 1775; female = 1775 - 161 = 1614
    expect(mifflinStJeorBmr({ weightKg: 80, heightCm: 180, ageYears: 30, sex: 'female' })).toBeCloseTo(1614)
  })

  it('uses the neutral midpoint for unknown sex', () => {
    expect(mifflinStJeorBmr({ weightKg: 80, heightCm: 180, ageYears: 30, sex: null })).toBeCloseTo(1697)
  })

  it('caps the fat-loss deficit at 750 kcal', () => {
    expect(goalCalorieDelta('fat_loss', 5000)).toBe(-750) // 20% would be 1000, capped
    expect(goalCalorieDelta('fat_loss', 2000)).toBe(-400) // 20% under the cap
  })

  it('maintenance + calisthenics carry no delta', () => {
    expect(goalCalorieDelta('maintenance', 2500)).toBe(0)
    expect(goalCalorieDelta('calisthenics', 2500)).toBe(0)
  })

  it('produces a self-consistent, floored, macro-balanced suggestion', () => {
    const s = computeNutritionSuggestion({
      weightKg: 80,
      heightCm: 180,
      ageYears: 30,
      sex: 'male',
      activity: 'moderate',
      goal: 'maintenance',
    })
    expect(s.bmr).toBe(1780)
    expect(s.tdee).toBe(Math.round(1780 * 1.55))
    expect(s.calorieDelta).toBe(0)
    expect(s.calories).toBe(s.tdee)
    expect(s.proteinG).toBe(144) // 80 * 1.8
    expect(s.bmi).toBeCloseTo(24.7, 1)
    // Macro kcal should land within rounding distance of the calorie target.
    const macroKcal = s.proteinG * 4 + s.carbsG * 4 + s.fatG * 9
    expect(Math.abs(macroKcal - s.calories)).toBeLessThanOrEqual(8)
  })

  it('never suggests below the 1200 kcal floor', () => {
    const s = computeNutritionSuggestion({
      weightKg: 45,
      heightCm: 150,
      ageYears: 25,
      sex: 'female',
      activity: 'sedentary',
      goal: 'fat_loss',
    })
    expect(s.calories).toBeGreaterThanOrEqual(1200)
  })
})

// ── templateItemToDiaryEntry (pure) ──────────────────────────────────────────
describe('templateItemToDiaryEntry (pure)', () => {
  it('derives per-100g macros from grams + totals', () => {
    const e = templateItemToDiaryEntry(
      { name: 'Rice', grams: 200, calories: 260, proteinG: 6, carbsG: 56, fatG: 1 },
      'lunch',
      '2026-06-13T00:00:00.000Z',
      0,
    )
    expect(e).not.toBeNull()
    expect(e!.calories).toBe(260)
    const food = e!.food as Record<string, number>
    expect(food.caloriesPer100g).toBeCloseTo(130)
    expect(food.proteinPer100g).toBeCloseTo(3)
  })

  it('treats a missing grams as a 100g serving (totals == per-100g)', () => {
    const e = templateItemToDiaryEntry(
      { name: 'Bar', calories: 200, proteinG: 20 },
      undefined,
      '2026-06-13T00:00:00.000Z',
      1,
    )
    const food = e!.food as Record<string, number>
    expect((e!.grams as number)).toBe(100)
    expect(food.caloriesPer100g).toBe(200)
    expect(e!.meal).toBe('snack') // default when neither item.meal nor defaultMeal
  })

  it('returns null for a nameless / garbage item', () => {
    expect(templateItemToDiaryEntry({ calories: 10 }, undefined, 'x', 0)).toBeNull()
    expect(templateItemToDiaryEntry(null, undefined, 'x', 0)).toBeNull()
  })
})
