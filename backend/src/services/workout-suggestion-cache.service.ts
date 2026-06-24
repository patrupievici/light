import { Prisma } from '@prisma/client'
import { prisma } from '../lib/prisma'
import type { WorkoutSuggestionResult } from './workout-generator.service'

function utcDayKey(d: Date): string {
  return d.toISOString().slice(0, 10)
}

export async function getCachedWorkoutSuggestion(
  userId: string,
): Promise<WorkoutSuggestionResult | null> {
  const row = await prisma.userTrainingProfile.findUnique({
    where: { userId },
    select: {
      workoutSuggestionCache: true,
      workoutSuggestionCachedAt: true,
    },
  })
  if (!row?.workoutSuggestionCache || !row.workoutSuggestionCachedAt) return null
  if (utcDayKey(row.workoutSuggestionCachedAt) !== utcDayKey(new Date())) return null

  const raw = row.workoutSuggestionCache
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null
  const o = raw as Record<string, unknown>
  if (!Array.isArray(o.exercises)) return null

  return raw as WorkoutSuggestionResult
}

export async function setCachedWorkoutSuggestion(
  userId: string,
  suggestion: WorkoutSuggestionResult,
): Promise<void> {
  await prisma.userTrainingProfile.upsert({
    where: { userId },
    create: {
      userId,
      workoutSuggestionCache: suggestion as object,
      workoutSuggestionCachedAt: new Date(),
    },
    update: {
      workoutSuggestionCache: suggestion as object,
      workoutSuggestionCachedAt: new Date(),
    },
  })
}

export async function clearWorkoutSuggestionCache(userId: string): Promise<void> {
  await prisma.userTrainingProfile.updateMany({
    where: { userId },
    data: {
      workoutSuggestionCache: Prisma.JsonNull,
      workoutSuggestionCachedAt: null,
    },
  })
}
