import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

const userCustomFood = { findMany: vi.fn(), findFirst: vi.fn(), create: vi.fn(), update: vi.fn(), delete: vi.fn() }
const userFavoriteFood = { findMany: vi.fn(), upsert: vi.fn(), deleteMany: vi.fn() }
const userRecipe = { findMany: vi.fn(), findFirst: vi.fn(), create: vi.fn(), update: vi.fn(), delete: vi.fn() }
const nutritionLogDay = { findMany: vi.fn() }

vi.mock('../lib/prisma', () => ({
  prisma: {
    userCustomFood: {
      findMany: (...a: unknown[]) => userCustomFood.findMany(...a),
      findFirst: (...a: unknown[]) => userCustomFood.findFirst(...a),
      create: (...a: unknown[]) => userCustomFood.create(...a),
      update: (...a: unknown[]) => userCustomFood.update(...a),
      delete: (...a: unknown[]) => userCustomFood.delete(...a),
    },
    userFavoriteFood: {
      findMany: (...a: unknown[]) => userFavoriteFood.findMany(...a),
      upsert: (...a: unknown[]) => userFavoriteFood.upsert(...a),
      deleteMany: (...a: unknown[]) => userFavoriteFood.deleteMany(...a),
    },
    userRecipe: {
      findMany: (...a: unknown[]) => userRecipe.findMany(...a),
      findFirst: (...a: unknown[]) => userRecipe.findFirst(...a),
      create: (...a: unknown[]) => userRecipe.create(...a),
      update: (...a: unknown[]) => userRecipe.update(...a),
      delete: (...a: unknown[]) => userRecipe.delete(...a),
    },
    nutritionLogDay: { findMany: (...a: unknown[]) => nutritionLogDay.findMany(...a) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { nutritionFoodsRoutes } from './nutrition-foods'

async function buildApp() {
  const app = Fastify()
  await app.register(nutritionFoodsRoutes, { prefix: '/v1/nutrition' })
  await app.ready()
  return app
}

const customRow = {
  id: 'cf1',
  name: 'My Protein Shake',
  brand: 'Home',
  caloriesPer100g: 380,
  proteinPer100g: 75,
  carbsPer100g: 8,
  fatPer100g: 5,
  servingGrams: 30,
  servingLabel: 'scoop',
}

beforeEach(() => {
  for (const grp of [userCustomFood, userFavoriteFood, userRecipe, nutritionLogDay]) {
    for (const fn of Object.values(grp)) fn.mockReset()
  }
})

describe('custom foods', () => {
  it('lists with id prefixed custom:', async () => {
    userCustomFood.findMany.mockResolvedValue([customRow])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/custom-foods' })
    expect(res.statusCode).toBe(200)
    expect(res.json().data[0].id).toBe('custom:cf1')
    await app.close()
  })

  it('creates a custom food (201)', async () => {
    userCustomFood.create.mockResolvedValue(customRow)
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/custom-foods',
      payload: { name: 'My Protein Shake', caloriesPer100g: 380, proteinPer100g: 75, carbsPer100g: 8, fatPer100g: 5 },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json().food.id).toBe('custom:cf1')
    await app.close()
  })

  it('400s an invalid custom food (missing macros)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/nutrition/custom-foods', payload: { name: 'x' } })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
    await app.close()
  })

  it('404s deleting another user\'s food', async () => {
    userCustomFood.findFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/nutrition/custom-foods/cfX' })
    expect(res.statusCode).toBe(404)
    await app.close()
  })
})

describe('favorite foods', () => {
  it('upserts a favorite (idempotent star)', async () => {
    userFavoriteFood.upsert.mockResolvedValue({})
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/favorite-foods',
      payload: { foodId: 'off:123', name: 'Skyr', caloriesPer100g: 63, proteinPer100g: 11, carbsPer100g: 4, fatPer100g: 0.2 },
    })
    expect(res.statusCode).toBe(201)
    expect(userFavoriteFood.upsert).toHaveBeenCalledOnce()
    const arg = userFavoriteFood.upsert.mock.calls[0][0] as { where: { userId_foodId: { userId: string; foodId: string } } }
    expect(arg.where.userId_foodId).toEqual({ userId: 'u1', foodId: 'off:123' })
    await app.close()
  })

  it('removes a favorite (204)', async () => {
    userFavoriteFood.deleteMany.mockResolvedValue({ count: 1 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/nutrition/favorite-foods/off:123' })
    expect(res.statusCode).toBe(204)
    await app.close()
  })
})

describe('recipes', () => {
  it('computes totals from ingredients on create', async () => {
    userRecipe.create.mockImplementation(async ({ data }: { data: Record<string, unknown> }) => ({ id: 'r1', ...data }))
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/recipes',
      payload: {
        name: 'Oats bowl',
        servings: 2,
        ingredients: [
          { name: 'Oats', grams: 100, caloriesPer100g: 380, proteinPer100g: 13, carbsPer100g: 60, fatPer100g: 7 },
          { name: 'Milk', grams: 200, caloriesPer100g: 50, proteinPer100g: 3.4, carbsPer100g: 5, fatPer100g: 2 },
        ],
      },
    })
    expect(res.statusCode).toBe(201)
    const r = res.json().recipe
    // 380 + (50*2) = 480 kcal; protein 13 + 6.8 = 19.8
    expect(r.totalCalories).toBe(480)
    expect(r.totalProtein).toBe(19.8)
    expect(r.servings).toBe(2)
    await app.close()
  })

  it('400s a recipe with no ingredients', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/nutrition/recipes',
      payload: { name: 'Empty', servings: 1, ingredients: [] },
    })
    expect(res.statusCode).toBe(400)
    await app.close()
  })
})

describe('recent foods (derived from diary)', () => {
  it('dedups foods by name+brand across recent days, newest first', async () => {
    nutritionLogDay.findMany.mockResolvedValue([
      {
        payload: {
          entries: [
            { food: { id: 'a', name: 'Egg', brand: '', caloriesPer100g: 155, proteinPer100g: 13, carbsPer100g: 1, fatPer100g: 11 } },
            { food: { id: 'a', name: 'Egg', brand: '', caloriesPer100g: 155, proteinPer100g: 13, carbsPer100g: 1, fatPer100g: 11 } },
            { food: { id: 'b', name: 'Rice', brand: null, caloriesPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3 } },
          ],
        },
      },
    ])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/recent-foods?limit=10' })
    expect(res.statusCode).toBe(200)
    const data = res.json().data
    expect(data).toHaveLength(2)
    expect(data.map((f: { name: string }) => f.name)).toEqual(['Egg', 'Rice'])
    await app.close()
  })

  it('respects the limit', async () => {
    nutritionLogDay.findMany.mockResolvedValue([
      {
        payload: {
          entries: [
            { food: { name: 'A', caloriesPer100g: 1, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 0 } },
            { food: { name: 'B', caloriesPer100g: 1, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 0 } },
            { food: { name: 'C', caloriesPer100g: 1, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 0 } },
          ],
        },
      },
    ])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/nutrition/recent-foods?limit=2' })
    expect(res.json().data).toHaveLength(2)
    await app.close()
  })
})
