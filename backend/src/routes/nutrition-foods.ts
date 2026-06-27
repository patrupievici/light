import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'

/**
 * MyFitnessPal-parity food features: custom foods, favorites, recipes, and a
 * derived "recent foods" list. Mounted under /v1/nutrition alongside the main
 * nutrition routes. Macros are canonical per-100g to match the diary FoodItem
 * shape. Recipe apply / quick-add / copy-day are client-side over the diary API.
 */

const Macros = {
  caloriesPer100g: z.number().min(0).max(2000),
  proteinPer100g: z.number().min(0).max(200),
  carbsPer100g: z.number().min(0).max(200),
  fatPer100g: z.number().min(0).max(200),
}

const CustomFoodSchema = z.object({
  name: z.string().min(1).max(120),
  brand: z.string().max(120).nullable().optional(),
  ...Macros,
  servingGrams: z.number().min(1).max(5000).nullable().optional(),
  servingLabel: z.string().max(60).nullable().optional(),
})

const FavoriteSchema = z.object({
  foodId: z.string().min(1).max(120),
  name: z.string().min(1).max(120),
  brand: z.string().max(120).nullable().optional(),
  ...Macros,
  servingGrams: z.number().min(1).max(5000).nullable().optional(),
})

const IngredientSchema = z.object({
  name: z.string().min(1).max(120),
  grams: z.number().min(0.1).max(5000),
  foodId: z.string().max(120).nullable().optional(),
  ...Macros,
})

const RecipeSchema = z.object({
  name: z.string().min(1).max(120),
  servings: z.number().int().min(1).max(50),
  ingredients: z.array(IngredientSchema).min(1).max(50),
})

type Ingredient = z.infer<typeof IngredientSchema>

function computeRecipeTotals(ingredients: Ingredient[]) {
  let cal = 0
  let p = 0
  let c = 0
  let f = 0
  for (const i of ingredients) {
    const k = i.grams / 100
    cal += i.caloriesPer100g * k
    p += i.proteinPer100g * k
    c += i.carbsPer100g * k
    f += i.fatPer100g * k
  }
  const r = (n: number) => Math.round(n * 10) / 10
  return { totalCalories: r(cal), totalProtein: r(p), totalCarbs: r(c), totalFat: r(f) }
}

function badRequest(reply: import('fastify').FastifyReply, requestId: string, details: unknown) {
  return reply.code(400).send({ error: 'VALIDATION_ERROR', message: 'Date invalide', requestId, details })
}

function serializeCustomFood(f: {
  id: string
  name: string
  brand: string | null
  caloriesPer100g: number
  proteinPer100g: number
  carbsPer100g: number
  fatPer100g: number
  servingGrams: number | null
  servingLabel: string | null
}) {
  return {
    id: `custom:${f.id}`,
    customId: f.id,
    name: f.name,
    brand: f.brand,
    caloriesPer100g: f.caloriesPer100g,
    proteinPer100g: f.proteinPer100g,
    carbsPer100g: f.carbsPer100g,
    fatPer100g: f.fatPer100g,
    servingGrams: f.servingGrams,
    servingLabel: f.servingLabel,
  }
}

export async function nutritionFoodsRoutes(app: FastifyInstance) {
  // ── Custom foods ───────────────────────────────────────────────────────────
  app.get('/custom-foods', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const rows = await prisma.userCustomFood.findMany({ where: { userId }, orderBy: { updatedAt: 'desc' } })
    return reply.send({ data: rows.map(serializeCustomFood) })
  })

  app.post('/custom-foods', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CustomFoodSchema.safeParse(request.body)
    if (!parsed.success) return badRequest(reply, request.id, parsed.error.flatten())
    const d = parsed.data
    const row = await prisma.userCustomFood.create({
      data: {
        userId,
        name: d.name.trim(),
        brand: d.brand?.trim() || null,
        caloriesPer100g: d.caloriesPer100g,
        proteinPer100g: d.proteinPer100g,
        carbsPer100g: d.carbsPer100g,
        fatPer100g: d.fatPer100g,
        servingGrams: d.servingGrams ?? null,
        servingLabel: d.servingLabel?.trim() || null,
      },
    })
    return reply.code(201).send({ food: serializeCustomFood(row) })
  })

  app.put('/custom-foods/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const parsed = CustomFoodSchema.safeParse(request.body)
    if (!parsed.success) return badRequest(reply, request.id, parsed.error.flatten())
    const existing = await prisma.userCustomFood.findFirst({ where: { id, userId } })
    if (!existing) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Aliment negăsit', requestId: request.id })
    const d = parsed.data
    const row = await prisma.userCustomFood.update({
      where: { id },
      data: {
        name: d.name.trim(),
        brand: d.brand?.trim() || null,
        caloriesPer100g: d.caloriesPer100g,
        proteinPer100g: d.proteinPer100g,
        carbsPer100g: d.carbsPer100g,
        fatPer100g: d.fatPer100g,
        servingGrams: d.servingGrams ?? null,
        servingLabel: d.servingLabel?.trim() || null,
      },
    })
    return reply.send({ food: serializeCustomFood(row) })
  })

  app.delete('/custom-foods/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const existing = await prisma.userCustomFood.findFirst({ where: { id, userId } })
    if (!existing) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Aliment negăsit', requestId: request.id })
    await prisma.userCustomFood.delete({ where: { id } })
    return reply.code(204).send()
  })

  // ── Favorite foods ─────────────────────────────────────────────────────────
  app.get('/favorite-foods', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const rows = await prisma.userFavoriteFood.findMany({ where: { userId }, orderBy: { createdAt: 'desc' } })
    return reply.send({
      data: rows.map((r) => ({
        id: r.foodId,
        name: r.name,
        brand: r.brand,
        caloriesPer100g: r.caloriesPer100g,
        proteinPer100g: r.proteinPer100g,
        carbsPer100g: r.carbsPer100g,
        fatPer100g: r.fatPer100g,
        servingGrams: r.servingGrams,
      })),
    })
  })

  app.post('/favorite-foods', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = FavoriteSchema.safeParse(request.body)
    if (!parsed.success) return badRequest(reply, request.id, parsed.error.flatten())
    const d = parsed.data
    // Idempotent star: upsert on (userId, foodId).
    await prisma.userFavoriteFood.upsert({
      where: { userId_foodId: { userId, foodId: d.foodId } },
      create: {
        userId,
        foodId: d.foodId,
        name: d.name.trim(),
        brand: d.brand?.trim() || null,
        caloriesPer100g: d.caloriesPer100g,
        proteinPer100g: d.proteinPer100g,
        carbsPer100g: d.carbsPer100g,
        fatPer100g: d.fatPer100g,
        servingGrams: d.servingGrams ?? null,
      },
      update: {
        name: d.name.trim(),
        brand: d.brand?.trim() || null,
        caloriesPer100g: d.caloriesPer100g,
        proteinPer100g: d.proteinPer100g,
        carbsPer100g: d.carbsPer100g,
        fatPer100g: d.fatPer100g,
        servingGrams: d.servingGrams ?? null,
      },
    })
    return reply.code(201).send({ ok: true })
  })

  app.delete('/favorite-foods/:foodId', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { foodId } = request.params as { foodId: string }
    await prisma.userFavoriteFood.deleteMany({ where: { userId, foodId } })
    return reply.code(204).send()
  })

  // ── Recipes ────────────────────────────────────────────────────────────────
  app.get('/recipes', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const rows = await prisma.userRecipe.findMany({ where: { userId }, orderBy: { updatedAt: 'desc' } })
    return reply.send({ data: rows })
  })

  app.post('/recipes', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = RecipeSchema.safeParse(request.body)
    if (!parsed.success) return badRequest(reply, request.id, parsed.error.flatten())
    const d = parsed.data
    const totals = computeRecipeTotals(d.ingredients)
    const row = await prisma.userRecipe.create({
      data: {
        userId,
        name: d.name.trim(),
        servings: d.servings,
        ingredientsJson: d.ingredients,
        ...totals,
      },
    })
    return reply.code(201).send({ recipe: row })
  })

  app.put('/recipes/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const parsed = RecipeSchema.safeParse(request.body)
    if (!parsed.success) return badRequest(reply, request.id, parsed.error.flatten())
    const existing = await prisma.userRecipe.findFirst({ where: { id, userId } })
    if (!existing) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Rețetă negăsită', requestId: request.id })
    const d = parsed.data
    const totals = computeRecipeTotals(d.ingredients)
    const row = await prisma.userRecipe.update({
      where: { id },
      data: { name: d.name.trim(), servings: d.servings, ingredientsJson: d.ingredients, ...totals },
    })
    return reply.send({ recipe: row })
  })

  app.delete('/recipes/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const existing = await prisma.userRecipe.findFirst({ where: { id, userId } })
    if (!existing) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Rețetă negăsită', requestId: request.id })
    await prisma.userRecipe.delete({ where: { id } })
    return reply.code(204).send()
  })

  // ── Recent foods (derived from diary history, no table) ─────────────────────
  app.get('/recent-foods', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { limit?: string }
    const limit = Math.min(50, Math.max(1, parseInt(q.limit ?? '20', 10) || 20))

    const days = await prisma.nutritionLogDay.findMany({
      where: { userId },
      orderBy: { day: 'desc' },
      take: 30,
      select: { payload: true },
    })

    type FoodLike = {
      id?: string
      name?: string
      brand?: string | null
      caloriesPer100g?: number
      proteinPer100g?: number
      carbsPer100g?: number
      fatPer100g?: number
      servingGrams?: number | null
    }
    const seen = new Set<string>()
    const out: Array<Record<string, unknown>> = []
    for (const d of days) {
      const payload = d.payload as { entries?: Array<{ food?: FoodLike }> } | null
      const entries = Array.isArray(payload?.entries) ? payload!.entries! : []
      for (const e of entries) {
        const food = e?.food
        if (!food || typeof food.name !== 'string') continue
        const key = `${food.name.toLowerCase()}|${(food.brand ?? '').toLowerCase()}`
        if (seen.has(key)) continue
        seen.add(key)
        out.push({
          id: food.id ?? key,
          name: food.name,
          brand: food.brand ?? null,
          caloriesPer100g: food.caloriesPer100g ?? 0,
          proteinPer100g: food.proteinPer100g ?? 0,
          carbsPer100g: food.carbsPer100g ?? 0,
          fatPer100g: food.fatPer100g ?? 0,
          servingGrams: food.servingGrams ?? null,
        })
        if (out.length >= limit) break
      }
      if (out.length >= limit) break
    }
    return reply.send({ data: out })
  })
}
