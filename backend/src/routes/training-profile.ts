import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { normalizeEquipmentTagsForAi } from '../lib/equipment-for-ai'
import { clearWorkoutSuggestionCache } from '../services/workout-suggestion-cache.service'
import {
  parsePlateInventory,
  computePlateStack,
  DEFAULT_BARBELL_KG,
  type PlatePair,
} from '../lib/plate-calculator'

const PrimaryGoalEnum = z.enum([
  'fat_loss',
  'maintenance',
  'hypertrophy',
  'strength',
  'calisthenics',
  'explosive_power',
  'vertical_jump',
])

const SecondaryGoalEnum = z.enum([
  'mobility',
  'posture',
  'conditioning',
  'core',
  'endurance',
])

const TrainingLevelEnum = z.enum(['beginner', 'novice', 'intermediate', 'advanced'])

const SplitPreferenceEnum = z.enum([
  'full_body',
  'upper_lower',
  'push_pull_legs',
  'skill_based',
  'auto',
])

const PatchTrainingProfileSchema = z.object({
  primaryGoal: PrimaryGoalEnum.nullable().optional(),
  secondaryGoals: z.array(SecondaryGoalEnum).max(8).optional(),
  trainingLevel: TrainingLevelEnum.nullable().optional(),
  gymExperience: z.string().max(500).nullable().optional(),
  daysPerWeek: z.number().int().min(1).max(7).nullable().optional(),
  sessionMinutes: z.number().int().min(15).max(240).nullable().optional(),
  equipment: z.array(z.string().min(1).max(64)).max(32).optional(),
  injuriesLimitations: z.string().max(4000).nullable().optional(),
  splitPreference: SplitPreferenceEnum.nullable().optional(),
  onboardingCompleted: z.boolean().optional(),
  onboardingGoalText: z.string().max(2000).nullable().optional(),
  goalAdviceText: z.string().max(12000).nullable().optional(),
})

function serializeTrainingProfile(row: {
  userId: string
  primaryGoal: string | null
  secondaryGoals: unknown
  trainingLevel: string | null
  gymExperience: string | null
  daysPerWeek: number | null
  sessionMinutes: number | null
  equipment: unknown
  injuriesLimitations: string | null
  splitPreference: string | null
  onboardingCompleted: boolean
  onboardingGoalText: string | null
  goalAdviceText: string | null
  updatedAt: Date
}) {
  return {
    userId: row.userId,
    primaryGoal: row.primaryGoal,
    secondaryGoals: Array.isArray(row.secondaryGoals) ? row.secondaryGoals : [],
    trainingLevel: row.trainingLevel,
    gymExperience: row.gymExperience,
    daysPerWeek: row.daysPerWeek,
    sessionMinutes: row.sessionMinutes,
    equipment: Array.isArray(row.equipment) ? row.equipment : [],
    injuriesLimitations: row.injuriesLimitations,
    splitPreference: row.splitPreference,
    onboardingCompleted: row.onboardingCompleted,
    onboardingGoalText: row.onboardingGoalText,
    goalAdviceText: row.goalAdviceText,
    updatedAt: row.updatedAt.toISOString(),
  }
}

// A single plate denomination + how many PAIRS the user owns (one pair = one
// plate per side of the bar). Stored canonically in kg.
const PlatePairSchema = z.object({
  kg: z.number().positive().max(100),
  pairs: z.number().int().min(1).max(20),
})

const PutPlateInventorySchema = z.object({
  // Plate inventory: array of { kg, pairs }. Empty array clears it (falls back
  // to the unlimited standard set in the calculator). Capped to keep the JSON
  // column small and the greedy fill bounded.
  plateInventoryKg: z.array(PlatePairSchema).max(24),
  // Bar weight in kg. Null/omitted keeps the existing value; the calculator
  // defaults to DEFAULT_BARBELL_KG when unset.
  barbellKg: z.number().min(1).max(100).nullable().optional(),
})

function serializePlateInventory(row: { plateInventoryKg: unknown; barbellKg: number | null }) {
  const parsed = parsePlateInventory(row.plateInventoryKg) ?? []
  return {
    plateInventoryKg: parsed,
    barbellKg: row.barbellKg ?? DEFAULT_BARBELL_KG,
  }
}

async function getOrCreateTrainingProfile(userId: string) {
  let row = await prisma.userTrainingProfile.findUnique({ where: { userId } })
  if (!row) {
    row = await prisma.userTrainingProfile.create({
      data: { userId },
    })
  }

  const rawEquip = Array.isArray(row.equipment)
    ? (row.equipment as unknown[]).filter((x): x is string => typeof x === 'string')
    : []
  const normalized = normalizeEquipmentTagsForAi(rawEquip)
  if (JSON.stringify(rawEquip) !== JSON.stringify(normalized)) {
    row = await prisma.userTrainingProfile.update({
      where: { userId },
      data: { equipment: normalized },
    })
    await clearWorkoutSuggestionCache(userId)
  }

  return row
}

export async function trainingProfileRoutes(app: FastifyInstance) {
  // GET /v1/me/training-profile
  app.get('/training-profile', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const row = await getOrCreateTrainingProfile(userId)
    return reply.send({ trainingProfile: serializeTrainingProfile(row) })
  })

  // PATCH /v1/me/training-profile
  app.patch('/training-profile', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const parsed = PatchTrainingProfileSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide pentru profilul de antrenament',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const data = parsed.data
    const updatePayload: Record<string, unknown> = {}

    if (data.primaryGoal !== undefined) updatePayload.primaryGoal = data.primaryGoal
    if (data.secondaryGoals !== undefined) updatePayload.secondaryGoals = data.secondaryGoals
    if (data.trainingLevel !== undefined) updatePayload.trainingLevel = data.trainingLevel
    if (data.gymExperience !== undefined) updatePayload.gymExperience = data.gymExperience
    if (data.daysPerWeek !== undefined) updatePayload.daysPerWeek = data.daysPerWeek
    if (data.sessionMinutes !== undefined) updatePayload.sessionMinutes = data.sessionMinutes
    if (data.equipment !== undefined) {
      updatePayload.equipment = normalizeEquipmentTagsForAi(data.equipment)
    }
    if (data.injuriesLimitations !== undefined)
      updatePayload.injuriesLimitations = data.injuriesLimitations
    if (data.splitPreference !== undefined) updatePayload.splitPreference = data.splitPreference
    if (data.onboardingCompleted !== undefined)
      updatePayload.onboardingCompleted = data.onboardingCompleted
    if (data.onboardingGoalText !== undefined)
      updatePayload.onboardingGoalText = data.onboardingGoalText
    if (data.goalAdviceText !== undefined) updatePayload.goalAdviceText = data.goalAdviceText

    await getOrCreateTrainingProfile(userId)

    if (
      data.equipment !== undefined ||
      data.primaryGoal !== undefined ||
      data.trainingLevel !== undefined ||
      data.daysPerWeek !== undefined ||
      data.sessionMinutes !== undefined ||
      // Goal text drives the AI prompt — if the user rewrites it via the
      // Goal Evolution flow or onboarding, today's cached suggestion is
      // stale and the user would otherwise see yesterday's generic picks
      // until midnight UTC.
      data.onboardingGoalText !== undefined
    ) {
      await clearWorkoutSuggestionCache(userId)
    }

    const row = await prisma.userTrainingProfile.update({
      where: { userId },
      data: updatePayload as any,
    })

    return reply.send({ trainingProfile: serializeTrainingProfile(row) })
  })

  // GET /v1/me/training-profile/plate-inventory
  // The user's owned plates + bar weight for the plate calculator. Optionally
  // computes a stack for a `?targetKg=` query so the client can render the
  // nearest-achievable load without re-implementing the math.
  app.get('/training-profile/plate-inventory', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const row = await getOrCreateTrainingProfile(userId)
    const inventory = serializePlateInventory(row)

    const q = request.query as Record<string, unknown>
    const targetRaw = Number(q.targetKg)
    const stack =
      Number.isFinite(targetRaw) && targetRaw > 0
        ? computePlateStack({
            targetKg: targetRaw,
            barbellKg: row.barbellKg,
            inventory: inventory.plateInventoryKg as PlatePair[],
          })
        : null

    return reply.send({ plateInventory: inventory, ...(stack ? { stack } : {}) })
  })

  // PUT /v1/me/training-profile/plate-inventory
  app.put('/training-profile/plate-inventory', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const parsed = PutPlateInventorySchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide pentru inventarul de discuri',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    await getOrCreateTrainingProfile(userId)

    // Normalize via parsePlateInventory so what we store matches what the
    // calculator reads back (dedupe by kg, drop non-positive). Canonical kg.
    const normalized = parsePlateInventory(parsed.data.plateInventoryKg) ?? []
    const updatePayload: Record<string, unknown> = {
      plateInventoryKg: normalized as unknown,
    }
    if (parsed.data.barbellKg !== undefined) {
      updatePayload.barbellKg = parsed.data.barbellKg
    }

    const row = await prisma.userTrainingProfile.update({
      where: { userId },
      data: updatePayload as any,
    })

    return reply.send({ plateInventory: serializePlateInventory(row) })
  })
}
