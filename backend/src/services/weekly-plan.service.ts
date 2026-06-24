import type { FastifyBaseLogger } from 'fastify'
import { Prisma, type UserProfile, type UserTrainingProfile } from '@prisma/client'

import { prisma } from '../lib/prisma'
import { normalizeEquipmentTagsForAi } from '../lib/equipment-for-ai'
import { resolveExerciseByName } from '../lib/exercise-resolver'
import { getRecentProgression, formatProgressionForPrompt } from '../lib/progression-context'
import {
  computeProgressiveLoads,
  applyBlockDeload,
  isDeloadWeek,
  DEFAULT_DELOAD_CADENCE,
  type ProgressionLevel,
} from '../lib/progressive-overload'
import { normalizeProgressionScheme, type Prescription } from '../lib/progression-schemes'
import { generateWarmupSets } from '../lib/warmup'
import { deepSeekChat } from './deepseek.service'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../ai/app-context'
import { generateGoalAdvice, parseJsonFromModel, sanitizePromptInput } from '../lib/ai-helpers'
import { buildGoalGuidance } from '../lib/goal-guidance'

export type WeeklyPlanOpts = {
  goal?: 'fat_loss' | 'maintenance' | 'hypertrophy' | 'strength' | 'calisthenics' | 'explosive_power'
  goalText?: string
  daysPerWeek?: number
  sessionMinutes?: number
  equipment?: string[]
  /** Default true. Set false to skip writing dailyTargets to userProfile. */
  applyDailyTargets?: boolean
  /** Default true. Set false to ALSO generate goalAdvice — slower (extra AI call). */
  skipGoalAdvice?: boolean
  /** ISO date (YYYY-MM-DD) used as `weekStart`. Defaults to today (UTC). */
  weekStart?: string
  /** When set, the user is *changing* their goal — the prompt knows about
   *  the previous goal so the AI can produce a `goalChangeRationale` field
   *  explaining what shifted in the plan. */
  previousGoalText?: string
  /** Dietary restrictions/preferences from onboarding (e.g. "vegan",
   *  "gluten-free", "no nuts"). Injected into the nutrition prompt so the
   *  meal targets + notes respect them. */
  dietaryRestrictions?: string[]
}

export type WeeklyPlanResult = {
  weekStart: string
  plan: {
    weekPlan: any[]
    dailyTargets: { calories: number; proteinG: number; carbsG: number; fatG: number } | null
    dailyCalorieTarget: number
    weeklyCalorieTarget: number
    notes: string[]
  }
  goalAdvice: string
  appliedDailyTargets: { calories: number; proteinG: number; carbsG: number; fatG: number } | null
  plannedWorkouts: Array<Record<string, unknown>>
  model: string
  /** Set when `previousGoalText` was provided and the AI returned a non-empty
   *  rationale explaining the shift between old and new plan. Used by the
   *  Goal Evolution flow to show a before/after summary. */
  goalChangeRationale?: string
}

export class WeeklyPlanError extends Error {
  constructor(
    public code: 'AI_DISABLED' | 'PROFILE_INCOMPLETE' | 'AI_UPSTREAM',
    message: string,
  ) {
    super(message)
  }
}

/**
 * Generate a 7-day workout + nutrition plan for one user and persist it
 * (planned_workouts + nutrition_plan_days + userProfile dailyTargets).
 *
 * Used by both `POST /v1/ai/weekly-plan` (interactive) and the weekly cron
 * (`weekly-plan-cron.service.ts`) that re-fills the plan every Monday so
 * users don't end up with empty calendars after week 1.
 */
export async function generateAndPersistWeeklyPlan(
  userId: string,
  opts: WeeklyPlanOpts,
  log?: FastifyBaseLogger,
): Promise<WeeklyPlanResult> {
  if (!process.env.DEEPSEEK_API_KEY) throw new WeeklyPlanError('AI_DISABLED', 'DEEPSEEK_API_KEY not set')

  const [profile, trainingProfile] = await Promise.all([
    prisma.userProfile.findUnique({ where: { userId } }),
    prisma.userTrainingProfile.findUnique({ where: { userId } }),
  ])
  if (!profile || !trainingProfile) {
    throw new WeeklyPlanError('PROFILE_INCOMPLETE', 'Profile not initialized')
  }

  const progression = await getRecentProgression(userId)
  const progressionBlock = formatProgressionForPrompt(progression)

  // Assemble the LLM prompt + derived flags. Extracted into a pure, exported
  // function so the "goal → prompt" relevance contract can be unit-tested
  // without a DB or a live LLM (see weekly-plan.service.test.ts).
  const { prompt, effectiveGoalText, goalEnum, isGoalChange, shouldApplyTargets } =
    buildWeeklyPlanInputs({ profile, trainingProfile, opts, progressionBlock })

  let out
  try {
    out = await deepSeekChat(
      [
        {
          role: 'system',
          content: `${ZVELT_APP_CONTEXT_FOR_AI}

You return strict JSON only, no markdown. No explanations.

For THIS endpoint, ALL human-readable strings in the JSON MUST be English only (never Romanian; do not mirror the user's goal language in structured fields).`,
        },
        { role: 'user', content: prompt },
      ],
      { maxTokens: 3000, temperature: 0.3 },
    )
  } catch (e: any) {
    log?.warn({ err: String(e?.message ?? e), userId }, 'weekly-plan AI call failed')
    throw new WeeklyPlanError('AI_UPSTREAM', e?.message ?? 'AI upstream error')
  }

  const json = parseJsonFromModel<{
    weekPlan: Array<{
      dayOfWeek: number
      date: string
      workout?: {
        name: string
        focus: string
        durationMinutes: number
        exercises: Array<{
          name: string
          sets: number
          reps: number
          restSeconds: number
          notes?: string
          /** One short sentence explaining why this exercise specifically
           *  fits the user's stated goal. Generated by the AI alongside the
           *  pick so the UI can show "why" without a second API call. */
          whyThisExercise?: string
        }>
      }
      nutrition: { targetCalories: number; proteinG: number; carbsG: number; fatG: number }
    }>
    dailyTargets?: { calories: number; proteinG: number; carbsG: number; fatG: number }
    dailyCalorieTarget: number
    weeklyCalorieTarget: number
    notes: string[]
    /** Only present when previousGoalText was supplied. */
    goalChangeRationale?: string
  }>(out.text)

  if (!json || !json.weekPlan || !Array.isArray(json.weekPlan)) {
    throw new WeeklyPlanError('AI_UPSTREAM', 'Invalid plan structure from model')
  }

  // Resolve every unique exercise name once.
  const uniqueNames = new Set<string>()
  for (const dp of json.weekPlan) {
    if (dp.workout?.exercises) {
      for (const ex of dp.workout.exercises) if (ex.name) uniqueNames.add(ex.name)
    }
  }
  const resolved = new Map<string, { id: string; name: string } | null>()
  await Promise.all(
    Array.from(uniqueNames).map(async (n) => {
      resolved.set(n, await resolveExerciseByName(n))
    }),
  )

  // Pull classification metadata for the resolved exercises so we can attach a
  // warm-up ramp only to weighted compound lifts (see lib/warmup.ts). Read-only,
  // existing columns only — no schema change.
  const resolvedIds = Array.from(
    new Set(
      Array.from(resolved.values())
        .map((r) => r?.id)
        .filter((x): x is string => !!x),
    ),
  )
  const exerciseMeta = new Map<
    string,
    { movementPattern: string; rankModel: string; category: string }
  >()
  if (resolvedIds.length > 0) {
    const metaRows = await prisma.exercise.findMany({
      where: { id: { in: resolvedIds } },
      select: { id: true, movementPattern: true, rankModel: true, category: true },
    })
    for (const m of metaRows) {
      exerciseMeta.set(m.id, {
        movementPattern: m.movementPattern,
        rankModel: m.rankModel,
        category: m.category,
      })
    }
  }

  const startDate = opts.weekStart ? new Date(`${opts.weekStart}T00:00:00Z`) : new Date()
  const weekStartStr = (opts.weekStart ?? startDate.toISOString().split('T')[0]) as string

  // Program-start anchor for the block-deload cadence. We have no dedicated
  // "program started" column, so derive it from existing signals (no schema
  // change): the user's earliest logged workout, falling back to their earliest
  // planned workout. The whole-week distance between that anchor and this plan's
  // weekStart gives a rolling week index that drives the periodization cadence.
  const [firstWorkout, firstPlanned] = await Promise.all([
    prisma.workout.findFirst({
      where: { userId, status: { in: ['completed', 'posted'] } },
      orderBy: { startedAt: 'asc' },
      select: { startedAt: true },
    }),
    prisma.plannedWorkout.findFirst({
      where: { userId },
      orderBy: { weekStart: 'asc' },
      select: { weekStart: true },
    }),
  ])
  const anchorDate =
    firstWorkout?.startedAt ??
    (firstPlanned?.weekStart ? new Date(`${firstPlanned.weekStart}T00:00:00Z`) : startDate)
  // True only when we have ≥1 prior signal — a fresh user (anchor == this week)
  // never opens their very first program on a deload.
  const isDeload = isDeloadWeek({ start: anchorDate, current: startDate }, DEFAULT_DELOAD_CADENCE)

  // NOTE: nutritionPlanDay is NOT deleted here. Its unique key is (userId, day)
  // — not weekStart — so deleting by weekStart left stale rows that made the
  // create() below throw P2002. The per-day upsert further down overwrites the
  // 7 days idempotently. Only the pending planned workouts are cleared.
  await prisma.$transaction([
    prisma.plannedWorkout.deleteMany({ where: { userId, weekStart: weekStartStr, status: 'pending' } }),
  ])

  const level: ProgressionLevel =
    (trainingProfile.trainingLevel as ProgressionLevel | null) === 'advanced'
      ? 'advanced'
      : (trainingProfile.trainingLevel as ProgressionLevel | null) === 'beginner'
        ? 'beginner'
        : 'intermediate'

  // Configurable progression scheme (default 'auto' = current RPE autoregulation,
  // behavior-preserving). Non-auto schemes additionally run an adherence gate
  // that compares what the user was LAST prescribed against what they logged, so
  // we seed a per-exercise prescription map from their most recent planned slots.
  const progressionScheme = normalizeProgressionScheme(
    (trainingProfile as { progressionScheme?: unknown }).progressionScheme,
  )
  const lastPrescriptionByEx =
    progressionScheme === 'auto'
      ? new Map<string, Prescription>()
      : await buildLastPrescriptionMap(userId)

  const plannedWorkoutsOut: Array<Record<string, unknown>> = []

  for (const dayPlan of json.weekPlan) {
    const workoutDate = new Date(startDate)
    workoutDate.setUTCDate(startDate.getUTCDate() + (dayPlan.dayOfWeek - 1))
    const dayStr = workoutDate.toISOString().split('T')[0]

    const hasWorkout =
      !!dayPlan.workout && Array.isArray(dayPlan.workout.exercises) && dayPlan.workout.exercises.length > 0

    if (hasWorkout) {
      const baseExercises = dayPlan.workout!.exercises.map((ex) => ({
        name: ex.name,
        sets: Number(ex.sets) || 3,
        reps: Number(ex.reps) || 8,
        restSeconds: Number(ex.restSeconds) || 90,
        notes: ex.notes ?? undefined,
        whyThisExercise: ex.whyThisExercise?.trim() || undefined,
        exerciseId: resolved.get(ex.name)?.id ?? null,
      }))

      const loadDecisions = await computeProgressiveLoads(
        userId,
        baseExercises.map((e) => ({
          exerciseId: e.exerciseId,
          prescribedReps: e.reps,
          lastPrescription: e.exerciseId ? lastPrescriptionByEx.get(e.exerciseId) ?? null : null,
        })),
        level,
        { progressionScheme },
      )
      const exercises = baseExercises.map((e, i) => {
        // Block-deload transform: on a scheduled deload week this backs the load
        // off ~−12%, trims a working set, and forces source='deload' so the
        // normal progression bump is suppressed (behavior-preserving otherwise).
        const deloaded = applyBlockDeload(
          {
            suggestedWeightKg: loadDecisions[i].suggestedWeightKg,
            sets: e.sets,
            source: loadDecisions[i].source,
            reason: loadDecisions[i].reason,
          },
          isDeload,
        )
        const suggestedWeightKg = deloaded.suggestedWeightKg
        const meta = e.exerciseId ? exerciseMeta.get(e.exerciseId) : undefined
        // Warm-up ramp: weighted compound lifts only, and only when we actually
        // have a working weight to ramp toward. Helper returns [] otherwise.
        const warmups =
          meta && suggestedWeightKg != null
            ? generateWarmupSets(suggestedWeightKg, {
                movementPattern: meta.movementPattern,
                rankModel: meta.rankModel,
                category: meta.category,
              })
            : []
        return {
          ...e,
          sets: deloaded.sets,
          reps: loadDecisions[i].suggestedReps,
          suggestedWeightKg,
          loadSource: deloaded.source,
          loadReason: deloaded.reason,
          ...(warmups.length > 0 ? { warmups } : {}),
        }
      })

      const createdWorkout = await prisma.plannedWorkout.create({
        data: {
          userId,
          day: dayStr,
          weekStart: weekStartStr,
          title: dayPlan.workout!.name,
          kind: 'gym',
          status: 'pending',
          exercisesJson: exercises as unknown as Prisma.InputJsonValue,
          notes: dayPlan.workout!.focus ?? null,
        },
      })

      plannedWorkoutsOut.push({
        id: createdWorkout.id,
        date: dayStr,
        name: createdWorkout.title,
        kind: 'gym',
        status: 'pending',
        isRestDay: false,
        focus: dayPlan.workout!.focus,
        exercises,
        nutrition: dayPlan.nutrition,
      })
    } else {
      plannedWorkoutsOut.push({
        id: null,
        date: dayStr,
        name: 'Rest Day',
        kind: 'rest',
        status: 'completed',
        isRestDay: true,
        exercises: [],
        nutrition: dayPlan.nutrition,
      })
    }

    const nutritionData = {
      userId,
      day: dayStr,
      weekStart: weekStartStr,
      goal: goalEnum,
      calories: dayPlan.nutrition.targetCalories,
      proteinG: dayPlan.nutrition.proteinG,
      carbsG: dayPlan.nutrition.carbsG,
      fatG: dayPlan.nutrition.fatG,
      waterMl: 2500,
    }
    await prisma.nutritionPlanDay.upsert({
      where: { userId_day: { userId, day: dayStr } },
      create: nutritionData,
      update: nutritionData,
    })
  }

  let appliedDailyTargets: { calories: number; proteinG: number; carbsG: number; fatG: number } | null = null
  if (shouldApplyTargets) {
    appliedDailyTargets = computeAppliedDailyTargets(json)
    if (appliedDailyTargets) {
      await prisma.userProfile.update({
        where: { userId },
        data: {
          dailyCalories: Math.max(800, Math.min(20000, Math.round(appliedDailyTargets.calories))),
          dailyProtein: Math.max(0, Math.min(1000, appliedDailyTargets.proteinG)),
          dailyCarbs: Math.max(0, Math.min(2000, appliedDailyTargets.carbsG)),
          dailyFat: Math.max(0, Math.min(1000, appliedDailyTargets.fatG)),
        },
      })
    }
  }

  // Persist the goalText the user submitted so future calls (workout
  // suggestion, next week's plan, profile reads) see the same narrative —
  // otherwise the AI prompt for tomorrow's suggestion falls back to the
  // generic enum and the user wonders why exercises don't match what they
  // said. Idempotent — same string is a no-op on Postgres.
  if (opts.goalText && opts.goalText.trim().length > 0) {
    const trimmed = opts.goalText.trim().slice(0, 2000)
    if (trimmed !== (trainingProfile.onboardingGoalText ?? '').trim()) {
      await prisma.userTrainingProfile.update({
        where: { userId },
        data: { onboardingGoalText: trimmed },
      }).catch(() => {})
    }
  }

  let goalAdvice = ''
  if (effectiveGoalText && !opts.skipGoalAdvice) {
    goalAdvice = await generateGoalAdvice(effectiveGoalText, String(trainingProfile.gymExperience ?? ''))
    if (goalAdvice) {
      await prisma.userTrainingProfile.update({
        where: { userId },
        data: { goalAdviceText: goalAdvice },
      }).catch(() => {})
    }
  }

  const goalChangeRationale = isGoalChange
    ? (json.goalChangeRationale ?? '').trim().slice(0, 600)
    : ''

  return {
    weekStart: weekStartStr,
    plan: {
      weekPlan: json.weekPlan,
      dailyTargets: json.dailyTargets ?? appliedDailyTargets,
      dailyCalorieTarget: json.dailyCalorieTarget,
      weeklyCalorieTarget: json.weeklyCalorieTarget,
      notes: json.notes,
    },
    goalAdvice,
    appliedDailyTargets,
    plannedWorkouts: plannedWorkoutsOut,
    model: out.model,
    ...(goalChangeRationale.length > 0 ? { goalChangeRationale } : {}),
  }
}

function computeAppliedDailyTargets(json: {
  weekPlan: Array<{
    workout?: { exercises?: unknown[] }
    nutrition: { targetCalories: number; proteinG: number; carbsG: number; fatG: number }
  }>
  dailyTargets?: { calories: number; proteinG: number; carbsG: number; fatG: number }
}) {
  if (json.dailyTargets) return json.dailyTargets
  const trainingDays = json.weekPlan.filter((d) => d.workout && (d.workout.exercises?.length ?? 0) > 0)
  if (trainingDays.length === 0) return null
  const avg = (k: 'targetCalories' | 'proteinG' | 'carbsG' | 'fatG') =>
    Math.round(trainingDays.reduce((s, d) => s + (d.nutrition[k] || 0), 0) / trainingDays.length)
  return {
    calories: avg('targetCalories'),
    proteinG: avg('proteinG'),
    carbsG: avg('carbsG'),
    fatG: avg('fatG'),
  }
}

/**
 * Build a per-exercise map of the user's most recent prescription, read from
 * their latest planned-workout slots (exercisesJson). Used by the non-`auto`
 * progression schemes' adherence gate to decide whether the user MET what they
 * were last told to do before adding load.
 *
 * Reads existing columns only (no schema change). The slot's `reps` is the
 * target reps and `suggestedWeightKg` the target load; `targetRpe` is read when
 * present but is absent in today's plans (gate treats null RPE as permissive).
 * Most-recent wins (we iterate newest-first and keep the first hit per exercise).
 */
async function buildLastPrescriptionMap(userId: string): Promise<Map<string, Prescription>> {
  const recent = await prisma.plannedWorkout.findMany({
    where: { userId, kind: 'gym' },
    orderBy: { day: 'desc' },
    take: 30,
    select: { exercisesJson: true },
  })

  const byEx = new Map<string, Prescription>()
  for (const row of recent) {
    const list = Array.isArray(row.exercisesJson) ? row.exercisesJson : []
    for (const raw of list) {
      if (!raw || typeof raw !== 'object') continue
      const slot = raw as Record<string, unknown>
      const exerciseId = typeof slot.exerciseId === 'string' ? slot.exerciseId : null
      if (!exerciseId || byEx.has(exerciseId)) continue
      const targetReps = Number(slot.reps)
      if (!Number.isFinite(targetReps) || targetReps <= 0) continue
      const wRaw = Number(slot.suggestedWeightKg)
      const targetWeightKg = Number.isFinite(wRaw) && wRaw > 0 ? wRaw : null
      const rpeRaw = Number(slot.targetRpe)
      const targetRpe = Number.isFinite(rpeRaw) && rpeRaw > 0 ? rpeRaw : null
      byEx.set(exerciseId, { targetReps, targetRpe, targetWeightKg })
    }
  }
  return byEx
}

/** Minimal profile shape the prompt assembler reads — loose on purpose so
 *  tests can pass plain objects without Prisma's Decimal/Json types. */
export type PromptProfileInput = {
  bodyweightKg: unknown
  heightCm: unknown
  sex: string | null
  birthYear: number | null
}
export type PromptTrainingProfileInput = {
  onboardingGoalText: string | null
  primaryGoal: string | null
  equipment: unknown
  daysPerWeek: number | null
  sessionMinutes: number | null
  trainingLevel: string | null
}

export type WeeklyPlanInputs = {
  prompt: string
  effectiveGoalText: string
  goalEnum: string
  isGoalChange: boolean
  shouldApplyTargets: boolean
}

/**
 * Pure assembly of the weekly-plan LLM prompt + the flags the caller needs
 * downstream. No DB, no network — everything is derived from the passed
 * profile/trainingProfile/opts, so this is the unit under test for the core
 * "the user's goal actually reaches the planner" contract.
 *
 * Priority order baked into the prompt: the user's free-text goal is TOP
 * priority; the `goal` enum is only a hint. Goal-specific guidance
 * (plyometrics for dunk, etc.) and dietary restrictions are injected here too.
 */
export function buildWeeklyPlanInputs(args: {
  profile: PromptProfileInput
  trainingProfile: PromptTrainingProfileInput
  opts: WeeklyPlanOpts
  progressionBlock: string
}): WeeklyPlanInputs {
  const { profile, trainingProfile, opts, progressionBlock } = args
  const { goal, goalText, daysPerWeek, sessionMinutes, equipment } = opts
  const shouldApplyTargets = opts.applyDailyTargets !== false

  const equipForPrompt = equipment ?? trainingProfile.equipment
  const equipArr = Array.isArray(equipForPrompt)
    ? (equipForPrompt as unknown[]).filter((x): x is string => typeof x === 'string')
    : []
  const equipmentList = normalizeEquipmentTagsForAi(equipArr)
  const bodyweightForPrompt =
    profile.bodyweightKg != null && String(profile.bodyweightKg).length > 0
      ? Number(profile.bodyweightKg)
      : 70

  const effectiveGoalText = (goalText ?? trainingProfile.onboardingGoalText ?? '').trim().slice(0, 1500)
  const goalEnum = goal ?? trainingProfile.primaryGoal ?? 'maintenance'
  const goalBlock = effectiveGoalText
    ? `USER'S GOAL (their own words — top priority):\n"${sanitizePromptInput(effectiveGoalText)}"\nGoal category (hint): ${goalEnum}`
    : `Goal: ${goalEnum}`

  // Goal-change context: when the user is switching goals (Goal Evolution
  // flow), we ask the AI to also produce a 1-3 sentence narrative explaining
  // what shifted in the plan. Triggers only when previousGoalText differs
  // from the new effective goal text — silent no-op otherwise so we don't
  // burn tokens on identical strings.
  const prevGoalText = (opts.previousGoalText ?? '').trim().slice(0, 1500)
  const isGoalChange =
    prevGoalText.length > 0 &&
    effectiveGoalText.length > 0 &&
    prevGoalText.toLowerCase() !== effectiveGoalText.toLowerCase()
  const goalChangeBlock = isGoalChange
    ? `\nPREVIOUS GOAL (what they had before this update):\n"${sanitizePromptInput(prevGoalText)}"\nSince the goal is changing, you MUST add a field "goalChangeRationale" to your response (1-3 sentences, max 60 words) that explains in plain English what shifted in the plan compared to a plan built for the previous goal — reference specific exercises or focus areas where useful.`
    : ''

  // Dietary restrictions/preferences — sanitize, cap, and dedupe so a long or
  // hostile list can't blow up the prompt or inject instructions.
  const dietary = Array.isArray(opts.dietaryRestrictions)
    ? Array.from(
        new Set(
          opts.dietaryRestrictions
            .filter((x): x is string => typeof x === 'string')
            .map((x) => sanitizePromptInput(x.trim()).slice(0, 40))
            .filter((x) => x.length > 0),
        ),
      ).slice(0, 12)
    : []

  const prompt = buildWeeklyPlanPrompt({
    goalBlock: goalBlock + goalChangeBlock,
    progressionBlock,
    goalGuidance: buildGoalGuidance(effectiveGoalText),
    daysPerWeek: daysPerWeek ?? trainingProfile.daysPerWeek ?? 4,
    sessionMinutes: sessionMinutes ?? trainingProfile.sessionMinutes ?? 60,
    trainingLevel: trainingProfile.trainingLevel ?? 'intermediate',
    equipmentList,
    bodyweightKg: bodyweightForPrompt,
    heightCm: Number(profile.heightCm ?? 175),
    sex: profile.sex ?? 'male',
    age: new Date().getFullYear() - (profile.birthYear ?? 1990),
    expectGoalChangeRationale: isGoalChange,
    dietaryRestrictions: dietary,
  })

  return { prompt, effectiveGoalText, goalEnum, isGoalChange, shouldApplyTargets }
}

function buildWeeklyPlanPrompt(p: {
  goalBlock: string
  progressionBlock: string
  goalGuidance: string
  daysPerWeek: number
  sessionMinutes: number
  trainingLevel: string
  equipmentList: string[]
  bodyweightKg: number
  heightCm: number
  sex: string
  age: number
  /** When true, the response shape includes a top-level "goalChangeRationale"
   *  string field — triggered by the Goal Evolution flow (previousGoalText set). */
  expectGoalChangeRationale: boolean
  /** Sanitized dietary restrictions/preferences — empty when none. */
  dietaryRestrictions: string[]
}): string {
  const dietaryBlock = p.dietaryRestrictions.length > 0
    ? `\n- Dietary restrictions: ${p.dietaryRestrictions.join(', ')}`
    : ''
  return `You are a fitness AI planner for the Zvelt mobile app.
Create a 7-day workout and nutrition plan tailored to the user's own goal.
Return strict JSON only with this EXACT structure:
{
  "weekPlan": [
    {
      "dayOfWeek": 1-7,
      "date": "YYYY-MM-DD",
      "workout": {
        "name": "string",
        "focus": "string",
        "durationMinutes": number,
        "exercises": [
          {
            "name": "string",
            "sets": number,
            "reps": number,
            "restSeconds": number,
            "notes": "string (form cue or modification, optional)",
            "whyThisExercise": "TWO short sentences (max 45 words total). Sentence 1: what this exercise primarily builds — muscle/system/skill (e.g. 'Trains rate of force development through triple extension of hips, knees and ankles.'). Sentence 2: why this is the right pick for the user's specific goal — reference the goal explicitly (e.g. 'For your dunk goal, this trains the exact force vector your jump needs.'). Concrete physiology language, no generic filler."
          }
        ]
      },
      "nutrition": { "targetCalories": number, "proteinG": number, "carbsG": number, "fatG": number }
    }
  ],
  "dailyTargets": { "calories": number, "proteinG": number, "carbsG": number, "fatG": number },
  "dailyCalorieTarget": number,
  "weeklyCalorieTarget": number,
  "notes": ["string"]${p.expectGoalChangeRationale ? `,\n  "goalChangeRationale": "string (1-3 sentences, max 60 words) — REQUIRED for this request. Explain what shifted in the plan compared to a plan built for the PREVIOUS goal. Reference concrete exercises or focus areas. No motivational filler."` : ''}
}

${p.goalBlock}
${p.progressionBlock ? `\n${p.progressionBlock}\n` : ''}${p.goalGuidance ? `${p.goalGuidance}\n` : ''}
User Profile:
- Days per week: ${p.daysPerWeek}
- Session duration: ${p.sessionMinutes} minutes
- Training level: ${p.trainingLevel}
- Equipment: ${p.equipmentList.join(', ')}
- Bodyweight: ${p.bodyweightKg} kg
- Height: ${p.heightCm} cm
- Sex: ${p.sex}
- Age: ${p.age}${dietaryBlock}

Rules:
- Make every exercise pick consistent with the USER'S GOAL above (priority over enum)
- EVERY exercise MUST have a non-empty "whyThisExercise" with TWO sentences: (1) what it builds physiologically, (2) why it fits the user's stated goal. Mandatory.
- Create workouts for the specified days, rest on other days
- Vary muscle groups each day
- Include warmup and cooldown suggestions
- "dailyTargets" must be the BASELINE daily nutrition for the user (used as profile defaults); per-day "nutrition" can vary ±100–200 kcal between training and rest days
- Calculate calories using Mifflin-St Jeor + activity multiplier; adjust for the user's goal (deficit / surplus)
- Protein: 1.6–2.2 g/kg for muscle/strength goals, 1.8–2.4 g/kg for fat loss${p.dietaryRestrictions.length > 0 ? `\n- The nutrition plan (macro targets and any food suggestions in "notes") MUST respect the user's dietary restrictions listed above — never suggest foods that violate them.` : ''}
- Keep exercises practical and specific; favor compound movements when goal is strength/hypertrophy
- Equipment: **full_commercial_gym** = use barbell/dumbbell/machine/cable exercises as appropriate. Use **only** bodyweight/calisthenics as the main load if **bodyweight_only** is listed without full gym access.
- Return EXACTLY 7 days (some can be rest days)
- **Language:** all exercise names, workout titles, focuses, suggestions, notes and every string inside "notes" MUST be **English only** (no Romanian).`
}

// Unused but kept so the type imports above stay live for editor goto-def.
export type _types = UserProfile | UserTrainingProfile
