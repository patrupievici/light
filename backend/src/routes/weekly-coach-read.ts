import type { FastifyInstance } from 'fastify'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { deepSeekChat } from '../services/deepseek.service'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../ai/app-context'
import { sanitizePromptInput } from '../lib/ai-helpers'
import { buildGoalGuidance } from '../lib/goal-guidance'

// In-process cache keyed by `${userId}:${weekStartYmd}`. Weekly cadence —
// the read for week W is stable all week long, refreshes once on Monday.
// Restart loses cache (acceptable; ~$0.0002 per call).
const READ_CACHE = new Map<string, { text: string; weekStart: string }>()

function isoWeekStartUtc(d: Date = new Date()): string {
  // Monday as week start (ISO 8601 convention).
  const dt = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
  const dow = dt.getUTCDay() // 0 = Sunday
  const diff = dow === 0 ? -6 : 1 - dow
  dt.setUTCDate(dt.getUTCDate() + diff)
  return dt.toISOString().slice(0, 10)
}

function ymd(d: Date): string {
  return d.toISOString().slice(0, 10)
}

type WeekSummary = {
  rangeLabel: string
  sessions: number
  totalVolumeKg: number
  uniqueExerciseCount: number
  avgRpe: number | null
  topLifts: Array<{ name: string; topWeightKg: number; reps: number }>
}

async function summarizeWeek(userId: string, startUtc: Date, endUtc: Date): Promise<WeekSummary> {
  const workouts = await prisma.workout.findMany({
    where: {
      userId,
      status: 'completed',
      endedAt: { gte: startUtc, lt: endUtc },
    },
    include: {
      exercises: {
        include: {
          exercise: { select: { name: true } },
          sets: { where: { tag: 'WORK', isCompleted: true } },
        },
      },
    },
  })

  let totalVolumeKg = 0
  const exerciseTops = new Map<string, { name: string; topWeightKg: number; reps: number }>()
  const rpeValues: number[] = []
  const exerciseNames = new Set<string>()

  for (const w of workouts) {
    for (const we of w.exercises) {
      exerciseNames.add(we.exercise.name)
      for (const s of we.sets) {
        const wKg = Number(s.weightKg)
        if (wKg > 0 && s.reps > 0) totalVolumeKg += wKg * s.reps
        if (s.rpe != null) rpeValues.push(Number(s.rpe))
        const existing = exerciseTops.get(we.exercise.name)
        if (!existing || wKg > existing.topWeightKg) {
          exerciseTops.set(we.exercise.name, {
            name: we.exercise.name,
            topWeightKg: wKg,
            reps: s.reps,
          })
        }
      }
    }
  }

  const top = Array.from(exerciseTops.values())
    .sort((a, b) => b.topWeightKg - a.topWeightKg)
    .slice(0, 6)
  const avgRpe = rpeValues.length > 0
    ? Math.round((rpeValues.reduce((a, b) => a + b, 0) / rpeValues.length) * 10) / 10
    : null

  return {
    rangeLabel: `${ymd(startUtc)} → ${ymd(new Date(endUtc.getTime() - 1))}`,
    sessions: workouts.length,
    totalVolumeKg: Math.round(totalVolumeKg),
    uniqueExerciseCount: exerciseNames.size,
    avgRpe,
    topLifts: top,
  }
}

export async function weeklyCoachReadRoutes(app: FastifyInstance) {
  // GET /v1/me/weekly-coach-read
  //
  // AI-generated weekly summary shown on Progress → Training. Single ISO
  // week granularity — same read all week, refreshes Monday UTC.
  app.get('/weekly-coach-read', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const weekStart = isoWeekStartUtc()

    const cacheKey = `${userId}:${weekStart}`
    const cached = READ_CACHE.get(cacheKey)
    if (cached && cached.weekStart === weekStart) {
      return reply.send({ read: cached.text, weekStart, cached: true })
    }

    if (!process.env.DEEPSEEK_API_KEY) {
      return reply.code(503).send({
        error: 'AI_DISABLED',
        message: 'Coach is offline',
        requestId: request.id,
      })
    }

    // Window: last 7 days + prior 7 days (both ending now), so the read can
    // call out trends like "volume up 18% vs last week".
    const now = new Date()
    const lastWeekStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
    const priorWeekStart = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000)

    const [thisWeek, priorWeek, trainingProfile] = await Promise.all([
      summarizeWeek(userId, lastWeekStart, now),
      summarizeWeek(userId, priorWeekStart, lastWeekStart),
      prisma.userTrainingProfile.findUnique({
        where: { userId },
        select: { onboardingGoalText: true, primaryGoal: true, daysPerWeek: true },
      }),
    ])

    if (thisWeek.sessions === 0) {
      const offerRead = trainingProfile?.onboardingGoalText
        ? `No sessions logged in the last 7 days. Your goal — "${sanitizePromptInput(trainingProfile.onboardingGoalText).slice(0, 120)}" — needs reps. Open the Train tab and start one session today; the coach read will populate once you train.`
        : 'No sessions logged in the last 7 days. Log a workout to get a coach read on your training pattern.'
      // Deliberately NOT cached: caching the empty state locked it for the
      // whole ISO week, so the read kept saying "no sessions" even after the
      // user trained. Recompute every call until there's a real session.
      return reply.send({ read: offerRead, weekStart, cached: false })
    }

    const goalText = trainingProfile?.onboardingGoalText?.trim() ?? ''
    const guidance = buildGoalGuidance(goalText)
    const daysPerWeekTarget = trainingProfile?.daysPerWeek ?? null

    const topLiftsBlock = thisWeek.topLifts.length > 0
      ? thisWeek.topLifts
          .map((l) => `  - ${l.name}: ${l.topWeightKg}kg × ${l.reps}`)
          .join('\n')
      : '  - (no loaded sets recorded)'

    const volumeDelta = priorWeek.totalVolumeKg > 0
      ? Math.round(((thisWeek.totalVolumeKg - priorWeek.totalVolumeKg) / priorWeek.totalVolumeKg) * 100)
      : null

    const prompt = `Generate a "Coach's read on your week" for the user's Progress tab. This appears once and is read carefully, so make it count.

THIS WEEK (last 7 days):
- Sessions: ${thisWeek.sessions}${daysPerWeekTarget ? ` (target: ${daysPerWeekTarget}/wk)` : ''}
- Total volume: ${thisWeek.totalVolumeKg} kg (load × reps summed across all working sets)
- Unique exercises: ${thisWeek.uniqueExerciseCount}
- Average RPE: ${thisWeek.avgRpe ?? 'not recorded'}
- Top working lifts:
${topLiftsBlock}

PRIOR WEEK (8-14 days ago):
- Sessions: ${priorWeek.sessions}
- Total volume: ${priorWeek.totalVolumeKg} kg
- Average RPE: ${priorWeek.avgRpe ?? 'not recorded'}
${volumeDelta != null ? `- Volume change: ${volumeDelta > 0 ? '+' : ''}${volumeDelta}% vs this week` : ''}

USER GOAL: ${goalText ? `"${sanitizePromptInput(goalText)}"` : `(category hint: ${trainingProfile?.primaryGoal ?? 'general fitness'})`}
${guidance ? `\nGoal-specific lens:${guidance}\n` : ''}
Structure: 4 short labeled bullets, each on its own line. Format EXACTLY like this:
**This week:** <1-2 sentence summary of what happened — reference numbers>
**Progress:** <one specific win OR the most important pattern this week>
**Watch:** <one risk, gap, or thing trending wrong — be specific>
**Next week:** <one concrete recommendation, with a number where possible>

Hard rules:
- Each bullet starts with the bolded label exactly as shown.
- Every bullet MUST include at least one number (kg, reps, sessions, %, or RPE).
- If a section truly has nothing to say (e.g. only one workout, no comparison possible), write "—" instead of padding.
- Coach tone: warm but direct. Never motivational filler.
- BANNED phrases (rewrite without them): "great job", "keep it up", "trust the process", "stay consistent", "listen to your body", "crushing it", "way to go".
- English only. Max 90 words total. No markdown except the **bold labels**.`

    try {
      const out = await deepSeekChat(
        [
          {
            role: 'system',
            content: `${ZVELT_APP_CONTEXT_FOR_AI}

You write weekly coach reads for active users on the Progress tab. Specific, quantified, never filler. The user expects something they couldn't have written themselves.`,
          },
          { role: 'user', content: prompt },
        ],
        { maxTokens: 350, temperature: 0.4 },
      )
      const read = out.text.trim().slice(0, 1200)
      if (!read) throw new Error('Empty coach read from model')
      READ_CACHE.set(cacheKey, { text: read, weekStart })
      // Eviction: drop entries from previous weeks so the map doesn't grow.
      for (const [k, v] of READ_CACHE) {
        if (v.weekStart !== weekStart) READ_CACHE.delete(k)
      }
      return reply.send({ read, weekStart, cached: false })
    } catch (e: any) {
      app.log.warn({ err: String(e?.message ?? e), userId }, 'weekly-coach-read failed')
      return reply.code(502).send({
        error: 'AI_UPSTREAM',
        message: 'Coach is briefly unavailable',
        requestId: request.id,
      })
    }
  })
}
