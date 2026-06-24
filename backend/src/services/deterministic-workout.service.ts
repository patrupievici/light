import { prisma } from '../lib/prisma'
import { PROGRAM_BLUEPRINTS, type ProgramBlueprint, type SlotPrescription } from '../programming/blueprints'
import { exerciseFitsUserEquipment } from '../programming/equipment-compatibility'
import { normalizeEquipmentTagsForAi } from '../lib/equipment-for-ai'
import { detectGoalIntents, goalTagsForIntent, hasInjuryContext, hasNegationContext } from '../lib/goal-guidance'
import { deepSeekChat } from './deepseek.service'
import { parseJsonFromModel, sanitizePromptInput } from '../lib/ai-helpers'
import {
  fetchLastWorkingWeights,
  heuristicWeightKg,
  type SuggestedExercise,
  type WorkoutSuggestionResult,
} from './workout-generator.service'

/**
 * Deterministic workout engine — composes a session by filling movement-pattern
 * slots from the tagged exercise catalog. No exercise is ever invented.
 *
 * Two ways the slots are sourced:
 *   1. COMMON goals → a fixed [ProgramBlueprint] (instant, no LLM).
 *   2. NICHE goals (e.g. "table tennis") → an LLM DECOMPOSES the goal into slots
 *      (pattern + dose), constrained to our pattern vocabulary, then the SAME
 *      composer fills them from the catalog. The LLM only picks patterns/tags
 *      from a fixed list — it never names exercises, so still zero hallucination.
 *
 * `generateWorkoutSuggestionForUser` tries (1) → (2) → full LLM as last resort.
 */

type CatalogExercise = Awaited<ReturnType<typeof prisma.exercise.findMany>>[number]

/** The movement-pattern vocabulary the catalog uses (also the LLM's allowed set). */
const ALLOWED_PATTERNS = [
  'squat',
  'hinge',
  'lunge_unilateral_lower',
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
  'jump_throw_sprint',
  'locomotion_conditioning',
  'loaded_carry',
  'core_anti_extension',
  'core_anti_rotation',
  'core_anti_lateral_flexion',
  'skill_stability',
] as const

function asTags(v: unknown): string[] {
  return Array.isArray(v) ? (v as unknown[]).filter((x): x is string => typeof x === 'string') : []
}

/** Additive goal-tag set from enum + free-text intents (the "component spec"). */
export function resolveGoalComponents(args: {
  primaryGoal: string | null
  onboardingGoalText: string | null
  extra?: string[]
}): string[] {
  const set = new Set<string>()
  if (args.primaryGoal) set.add(args.primaryGoal)
  for (const intent of detectGoalIntents(args.onboardingGoalText)) {
    for (const tag of goalTagsForIntent(intent)) set.add(tag)
  }
  for (const t of args.extra ?? []) set.add(t)
  return [...set]
}

/**
 * Routing decision (pure): the FREE-TEXT goal is the source of truth.
 *  - free text recognized by keywords → its tags drive blueprint selection
 *    (so "dunk" + a "strength" picker still routes to the jump blueprint).
 *  - free text present but NOT recognized (e.g. "table tennis") → defer to the
 *    LLM decomposition path; the picker enum must NOT shadow a niche goal.
 *  - no free text → fall back to the picker enum.
 */
export function routeWorkoutGoal(args: {
  primaryGoal: string | null
  onboardingGoalText: string | null
}): { defer: boolean; blueprintGoals: string[] } {
  const text = (args.onboardingGoalText ?? '').trim()
  // Safety: a goal mentioning an injury/pain/constraint must never run a blind
  // blueprint — defer to the LLM, which can program around the limitation.
  if (hasInjuryContext(text)) return { defer: true, blueprintGoals: [] }
  // Negation/avoidance ("not interested in bulking") — keywords can't parse it.
  if (hasNegationContext(text)) return { defer: true, blueprintGoals: [] }
  const intents = detectGoalIntents(text)
  // Compound goal (multiple distinct intents, e.g. "dunk and run a marathon"):
  // a single fixed blueprint can't blend them — defer to the LLM, which can.
  if (intents.length > 1) return { defer: true, blueprintGoals: [] }
  const textTags = intents.flatMap(goalTagsForIntent)
  if (text.length > 0 && textTags.length === 0) return { defer: true, blueprintGoals: [] }
  const blueprintGoals = textTags.length > 0 ? textTags : args.primaryGoal ? [args.primaryGoal] : []
  return { defer: blueprintGoals.length === 0, blueprintGoals }
}

export function pickBlueprint(goals: string[], daysPerWeek: number): ProgramBlueprint | null {
  const inDays = (b: ProgramBlueprint) => daysPerWeek >= b.minDays && daysPerWeek <= b.maxDays
  return (
    PROGRAM_BLUEPRINTS.find(
      (b) => !b.primaryGoals.includes('*') && b.primaryGoals.some((g) => goals.includes(g)) && inDays(b),
    ) ?? null
  )
}

function whyFor(pattern: string, goal: string): string {
  const map: Record<string, string> = {
    jump_throw_sprint: 'Trains rate of force development — the core driver of explosive power and jump height.',
    squat: 'Builds maximal lower-body strength that underpins power output.',
    hinge: 'Strengthens the posterior chain for hip-extension power.',
    lunge_unilateral_lower: 'Single-leg strength and stability that transfers directly to athletic movement.',
    horizontal_push: 'Upper-body pressing strength and size.',
    vertical_push: 'Overhead pressing strength and shoulder stability.',
    horizontal_pull: 'Back thickness and pulling strength to balance pressing.',
    vertical_pull: 'Lat width and vertical pulling strength.',
    locomotion_conditioning: 'Conditioning that raises work capacity and supports recovery.',
    core_anti_extension: 'Bracing strength that protects the spine under load.',
    core_anti_rotation: 'Rotational core control — key for transferring power between limbs.',
    core_anti_lateral_flexion: 'Lateral core stability for a balanced, injury-resistant trunk.',
    loaded_carry: 'Full-body tension and grip strength that carries over everywhere.',
    skill_stability: 'Targeted accessory work to round out the session.',
  }
  return map[pattern] ?? `Selected to support your ${goal} goal.`
}

type SessionContext = {
  catalog: CatalogExercise[]
  userEquipment: string[]
  bodyweightKg: number | null
  trainingLevel: string | null
}

async function loadContext(
  userId: string,
): Promise<{ ctx: SessionContext; primaryGoal: string | null; onboardingGoalText: string | null; daysPerWeek: number } | null> {
  const [tp, profile] = await Promise.all([
    prisma.userTrainingProfile.findUnique({ where: { userId } }),
    prisma.userProfile.findUnique({ where: { userId }, select: { bodyweightKg: true } }),
  ])
  if (!tp) return null
  const catalog = await prisma.exercise.findMany({ where: { isCustom: false }, take: 500 })
  if (catalog.length === 0) return null
  return {
    ctx: {
      catalog,
      userEquipment: normalizeEquipmentTagsForAi(asTags(tp.equipment)),
      bodyweightKg: profile?.bodyweightKg ? Number(profile.bodyweightKg) : null,
      trainingLevel: tp.trainingLevel ?? 'intermediate',
    },
    primaryGoal: tp.primaryGoal ?? null,
    onboardingGoalText: tp.onboardingGoalText ?? null,
    daysPerWeek: tp.daysPerWeek ?? 4,
  }
}

/** Rank a candidate for a slot. fatigueScore is the primary signal — it tracks
 *  how substantial/compound a lift is (Squat 5, Wall Sit 2), so a "squat" slot
 *  picks the big barbell Squat over Wall Sit. (isRanked can't differentiate —
 *  every catalogued lift is ranked.) Goal tag + ranked are small nudges only;
 *  notably NOT a hard filter, since for fat loss only the light bodyweight
 *  squats are tagged 'fat_loss' yet the barbell Squat is the better choice. */
function candidateScore(e: CatalogExercise, goals: string[]): number {
  let s = Number(e.fatigueScore ?? 0) * 20
  const tags = asTags(e.goalTags)
  if (goals.some((g) => tags.includes(g))) s += 10
  if (e.isRanked) s += 5
  return s
}

/** Shared filler: turn a slot list into a concrete session from the catalog. */
export async function composeSession(
  userId: string,
  ctx: SessionContext,
  slots: SlotPrescription[],
  goals: string[],
  meta: { blueprintId: string; title: string; description: string },
): Promise<WorkoutSuggestionResult | null> {
  const dayOffset = Math.floor(Date.now() / 86_400_000)
  const isBeginner = (ctx.trainingLevel ?? '').toLowerCase().startsWith('begin')
  const chosen: Array<{ ex: CatalogExercise; slot: SlotPrescription }> = []
  const usedIds = new Set<string>()

  for (const slot of slots) {
    let pool = ctx.catalog.filter(
      (e) =>
        e.movementPattern === slot.pattern &&
        exerciseFitsUserEquipment(e.equipment, ctx.userEquipment) &&
        !usedIds.has(e.id),
    )
    if (pool.length === 0) continue
    // Beginners: keep beginner-suitable movements when any exist — no Olympic
    // lifts / advanced skills (e.g. Power Snatch) for a novice.
    if (isBeginner) {
      const beg = pool.filter((e) => e.beginnerSuitable)
      if (beg.length > 0) pool = beg
    }

    // Rank by canonical main lift + on-goal tag + compound size (goal is a
    // bonus, not a hard filter).
    pool.sort((a, b) => candidateScore(b, goals) - candidateScore(a, goals) || a.name.localeCompare(b.name))
    // Daily variety, but only within the top window — never drop to low-quality
    // picks just for rotation.
    const window = Math.min(pool.length, slot.pick + 3)
    const start = window > 0 ? dayOffset % window : 0
    const ordered = pool.slice(0, window)
    const rotated = ordered.slice(start).concat(ordered.slice(0, start))
    let taken = 0
    for (const ex of rotated) {
      if (taken >= slot.pick) break
      if (usedIds.has(ex.id)) continue
      usedIds.add(ex.id)
      chosen.push({ ex, slot })
      taken++
    }
  }

  if (chosen.length < 3) return null

  const lastWeights = await fetchLastWorkingWeights(
    userId,
    chosen.map((c) => c.ex.id),
  )
  const primaryGoal = goals[0] ?? 'general fitness'

  const exercises: SuggestedExercise[] = chosen.map(({ ex, slot }) => {
    const last = lastWeights.get(ex.id)
    let suggestedWeightKg: number
    let weightSource: SuggestedExercise['weightSource']
    if (last != null && last > 0) {
      suggestedWeightKg = last
      weightSource = 'history'
    } else {
      const h = heuristicWeightKg({
        pattern: ex.movementPattern,
        equipment: ex.equipment,
        bodyweightKg: ctx.bodyweightKg,
        trainingLevel: ctx.trainingLevel,
      })
      suggestedWeightKg = h
      weightSource = h === 0 ? 'bodyweight' : 'heuristic'
    }
    return {
      exerciseId: ex.id,
      name: ex.name,
      movementPattern: ex.movementPattern,
      primaryMuscle: ex.primaryMuscle,
      equipment: ex.equipment,
      sets: slot.sets,
      repRange: slot.repRange,
      restSeconds: slot.restSeconds,
      suggestedWeightKg,
      weightSource,
      whyThisExercise: whyFor(ex.movementPattern, primaryGoal),
    }
  })

  return {
    blueprintId: meta.blueprintId,
    title: meta.title,
    description: meta.description,
    primaryGoal,
    exercises,
    warnings: [],
  }
}

/** (1) Common goals → fixed blueprint. Returns null for uncovered/fuzzy goals. */
export async function generateDeterministicSuggestion(
  userId: string,
): Promise<WorkoutSuggestionResult | null> {
  const loaded = await loadContext(userId)
  if (!loaded) return null

  const route = routeWorkoutGoal({
    primaryGoal: loaded.primaryGoal,
    onboardingGoalText: loaded.onboardingGoalText,
  })
  // Niche / uncovered goal → let the LLM-decomposition path handle it.
  if (route.defer) return null

  const blueprint = pickBlueprint(route.blueprintGoals, loaded.daysPerWeek)
  if (!blueprint) return null

  // Within-slot exercise preference uses the full additive set (text + enum).
  const goals = resolveGoalComponents({
    primaryGoal: loaded.primaryGoal,
    onboardingGoalText: loaded.onboardingGoalText,
  })
  return composeSession(userId, loaded.ctx, blueprint.slots, goals, {
    blueprintId: blueprint.id,
    title: blueprint.title,
    description: blueprint.description,
  })
}

type DecomposedSpec = { title: string; components: string[]; slots: SlotPrescription[] }

/** Ask the LLM to DECOMPOSE a niche goal into pattern slots (no exercise names).
 *  Constrained + validated against our vocabulary → still zero hallucination. */
export async function decomposeGoalToSlots(goalText: string): Promise<DecomposedSpec | null> {
  const clean = sanitizePromptInput(goalText.trim()).slice(0, 400)
  if (clean.length < 3) return null
  const injuryNote = hasInjuryContext(clean)
    ? `
- SAFETY (the athlete reports an injury / pain / surgery / constraint): do NOT load the affected area hard. Avoid plyometrics, jumps, max-effort, and deep or heavy loading on that region. Prefer controlled, moderate-load, joint-friendly patterns; favour higher reps with lighter load, stability, and pain-free range. Prioritise safe rehab-style work over performance.`
    : ''
  const prompt = `You are a strength & conditioning coach. Decompose this athlete's goal into ONE training session, as movement-pattern slots.

Use ONLY these movement patterns (no others):
${ALLOWED_PATTERNS.join(', ')}

Return STRICT JSON only:
{
  "title": "short session name (max 4 words)",
  "components": ["quality tags, e.g. explosive_power, core_anti_rotation"],
  "slots": [
    { "pattern": "<one of the allowed>", "pick": 1-3, "sets": 1-6, "repRange": "e.g. 3-5", "restSeconds": 30-300 }
  ]
}

Rules:
- 4-6 slots. Order most important first.
- Dose for the goal: power/sport → 3-5 reps, rest 120-180; strength → 3-6; hypertrophy → 8-12; conditioning → rounds/time.
- Cover ALL qualities the sport needs (e.g. a racket sport: lower-body explosive + rotational core + upper-body power + single-leg).${injuryNote}
- No prose, JSON only.

GOAL: "${clean}"`

  let out: { text: string }
  try {
    out = await deepSeekChat(
      [
        { role: 'system', content: 'You return strict JSON only. No markdown, no explanations.' },
        { role: 'user', content: prompt },
      ],
      { maxTokens: 500, temperature: 0.2 },
    )
  } catch {
    return null
  }

  const json = parseJsonFromModel(out.text) as Partial<DecomposedSpec> | null
  if (!json || !Array.isArray(json.slots)) return null

  const allowed = new Set<string>(ALLOWED_PATTERNS)
  const clamp = (n: unknown, lo: number, hi: number, dflt: number) => {
    const v = typeof n === 'number' ? n : Number(n)
    return Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.round(v))) : dflt
  }
  const slots: SlotPrescription[] = []
  for (const raw of json.slots) {
    const r = raw as Record<string, unknown>
    const pattern = String(r.pattern ?? '')
    if (!allowed.has(pattern)) continue // drop invented patterns
    slots.push({
      pattern,
      pick: clamp(r.pick, 1, 3, 1),
      sets: clamp(r.sets, 1, 6, 3),
      repRange: typeof r.repRange === 'string' ? r.repRange.slice(0, 16) : '8–12',
      restSeconds: clamp(r.restSeconds, 30, 300, 90),
    })
    if (slots.length >= 7) break
  }
  if (slots.length < 2) return null

  const components = Array.isArray(json.components)
    ? json.components.filter((c): c is string => typeof c === 'string').slice(0, 8)
    : []
  const title = typeof json.title === 'string' && json.title.trim() ? json.title.trim().slice(0, 40) : 'Sport-specific session'
  return { title, components, slots }
}

/** (2) Niche goals → LLM decomposes into slots → deterministic composer fills.
 *  Returns null if no free-text goal, decomposition fails, or pool too thin. */
export async function generateDecomposedSuggestion(
  userId: string,
): Promise<WorkoutSuggestionResult | null> {
  const loaded = await loadContext(userId)
  if (!loaded) return null
  const goalText = loaded.onboardingGoalText?.trim()
  if (!goalText) return null

  const spec = await decomposeGoalToSlots(goalText)
  if (!spec) return null

  // Goal-tag preference = LLM components + any keyword intents + the enum, so the
  // filler biases each slot toward the right quality where the catalog allows.
  const goals = resolveGoalComponents({
    primaryGoal: loaded.primaryGoal,
    onboardingGoalText: goalText,
    extra: spec.components,
  })

  return composeSession(userId, loaded.ctx, spec.slots, goals, {
    blueprintId: 'llm_decomposed',
    title: spec.title,
    description: 'Built for your goal from sport-specific qualities.',
  })
}
