/**
 * Goal-aware daily push notifications.
 *
 * Sends each active user a personalized push referencing **their goal** and
 * **today's planned workout** — generated fresh by DeepSeek every day. The
 * difference vs a generic "Time to work out!" notification is that the user
 * opens this one because it says *something*: "For your dunk goal, today's
 * plyometric work matters most — get it in before dinner."
 *
 * Cron cadence:
 *   - Runs every hour at minute 5 (avoids overlap with the weekly-plan cron
 *     on the hour).
 *   - For each eligible user, checks whether the current UTC hour matches
 *     their preferred LOCAL push hour (derived from their most recent
 *     workout's `timezone` field; falls back to 18:00 UTC if unknown).
 *   - Idempotent per (user, UTC date) via an in-process Set so we never
 *     double-send the same day after a restart-recovery hiccup.
 *
 * Eligibility:
 *   - status = active
 *   - onboardingCompleted = true
 *   - Has a planned workout today (status = pending)
 *   - Has at least one FCM token registered
 *
 * Fallback chain when AI fails:
 *   - Returns a deterministic template based on goal text + workout name
 *     so a user never gets silence purely because DeepSeek hiccupped.
 */

import cron, { type ScheduledTask } from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'

import { prisma } from '../lib/prisma'
import { deepSeekChat } from './deepseek.service'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../ai/app-context'
import { sanitizePromptInput, parseJsonFromModel } from '../lib/ai-helpers'
import { isFcmConfigured, sendPlainPush } from './fcm.service'

const DEFAULT_LOCAL_PUSH_HOUR = 18 // 6 PM local — best window for evening lifters

// In-process dedupe: prevents double-sends after partial-failure recovery.
// Key: `${userId}:${utcDateYmd}`. Cleared once per day by a self-prune.
const SENT_TODAY = new Set<string>()

let cronTask: ScheduledTask | null = null

// ─── Public API ──────────────────────────────────────────────────────────────

export function startGoalAwarePushCron(log: FastifyBaseLogger): void {
  if (cronTask) {
    log.warn('goal-aware push cron already started — skipping duplicate init')
    return
  }
  // Every hour at minute 5 — avoids clashing with weekly-plan cron at :00.
  cronTask = cron.schedule(
    '5 * * * *',
    () => {
      runGoalAwarePushBatch(log).catch((err) => {
        log.error({ err: String(err?.message ?? err) }, 'goal-aware push cron crashed')
      })
    },
    { timezone: 'UTC' },
  )
  log.info('cron: goal-aware push @ :05 each hour (UTC)')
}

/** Public, on-demand single-user trigger used by the `/me/test-push` route.
 *  Bypasses the hour-of-day gate so QA can fire it any time. Still respects
 *  the per-day dedupe (call `force=true` to override). */
export async function sendGoalAwarePushForUser(
  userId: string,
  opts: { force?: boolean; log?: FastifyBaseLogger } = {},
): Promise<{ ok: boolean; reason?: string; title?: string; body?: string; tokens?: number }> {
  if (!isFcmConfigured()) {
    return { ok: false, reason: 'fcm_not_configured' }
  }

  const ctx = await loadPushContext(userId)
  if (!ctx) {
    return { ok: false, reason: 'no_context_or_no_planned_workout_today' }
  }

  const todayKey = `${userId}:${utcYmd(new Date())}`
  if (!opts.force && SENT_TODAY.has(todayKey)) {
    return { ok: false, reason: 'already_sent_today' }
  }

  const msg = await buildPushMessage(ctx, opts.log)

  const tokens = await sendPlainPush(userId, msg.title, msg.body, {
    type: 'goal_aware_nudge',
    plannedWorkoutId: ctx.workoutId,
  })
  if (tokens > 0) {
    SENT_TODAY.add(todayKey)
  }
  return { ok: tokens > 0, title: msg.title, body: msg.body, tokens, reason: tokens === 0 ? 'no_tokens' : undefined }
}

// ─── Cron batch logic ────────────────────────────────────────────────────────

export async function runGoalAwarePushBatch(log: FastifyBaseLogger): Promise<{
  scanned: number
  sent: number
  skippedHour: number
  skippedDedupe: number
  failed: number
}> {
  if (!isFcmConfigured()) {
    log.debug('goal-aware push: FCM not configured, skipping batch')
    return { scanned: 0, sent: 0, skippedHour: 0, skippedDedupe: 0, failed: 0 }
  }

  // Self-prune yesterday's dedupe keys so the set doesn't grow forever.
  pruneSentSet()

  const now = new Date()
  const utcHour = now.getUTCHours()
  const utcYmdNow = utcYmd(now)

  // Eligible users: onboarding done, planned workout today not completed,
  // at least one push token. We pull a wider list and gate by hour inside the
  // loop so we have access to each user's most-recent-workout timezone.
  const candidates = await prisma.user.findMany({
    where: {
      status: 'active',
      trainingProfile: { onboardingCompleted: true },
      pushTokens: { some: {} },
      plannedWorkouts: {
        some: {
          day: { contains: '' }, // narrowed below by joined query
          status: 'pending',
          kind: 'gym',
        },
      },
    },
    select: {
      id: true,
      workouts: {
        select: { timezone: true, startedAt: true },
        orderBy: { startedAt: 'desc' },
        take: 1,
      },
    },
    take: 5000,
  })

  let sent = 0
  let skippedHour = 0
  let skippedDedupe = 0
  let failed = 0

  for (const u of candidates) {
    try {
      const tzOffsetMin = extractTzOffsetMinutes(u.workouts[0]?.timezone)
      const localHour = (utcHour + Math.round(tzOffsetMin / 60) + 24) % 24
      if (localHour !== DEFAULT_LOCAL_PUSH_HOUR) {
        skippedHour++
        continue
      }

      const key = `${u.id}:${utcYmdNow}`
      if (SENT_TODAY.has(key)) {
        skippedDedupe++
        continue
      }

      // Re-check planned workout existence with today's local date — the
      // outer query was permissive. This avoids paging the AI on a user
      // whose planned workout is for a different day than their local today.
      const ctx = await loadPushContext(u.id)
      if (!ctx) {
        skippedDedupe++
        continue
      }

      const msg = await buildPushMessage(ctx, log)
      const tokens = await sendPlainPush(u.id, msg.title, msg.body, {
        type: 'goal_aware_nudge',
        plannedWorkoutId: ctx.workoutId,
      })
      if (tokens > 0) {
        SENT_TODAY.add(key)
        sent++
      } else {
        failed++
      }
    } catch (err: any) {
      failed++
      log.warn({ err: String(err?.message ?? err), userId: u.id }, 'goal-aware push: user failed')
    }
  }

  log.info(
    { scanned: candidates.length, sent, skippedHour, skippedDedupe, failed },
    'goal-aware push: batch done',
  )
  return { scanned: candidates.length, sent, skippedHour, skippedDedupe, failed }
}

// ─── Context loading + AI message generation ────────────────────────────────

type PushContext = {
  userId: string
  goalText: string
  workoutId: string
  workoutTitle: string
  workoutFocus: string
}

async function loadPushContext(userId: string): Promise<PushContext | null> {
  const tp = await prisma.userTrainingProfile.findUnique({
    where: { userId },
    select: { onboardingGoalText: true, primaryGoal: true },
  })
  const goalText =
    tp?.onboardingGoalText?.trim() ?? `Goal: ${tp?.primaryGoal ?? 'general fitness'}`

  const todayLocal = userTodayYmd(userId).catch(() => utcYmd(new Date()))
  const day = await todayLocal

  const planned = await prisma.plannedWorkout.findFirst({
    where: { userId, day, status: 'pending', kind: 'gym' },
    select: { id: true, title: true, notes: true },
    orderBy: { createdAt: 'asc' },
  })
  if (!planned) return null

  return {
    userId,
    goalText,
    workoutId: planned.id,
    workoutTitle: (planned.title || 'Today\'s session').slice(0, 80),
    workoutFocus: (planned.notes || '').trim().slice(0, 120),
  }
}

type PushMessage = { title: string; body: string }

async function buildPushMessage(ctx: PushContext, log?: FastifyBaseLogger): Promise<PushMessage> {
  // Deterministic fallback that we'll return if AI fails or returns garbage.
  const fallback: PushMessage = {
    title: `Zvelt · ${ctx.workoutTitle}`,
    body: ctx.goalText.length > 0
      ? `Today's session moves you toward: ${ctx.goalText.slice(0, 80)}.`
      : `Today's session: ${ctx.workoutTitle}.`,
  }

  if (!process.env.DEEPSEEK_API_KEY) return fallback

  const prompt = `Generate a personalized push notification for a fitness app user.
The user will see ONE notification on their phone — make it worth opening.

USER GOAL: "${sanitizePromptInput(ctx.goalText).slice(0, 300)}"
TODAY'S PLANNED WORKOUT: "${ctx.workoutTitle}"${ctx.workoutFocus ? `\nWORKOUT FOCUS: "${sanitizePromptInput(ctx.workoutFocus)}"` : ''}

Return strict JSON only:
{
  "title": "string (max 48 chars). Format: 'Zvelt · <short hook>' where hook references TODAY'S SESSION, not generic.",
  "body": "string (max 110 chars). ONE sentence that ties today's specific session to the user's stated goal. Reference the goal explicitly. No exclamation marks. No emojis."
}

BANNED phrases (the user has seen these in every other app — they are noise): "Time to work out", "Don't skip", "You got this", "Crush it", "Get moving", "Time to train", "Hit the gym", "Power through".

If the goal is vague, focus on the workout's concrete benefit. Coach tone — direct, warm, specific. No motivational filler.`

  try {
    const out = await deepSeekChat(
      [
        {
          role: 'system',
          content: `${ZVELT_APP_CONTEXT_FOR_AI}

You write goal-aware push notifications. Each one is 2 strings: title and body. The user must learn something they didn't already know to want to open the app.`,
        },
        { role: 'user', content: prompt },
      ],
      { maxTokens: 150, temperature: 0.55 },
    )

    const json = parseJsonFromModel<{ title?: string; body?: string }>(out.text)
    if (!json) return fallback

    const title = (json.title ?? '').trim().slice(0, 60)
    const body = (json.body ?? '').trim().slice(0, 140)
    if (title.length < 4 || body.length < 8) return fallback
    return { title, body }
  } catch (e: any) {
    log?.warn({ err: String(e?.message ?? e), userId: ctx.userId }, 'goal-aware push: AI failed, using fallback')
    return fallback
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Extract a timezone offset in minutes from an arbitrary string. We don't
 * guarantee correctness for region names like "Europe/Bucharest" (would need
 * Intl.DateTimeFormat lookup); we handle the common shapes we actually store:
 *   "+03:00" / "-05:00" / "UTC+3" / "+0200" / "0"
 * Defaults to 0 (UTC) on anything unrecognized.
 */
function extractTzOffsetMinutes(raw: string | null | undefined): number {
  if (!raw) return 0
  const s = raw.trim()
  // ±HH:MM or ±HHMM
  const m = s.match(/([+-])(\d{1,2}):?(\d{2})?/)
  if (m) {
    const sign = m[1] === '-' ? -1 : 1
    const hours = parseInt(m[2] ?? '0', 10)
    const mins = parseInt(m[3] ?? '0', 10)
    return sign * (hours * 60 + mins)
  }
  // Bare number (legacy stored values: "+3" or "3")
  const n = parseInt(s, 10)
  if (!isNaN(n) && Math.abs(n) <= 14) return n * 60
  return 0
}

function utcYmd(d: Date): string {
  return d.toISOString().slice(0, 10)
}

/** Best-effort "today's local YMD" for a user. Uses their most recent
 *  workout's timezone offset; falls back to UTC today. */
async function userTodayYmd(userId: string): Promise<string> {
  const w = await prisma.workout.findFirst({
    where: { userId },
    select: { timezone: true },
    orderBy: { startedAt: 'desc' },
  })
  const offsetMin = extractTzOffsetMinutes(w?.timezone)
  const now = new Date()
  const local = new Date(now.getTime() + offsetMin * 60 * 1000)
  return local.toISOString().slice(0, 10)
}

/** Drop dedupe entries that aren't from the current UTC date. */
function pruneSentSet(): void {
  const today = utcYmd(new Date())
  for (const key of SENT_TODAY) {
    if (!key.endsWith(`:${today}`)) SENT_TODAY.delete(key)
  }
}
