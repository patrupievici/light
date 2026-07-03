import { prisma } from '../lib/prisma'
import { normalizeEquipmentTagsForAi } from '../lib/equipment-for-ai'
import {
  exerciseFitsUserEquipment,
  exerciseMatchesPrimaryGoal,
} from '../programming/equipment-compatibility'
import { inferSportIntentFromProfile } from '../programming/sport-intent'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../ai/app-context'
import { buildGoalGuidance, detectGoalIntents, goalTagsForIntent } from '../lib/goal-guidance'
import { deepSeekChat } from './deepseek.service'
import { parseJsonFromModel } from '../lib/ai-helpers'
import type { SuggestedExercise, WorkoutSuggestionResult } from './workout-generator.service'
import { fetchLastWorkingWeights, heuristicWeightKg, roundToStep } from './workout-generator.service'
import { getRecentProgression, formatProgressionForPrompt } from '../lib/progression-context'

function parseStringArray(json: unknown): string[] {
  if (!Array.isArray(json)) return []
  return json.filter((x): x is string => typeof x === 'string')
}

type AiExercisePick = {
  exerciseId: string
  sets: number
  repRange: string
  restSeconds: number
  whyThisExercise?: string
}

type AiSessionJson = {
  title?: string
  description?: string
  exercises?: AiExercisePick[]
}

function clampSets(n: unknown): number {
  const x = typeof n === 'number' ? n : Number(n)
  if (!Number.isFinite(x)) return 3
  return Math.min(12, Math.max(1, Math.round(x)))
}

function clampRest(n: unknown): number {
  const x = typeof n === 'number' ? n : Number(n)
  if (!Number.isFinite(x)) return 90
  return Math.min(360, Math.max(30, Math.round(x)))
}

function sanitizeRepRange(s: unknown): string {
  const t = String(s ?? '').trim().slice(0, 24)
  return t.length > 0 ? t : '8–12'
}

function shuffleInPlace<T>(arr: T[]): void {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[arr[i], arr[j]] = [arr[j], arr[i]]
  }
}

/** Prefer loaded gym equipment in the AI pool when the catalog is large (no fatigueScore ordering). */
function equipmentTier(equipment: string | null | undefined): number {
  const x = (equipment ?? 'bodyweight').toLowerCase()
  if (x === 'barbell') return 0
  if (x === 'dumbbell') return 1
  if (x === 'machine') return 2
  if (x === 'cable') return 3
  return 4
}

function isBodyweightEquipment(equipment: string | null | undefined): boolean {
  return (equipment ?? 'bodyweight').toLowerCase() === 'bodyweight'
}

/**
 * Full commercial gym: model sees mostly loaded equipment — cap how many bodyweight rows appear in ALLOWED_EXERCISES.
 * If filters leave only bodyweight, leave the list unchanged.
 */
function limitBodyweightForFullCommercialGym<E extends { equipment: string | null }>(
  allowed: E[],
  userEquipmentTags: string[],
  maxBodyweight: number,
): E[] {
  if (!userEquipmentTags.includes('full_commercial_gym')) {
    return allowed
  }
  const loaded = allowed.filter((e) => !isBodyweightEquipment(e.equipment))
  const bw = allowed.filter((e) => isBodyweightEquipment(e.equipment))
  if (loaded.length === 0) {
    return allowed
  }
  shuffleInPlace(bw)
  return [...loaded, ...bw.slice(0, maxBodyweight)]
}

/**
 * Build up to `maxSize` exercises with round-robin across equipment tiers so barbell/machine
 * rows are not crowded out by low-fatigue bodyweight entries.
 */
function samplePoolForAi<E extends { equipment: string | null }>(allowed: E[], maxSize: number): E[] {
  if (allowed.length <= maxSize) {
    const copy = [...allowed]
    shuffleInPlace(copy)
    return copy
  }
  const buckets: E[][] = [[], [], [], [], []]
  for (const e of allowed) {
    buckets[equipmentTier(e.equipment)].push(e)
  }
  for (const b of buckets) shuffleInPlace(b)

  const out: E[] = []
  while (out.length < maxSize) {
    let progressed = false
    for (let t = 0; t < buckets.length; t++) {
      if (out.length >= maxSize) break
      const b = buckets[t]
      if (b.length > 0) {
        const next = b.pop()
        if (next !== undefined) {
          out.push(next)
          progressed = true
        }
      }
    }
    if (!progressed) break
  }
  shuffleInPlace(out)
  return out
}

/**
 * DeepSeek picks real exercises from an allowed pool (UUID ids from DB).
 */
export async function generateAiWorkoutSuggestionForUser(userId: string): Promise<WorkoutSuggestionResult> {
  const warnings: string[] = []

  if (!process.env.DEEPSEEK_API_KEY) {
    throw new Error('AI_DISABLED')
  }

  const [tp, profile] = await Promise.all([
    prisma.userTrainingProfile.findUnique({ where: { userId } }),
    prisma.userProfile.findUnique({ where: { userId }, select: { bodyweightKg: true } }),
  ])

  const primaryGoal = tp?.primaryGoal ?? null
  const trainingLevel = tp?.trainingLevel ?? null
  const rawEquip = parseStringArray(tp?.equipment)
  const userEquipment = normalizeEquipmentTagsForAi(rawEquip)
  const bodyweightKg = profile?.bodyweightKg ? Number(profile.bodyweightKg) : null

  const sportIntent = inferSportIntentFromProfile({
    gymExperience: tp?.gymExperience,
    injuriesLimitations: tp?.injuriesLimitations,
  })
  const effectivePrimaryGoal = primaryGoal ?? sportIntent?.inferredPrimaryGoal ?? 'hypertrophy'

  // Additive goal set (union of ALL signals) used to widen the candidate pool.
  // Previously the pool was filtered by a single `effectivePrimaryGoal` (enum
  // OR sport-intent OR 'hypertrophy'), so the user's free-text goal (e.g. "dunk
  // a basketball" -> jump) was overridden by the picker enum and plyometric
  // exercises never even entered the pool -> generic plans. We now include
  // exercises matching the enum goal, the sport intent, AND the free-text goal.
  const goalSet = new Set<string>();
  if (primaryGoal) goalSet.add(primaryGoal);
  if (sportIntent?.inferredPrimaryGoal) goalSet.add(sportIntent.inferredPrimaryGoal);
  for (const intent of detectGoalIntents(tp?.onboardingGoalText)) {
    for (const tag of goalTagsForIntent(intent)) goalSet.add(tag);
  }
  if (goalSet.size === 0) goalSet.add('hypertrophy');
  const goalList = [...goalSet];

  if (!tp?.onboardingCompleted) {
    warnings.push('Complete training onboarding for tighter AI matching.')
  }
  if (sportIntent) {
    warnings.push(`Sport focus from profile notes: ${sportIntent.sport}.`)
  }

  // AI pool: do not restrict by beginnerSuitable or fatigue — user level only affects suggested loads downstream.
  const catalog = await prisma.exercise.findMany({
    where: { isCustom: false },
    orderBy: [{ name: 'asc' }],
    take: 500,
  })

  if (catalog.length === 0) {
    warnings.push('Exercise catalog empty — run npm run db:seed in backend.')
    return {
      blueprintId: 'ai_generated',
      title: 'No exercises in catalog',
      description: 'Seed the exercise catalog to enable AI workouts.',
      primaryGoal,
      exercises: [],
      warnings,
    }
  }

  let allowed = catalog.filter(
    (e) =>
      exerciseFitsUserEquipment(e.equipment, userEquipment) &&
      // Additive: keep the exercise if it matches ANY of the user's goal
      // signals, not just one overriding enum.
      goalList.some((g) => exerciseMatchesPrimaryGoal(e.goalTags, g)),
  )

  if (allowed.length < 8) {
    allowed = catalog.filter((e) => exerciseFitsUserEquipment(e.equipment, userEquipment))
    warnings.push('AI pool: relaxed primary-goal filter.')
  }
  if (allowed.length < 8) {
    allowed = [...catalog]
    warnings.push('AI pool: relaxed equipment filter.')
  }

  const MAX_BW_IN_POOL_FULL_GYM = 2
  allowed = limitBodyweightForFullCommercialGym(allowed, userEquipment, MAX_BW_IN_POOL_FULL_GYM)

  const pool = samplePoolForAi(allowed, 120).map((e) => ({
    id: e.id,
    name: e.name,
    pattern: e.movementPattern,
    muscle: e.primaryMuscle,
    equipment: e.equipment,
  }))

  const allowedIds = new Set(pool.map((p) => p.id))

  // User's free-text goal from onboarding (their own words) — drives selection
  // when present so daily sessions stay aligned with what they actually wrote,
  // not just the enum bucket.
  const onboardingGoalText = (tp?.onboardingGoalText ?? '').trim().slice(0, 800)

  // Recent lift history so the AI biases toward exercises the user is actually
  // training and away from lifts that have stalled.
  const progression = await getRecentProgression(userId)
  const progressionBlock = formatProgressionForPrompt(progression)

  const userPrompt = `Pick ONE gym session from ALLOWED_EXERCISES only.

ALLOWED_EXERCISES=${JSON.stringify(pool)}

USER_CONTEXT:
- primaryGoal (training): ${JSON.stringify(effectivePrimaryGoal)}
- trainingLevel: ${JSON.stringify(trainingLevel ?? 'intermediate')}
- daysPerWeek: ${tp?.daysPerWeek ?? 4}
- sessionMinutes: ${tp?.sessionMinutes ?? 60}
- injuriesLimitations: ${JSON.stringify((tp?.injuriesLimitations ?? '').slice(0, 400))}
${onboardingGoalText ? `- userGoalNarrative: ${JSON.stringify(onboardingGoalText)}\n  (top priority — bias your picks toward this goal even when it tilts away from the enum bucket)` : ''}
${progressionBlock ? `\n${progressionBlock}` : ''}${buildGoalGuidance(onboardingGoalText)}

Return strict JSON only:
{
  "title": "short English session title",
  "description": "one English sentence",
  "exercises": [
    {
      "exerciseId": "<must be exactly one id from ALLOWED_EXERCISES>",
      "sets": 3,
      "repRange": "8-12",
      "restSeconds": 90,
      "whyThisExercise": "TWO short sentences (max 45 words total). Sentence 1: what this exercise primarily builds (muscle/system/skill, concrete physiology — e.g. 'Builds eccentric hamstring strength through hip-hinge loading.'). Sentence 2: why it fits the user's stated goal — reference the goal explicitly. No generic filler like 'great for strength'."
    }
  ]
}

Rules:
- 6–9 exercises, no duplicate exerciseId.
- Cover squat OR unilateral squat variant, hinge OR hinge variant, horizontal push, horizontal pull, vertical pull where exercises exist in the list.
- Use ONLY exerciseId values present in ALLOWED_EXERCISES (exact UUID).
- EVERY exercise MUST have a non-empty "whyThisExercise" with TWO sentences: (1) what it builds physiologically, (2) why it fits the user's goal. Mandatory.
- Respect injuries (avoid provocative movements when injuriesLimitations mentions specific joints/pain).
- All strings English.${userEquipment.includes('full_commercial_gym') ? '\n- Prefer barbell/dumbbell/machine/cable; ALLOWED_EXERCISES includes at most 2 bodyweight movements — use them only if they clearly complement the session.' : ''}`

  let parsed: AiSessionJson | null = null

  for (let attempt = 0; attempt < 2; attempt++) {
    const out = await deepSeekChat(
      [
        {
          role: 'system',
          content: `${ZVELT_APP_CONTEXT_FOR_AI}

You return strict JSON only, no markdown.
Exercise IDs must be copied exactly from ALLOWED_EXERCISES — invalid IDs break the app.`,
        },
        {
          role: 'user',
          content:
            attempt === 0
              ? userPrompt
              : `${userPrompt}\n\nRetry: previous JSON used ids not in ALLOWED_EXERCISES — fix every exerciseId.`,
        },
      ],
      { maxTokens: 1400, temperature: attempt === 0 ? 0.35 : 0.2 },
    )

    parsed = parseJsonFromModel<AiSessionJson>(out.text)
    if (!parsed?.exercises?.length) continue

    const idsOk = parsed.exercises.every(
      (x) => x.exerciseId && typeof x.exerciseId === 'string' && allowedIds.has(x.exerciseId),
    )
    if (idsOk) break
    parsed = null
  }

  if (!parsed?.exercises?.length) {
    warnings.push('AI returned no valid exercises after retries.')
    return {
      blueprintId: 'ai_generated',
      title: 'Could not build AI workout',
      description: 'Try again or check DeepSeek API / exercise catalog.',
      primaryGoal,
      exercises: [],
      warnings,
    }
  }

  const byId = new Map(catalog.map((e) => [e.id, e]))
  const seen = new Set<string>()
  const exercises: SuggestedExercise[] = []

  for (const row of parsed.exercises) {
    if (!row.exerciseId || seen.has(row.exerciseId)) continue
    if (!allowedIds.has(row.exerciseId)) continue
    const ex = byId.get(row.exerciseId)
    if (!ex) continue
    seen.add(row.exerciseId)
    const whyRaw = typeof row.whyThisExercise === 'string' ? row.whyThisExercise.trim() : ''
    exercises.push({
      exerciseId: ex.id,
      name: ex.name,
      movementPattern: ex.movementPattern,
      primaryMuscle: ex.primaryMuscle,
      equipment: ex.equipment,
      sets: clampSets(row.sets),
      repRange: sanitizeRepRange(row.repRange),
      restSeconds: clampRest(row.restSeconds),
      suggestedWeightKg: 0,
      weightSource: 'heuristic',
      whyThisExercise: whyRaw.length > 0 ? whyRaw.slice(0, 480) : undefined,
    })
  }

  if (exercises.length === 0) {
    warnings.push('AI picks failed validation.')
    return {
      blueprintId: 'ai_generated',
      title: parsed.title ?? 'AI workout',
      description: parsed.description ?? '',
      primaryGoal,
      exercises: [],
      warnings,
    }
  }

  const lastWeights = await fetchLastWorkingWeights(
    userId,
    exercises.map((e) => e.exerciseId),
  )
  let needsBodyweightWarning = false
  for (const ex of exercises) {
    const hist = lastWeights.get(ex.exerciseId)
    if (typeof hist === 'number' && hist > 0) {
      ex.suggestedWeightKg = roundToStep(hist, 2.5)
      ex.weightSource = 'history'
      continue
    }
    const heuristic = heuristicWeightKg({
      pattern: ex.movementPattern,
      equipment: ex.equipment,
      bodyweightKg,
      trainingLevel,
    })
    ex.suggestedWeightKg = heuristic
    if (heuristic === 0) {
      ex.weightSource = 'bodyweight'
    } else {
      ex.weightSource = 'heuristic'
      if (bodyweightKg == null) needsBodyweightWarning = true
    }
  }
  if (needsBodyweightWarning) {
    warnings.push('Add your bodyweight in profile for more accurate starting weights.')
  }

  return {
    blueprintId: 'ai_generated',
    title: (parsed.title ?? 'AI session').slice(0, 120),
    description: (parsed.description ?? '').slice(0, 240),
    primaryGoal,
    exercises,
    warnings,
  }
}
