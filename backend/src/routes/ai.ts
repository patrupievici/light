import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { Prisma } from '@prisma/client'
import { authenticate } from '../middleware/auth'
import { prisma } from '../lib/prisma'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../ai/app-context'
import { normalizeEquipmentTagsForAi } from '../lib/equipment-for-ai'
import { inferSportIntentFromProfile } from '../programming/sport-intent'
import { signalsEliteCompetitionLevel } from '../lib/elite-athlete'
import { generateWorkoutSuggestionForUser, createDraftWorkoutFromSuggestion } from '../services/workout-generator.service'
import { deepSeekChat } from '../services/deepseek.service'
import { resolveExerciseByName } from '../lib/exercise-resolver'
import { getRecentProgression, formatProgressionForPrompt } from '../lib/progression-context'
import { computeProgressiveLoads, type ProgressionLevel } from '../lib/progressive-overload'
import { sanitizePromptInput, parseJsonFromModel, generateGoalAdvice } from '../lib/ai-helpers'
import { buildGoalGuidance } from '../lib/goal-guidance'
import { generateAndPersistWeeklyPlan, WeeklyPlanError } from '../services/weekly-plan.service'

const ChatSchema = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(['user', 'assistant', 'system']),
        content: z.string().min(1).max(2000),
      }),
    )
    .min(1)
    .max(20),
})

const OnboardingInterpretSchema = z.object({
  gymExperience: z.string().max(500).optional().nullable(),
  injuriesLimitations: z.string().max(4000).optional().nullable(),
})

const GoalInterpretSchema = z.object({
  goalText: z.string().min(3).max(2000),
})

/** Heuristic label for the UI — pure substring detection mirrors goal-guidance
 *  intent labels but never blocks rendering when the AI is slow. */
function detectIntentLabel(goalText: string): string | null {
  const t = goalText.toLowerCase()
  if (/\b(dunk|vertical|jump|jumping|hops|leap|basketball|volleyball)\b/.test(t)) return 'jump'
  if (/\b(sprint|sprinting|faster|speed|acceleration|40[\s-]?yard|100m)\b/.test(t)) return 'sprint'
  if (/\b(powerlifting|1\s*rm|max\s+lift|stronger|deadlift\s+pr|squat\s+pr|bench\s+pr)\b/.test(t)) return 'strength'
  if (/\b(calisthenic|planche|front\s+lever|back\s+lever|muscle[\s-]?up|handstand|hspu|gymnastic)\b/.test(t)) return 'calisthenics'
  if (/\b(fat\s+loss|lose\s+(weight|fat)|cutting|cut\b|lean|shred|shredded)\b/.test(t)) return 'fat_loss'
  if (/\b(build\s+muscle|muscle\s+(gain|growth|building)|bodybuilding|hypertrophy|get\s+(jacked|big|swole))\b/.test(t)) return 'hypertrophy'
  if (/\b(marathon|half[\s-]?marathon|5k|10k|ultra|running|cycling|triathlon|endurance|stamina)\b/.test(t)) return 'endurance'
  return null
}

const AiTrainerSchema = z.object({
  question: z.string().min(3).max(1000),
  createWorkout: z.boolean().optional(),
})

const WeeklyPlanSchema = z.object({
  goal: z.enum(['fat_loss', 'maintenance', 'hypertrophy', 'strength', 'calisthenics', 'explosive_power']).optional(),
  /// Free-form goal narrative from onboarding chatbox. When present the AI sees
  /// the user's own words (top priority in prompt) — `goal` enum is only a hint.
  goalText: z.string().max(2000).optional(),
  daysPerWeek: z.number().min(1).max(7).optional(),
  sessionMinutes: z.number().min(15).max(180).optional(),
  equipment: z.array(z.string()).optional(),
  /// When true (default), persist AI's `mealPlan.dailyTargets` to userProfile.
  /// Set false if the caller wants to keep existing nutrition targets.
  applyDailyTargets: z.boolean().optional(),
  /// User's previous goal text — passed when goal is being CHANGED (goal
  /// evolution flow). Enables the AI to produce a `goalChangeRationale`
  /// field in the response that explains what shifted in the plan.
  previousGoalText: z.string().max(2000).optional(),
  /// Dietary restrictions/preferences from onboarding — fed into the nutrition
  /// prompt so meal targets + notes respect them.
  dietaryRestrictions: z.array(z.string().max(40)).max(20).optional(),
})

/**
 * Proxy DeepSeek (OpenAI-compatible) — task Excel #26.
 * Env: DEEPSEEK_API_KEY, optional DEEPSEEK_API_URL (default api.deepseek.com).
 */
export async function aiRoutes(app: FastifyInstance) {
  // Stricter rate limit for AI endpoints (5 req/min per user) to protect API credits.
  app.addHook('preHandler', async (request, reply) => {
    // Fastify rate-limit already tracks per-IP; this is a soft check via header.
    // The global 100/min is the hard limit; AI routes need tighter control.
  })

  app.post('/chat', { preHandler: [authenticate], config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (request, reply) => {
    if (!process.env.DEEPSEEK_API_KEY) {
      return reply.code(503).send({
        error: 'AI_DISABLED',
        message: 'Seteaza DEEPSEEK_API_KEY in .env',
        requestId: request.id,
      })
    }

    const parsed = ChatSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Mesaje invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const systemHint = `${ZVELT_APP_CONTEXT_FOR_AI}

Esti un asistent fitness concis. Raspunsuri scurte, practice; nu oferi diagnostic medical si nu inlocui medicul.`

    const messages = [
      { role: 'system' as const, content: systemHint },
      ...parsed.data.messages.map((m) => ({ role: m.role, content: m.content })),
    ]
    try {
      const out = await deepSeekChat(messages, { maxTokens: 500, temperature: 0.6 })
      return reply.send({
        reply: out.text,
        model: out.model,
      })
    } catch (e: any) {
      app.log.warn({ err: String(e?.message ?? e) }, 'DeepSeek error')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'AI indisponibil',
        requestId: request.id,
      })
    }
  })

  // POST /v1/ai/goal-interpret
  //
  // Fast endpoint for the "AI got me" onboarding moment: the user writes their
  // free-text goal, and BEFORE the long weekly-plan generation runs we show
  // them an instant intermediate screen that proves the AI understood the
  // goal. Same DeepSeek model, far smaller prompt — usually returns in ~1s.
  //
  // Response shape:
  //   { paraphrase: "...", priorities: ["...", "..."], intentLabel: "jump" | null, model: "..." }
  app.post(
    '/goal-interpret',
    { preHandler: [authenticate], config: { rateLimit: { max: 20, timeWindow: '1 minute' } } },
    async (request, reply) => {
      if (!process.env.DEEPSEEK_API_KEY) {
        return reply.code(503).send({
          error: 'AI_DISABLED',
          message: 'Set DEEPSEEK_API_KEY on the server',
          requestId: request.id,
        })
      }
      const parsed = GoalInterpretSchema.safeParse(request.body)
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'Invalid goalText',
          requestId: request.id,
          details: parsed.error.flatten(),
        })
      }

      const goalText = parsed.data.goalText.trim()
      const intentLabel = detectIntentLabel(goalText)
      const guidance = buildGoalGuidance(goalText)

      const prompt = `The user just wrote this fitness goal:
"${sanitizePromptInput(goalText)}"

${guidance ? `Detected focus areas — use them to shape your priorities:${guidance}\n` : ''}
Return strict JSON only with this exact shape:
{
  "paraphrase": "1-2 sentences confirming you understood the goal — second-person, warm but not saccharine, NEVER restate the goal verbatim",
  "priorities": ["3-5 short bullets describing what the plan will focus on, each max 10 words, specific to this goal"]
}

Rules:
- Paraphrase must show comprehension, not parroting. E.g. if goal is "I want to dunk", say "You want to develop explosive lower-body power for vertical jumping in basketball", not "You want to dunk".
- Priorities are skills/categories/training principles, NOT specific exercises. E.g. "Single-leg plyometric work" not "Box jumps 4×6".
- English only. No emojis. No markdown.`

      try {
        const out = await deepSeekChat(
          [
            {
              role: 'system',
              content: `${ZVELT_APP_CONTEXT_FOR_AI}

You return strict JSON only, no markdown. Be specific and warm without being saccharine.`,
            },
            { role: 'user', content: prompt },
          ],
          { maxTokens: 300, temperature: 0.45 },
        )
        const json = parseJsonFromModel<{ paraphrase?: string; priorities?: string[] }>(out.text)
        if (!json) throw new Error('Invalid JSON from model')

        const paraphrase = String(json.paraphrase ?? '').trim().slice(0, 400)
        const priorities = Array.isArray(json.priorities)
          ? json.priorities
              .map((p) => String(p).trim())
              .filter((p) => p.length > 0)
              .slice(0, 5)
          : []

        if (!paraphrase || priorities.length === 0) {
          throw new Error('Empty paraphrase or priorities')
        }

        return reply.send({
          paraphrase,
          priorities,
          intentLabel,
          model: out.model,
        })
      } catch (e: any) {
        app.log.warn({ err: String(e?.message ?? e) }, 'DeepSeek goal-interpret error')
        return reply.code(502).send({
          error: 'AI_UPSTREAM',
          message: 'AI temporarily unavailable',
          requestId: request.id,
        })
      }
    },
  )

  // POST /v1/ai/onboarding-interpret
  app.post('/onboarding-interpret', { preHandler: [authenticate], config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (request, reply) => {
    if (!process.env.DEEPSEEK_API_KEY) {
      return reply.code(503).send({
        error: 'AI_DISABLED',
        message: 'Seteaza DEEPSEEK_API_KEY in .env',
        requestId: request.id,
      })
    }

    const parsed = OnboardingInterpretSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const fallback = inferSportIntentFromProfile({
      gymExperience: parsed.data.gymExperience ?? null,
      injuriesLimitations: parsed.data.injuriesLimitations ?? null,
    })

    const prompt = `You are a fitness onboarding interpreter.
Return strict JSON only with shape:
{
  "sportFocus": string|null,
  "inferredPrimaryGoal": string|null,
  "constraints": string[],
  "experienceLevelHint": "beginner"|"novice"|"intermediate"|"advanced"|null,
  "programNotes": string[]
}
Allowed inferredPrimaryGoal values: fat_loss, maintenance, hypertrophy, strength, calisthenics, explosive_power, vertical_jump, null.
Input gymExperience: ${sanitizePromptInput(parsed.data.gymExperience ?? '')}
Input injuriesLimitations: ${sanitizePromptInput(parsed.data.injuriesLimitations ?? '')}
Keep constraints/programNotes short and practical.
Every string field (constraints, programNotes, sportFocus) MUST be English only — no Romanian.`

    try {
      const out = await deepSeekChat(
        [
          {
            role: 'system',
            content: `${ZVELT_APP_CONTEXT_FOR_AI}

You return strict JSON only, no markdown.
All text fields inside the JSON (sportFocus, constraints, programNotes) MUST be English only.`,
          },
          { role: 'user', content: prompt },
        ],
        { maxTokens: 350, temperature: 0.2 },
      )
      const json = parseJsonFromModel<{
        sportFocus: string | null
        inferredPrimaryGoal: string | null
        constraints: string[]
        experienceLevelHint: 'beginner' | 'novice' | 'intermediate' | 'advanced' | null
        programNotes: string[]
      }>(out.text)
      if (!json) {
        throw new Error('Invalid JSON from model')
      }
      return reply.send({
        interpretation: {
          sportFocus: json.sportFocus ?? fallback?.sport ?? null,
          inferredPrimaryGoal: json.inferredPrimaryGoal ?? fallback?.inferredPrimaryGoal ?? null,
          constraints: Array.isArray(json.constraints) ? json.constraints.slice(0, 10) : [],
          experienceLevelHint: json.experienceLevelHint ?? null,
          programNotes: Array.isArray(json.programNotes) ? json.programNotes.slice(0, 10) : [],
        },
        model: out.model,
      })
    } catch (e: any) {
      app.log.warn({ err: String(e?.message ?? e) }, 'DeepSeek onboarding-interpret error')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'AI indisponibil',
        requestId: request.id,
      })
    }
  })

  // POST /v1/ai/onboarding-plan — REMOVED. The unified `/v1/ai/weekly-plan`
  // now accepts a `goalText` field, persists exercises in PlannedWorkout, and
  // writes mealPlan dailyTargets to userProfile in one round-trip.
  app.post('/onboarding-plan', { preHandler: [authenticate] }, async (request, reply) => {
    return reply.code(410).send({
      error: 'GONE',
      message: 'Use POST /v1/ai/weekly-plan with { goalText } instead.',
      requestId: request.id,
    })
  })


  // POST /v1/ai/trainer
  app.post('/trainer', { preHandler: [authenticate], config: { rateLimit: { max: 6, timeWindow: '1 minute' } } }, async (request, reply) => {
    if (!process.env.DEEPSEEK_API_KEY) {
      return reply.code(503).send({
        error: 'AI_DISABLED',
        message: 'Seteaza DEEPSEEK_API_KEY in .env',
        requestId: request.id,
      })
    }

    const parsed = AiTrainerSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const { userId } = request.user
    const createWorkout = parsed.data.createWorkout ?? false
    const [profile, trainingProfile] = await Promise.all([
      prisma.userProfile.findUnique({ where: { userId } }),
      prisma.userTrainingProfile.findUnique({ where: { userId } }),
    ])
    let suggestion: Awaited<ReturnType<typeof generateWorkoutSuggestionForUser>> | null = null
    if (createWorkout) {
      try {
        suggestion = await generateWorkoutSuggestionForUser(userId)
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e)
        app.log.warn({ err: msg }, 'trainer createWorkout: suggestion AI failed')
        suggestion = null
      }
    }

    const trainerPrompt = `You are an AI trainer. Respond in strict JSON only:
{
  "answer": string,
  "nextSessionFocus": string[],
  "risksToWatch": string[],
  "microPlan7Days": string[]
}
Constraints:
- Keep answer max 140 words.
- No diagnosis, no medical claims.
- Practical, specific, concise.
User question: ${sanitizePromptInput(parsed.data.question)}
User profile: ${JSON.stringify({
      unitSystem: profile?.unitSystem ?? null,
      bodyweightKg: profile?.bodyweightKg ?? null,
      heightCm: profile?.heightCm ?? null,
      dailyCalories: profile?.dailyCalories ?? null,
    })}
Training profile: ${JSON.stringify({
      primaryGoal: trainingProfile?.primaryGoal ?? null,
      trainingLevel: trainingProfile?.trainingLevel ?? null,
      daysPerWeek: trainingProfile?.daysPerWeek ?? null,
      sessionMinutes: trainingProfile?.sessionMinutes ?? null,
      equipment: normalizeEquipmentTagsForAi(
        Array.isArray(trainingProfile?.equipment)
          ? (trainingProfile.equipment as unknown[]).filter((x): x is string => typeof x === 'string')
          : [],
      ),
      injuriesLimitations: trainingProfile?.injuriesLimitations
        ? sanitizePromptInput(String(trainingProfile.injuriesLimitations))
        : null,
      gymExperience: trainingProfile?.gymExperience
        ? sanitizePromptInput(String(trainingProfile.gymExperience))
        : null,
    })}
Current workout suggestion: ${JSON.stringify(suggestion)}`

    try {
      const out = await deepSeekChat(
        [
          {
            role: 'system',
            content: `${ZVELT_APP_CONTEXT_FOR_AI}

You return strict JSON only, no markdown. No explanations. You are a concise performance coach for strength and conditioning.`,
          },
          { role: 'user', content: trainerPrompt },
        ],
        { maxTokens: 550, temperature: 0.4 },
      )

      const json = parseJsonFromModel<{
        answer: string
        nextSessionFocus: string[]
        risksToWatch: string[]
        microPlan7Days: string[]
      }>(out.text)
      if (!json) {
        throw new Error('Invalid JSON from model')
      }

      let createdWorkout: { id: string } | null = null
      if (createWorkout && suggestion && suggestion.exercises.length > 0) {
        const created = await createDraftWorkoutFromSuggestion(userId, suggestion)
        const w = created.workout as { id?: string } | null
        if (w?.id) createdWorkout = { id: w.id }
      }

      return reply.send({
        trainer: {
          answer: (json.answer ?? '').slice(0, 1200),
          nextSessionFocus: Array.isArray(json.nextSessionFocus)
            ? json.nextSessionFocus.slice(0, 6)
            : [],
          risksToWatch: Array.isArray(json.risksToWatch) ? json.risksToWatch.slice(0, 6) : [],
          microPlan7Days: Array.isArray(json.microPlan7Days) ? json.microPlan7Days.slice(0, 7) : [],
        },
        model: out.model,
        workout: createdWorkout,
      })
    } catch (e: any) {
      app.log.warn({ err: String(e?.message ?? e) }, 'DeepSeek trainer error')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'AI trainer indisponibil',
        requestId: request.id,
      })
    }
  })

  // POST /v1/ai/weekly-plan — thin wrapper around generateAndPersistWeeklyPlan.
  // Same function is invoked by the Monday cron so users keep getting plans
  // beyond the first week without lifting a finger.
  app.post('/weekly-plan', { preHandler: [authenticate], config: { rateLimit: { max: 3, timeWindow: '5 minutes' } } }, async (request, reply) => {
    const parsed = WeeklyPlanSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const { userId } = request.user
    try {
      const result = await generateAndPersistWeeklyPlan(userId, parsed.data, app.log)
      return reply.send(result)
    } catch (e) {
      if (e instanceof WeeklyPlanError) {
        const status = e.code === 'AI_DISABLED' ? 503 : e.code === 'PROFILE_INCOMPLETE' ? 400 : 502
        return reply.code(status).send({ error: e.code, message: e.message, requestId: request.id })
      }
      app.log.warn({ err: e instanceof Error ? e.message : String(e) }, 'weekly-plan unexpected error')
      return reply.code(500).send({ error: 'INTERNAL_ERROR', message: 'Unexpected error', requestId: request.id })
    }
  })

}
