import cron, { type ScheduledTask } from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'

import { prisma } from '../lib/prisma'
import { generateAndPersistWeeklyPlan, WeeklyPlanError } from './weekly-plan.service'

/**
 * Weekly plan regeneration cron.
 *
 * Why: the onboarding plan covers week 1. Without this cron, users see empty
 * calendars from week 2 onward. With it, every active user gets a fresh
 * 7-day plan that respects their latest progression (e1RM, last weights).
 *
 * When: every Monday at 03:00 server time. We pace the AI calls so we don't
 * burn the DeepSeek rate limit in one burst.
 *
 * Who: only users with onboardingCompleted=true AND a completed workout in
 * the last 14 days. Cold accounts are skipped — no need to burn AI credits
 * generating plans nobody will read.
 *
 * Idempotency: per-user we check if planned_workout already exists for the
 * upcoming weekStart; if it does, we skip (re-run safe).
 */

const SECONDS_BETWEEN_USERS = 4 // ~15 users/min → comfortably under most AI rate limits
const ACTIVE_WINDOW_DAYS = 14

let cronTask: ScheduledTask | null = null

export function startWeeklyPlanRegenCron(log: FastifyBaseLogger): void {
  if (cronTask) {
    log.warn('weekly-plan cron already started — skipping duplicate init')
    return
  }
  // Monday at 03:00 server local time. Server is typically UTC; in production
  // this fires Monday 03:00 UTC, which means most timezones still see a fresh
  // plan when they wake up Monday morning.
  cronTask = cron.schedule(
    '0 3 * * 1',
    () => {
      runWeeklyPlanRegenForActiveUsers(log).catch((err) => {
        log.error({ err: String(err?.message ?? err) }, 'weekly-plan cron crashed')
      })
    },
    { timezone: 'UTC' },
  )
  log.info('cron: weekly-plan regen @ Monday 03:00 UTC')
}

export function stopWeeklyPlanRegenCron(): void {
  cronTask?.stop()
  cronTask = null
}

/**
 * Public entry point. Runs the regeneration for every eligible user.
 * Returns a summary so an admin endpoint or tests can call it on demand.
 */
export async function runWeeklyPlanRegenForActiveUsers(log: FastifyBaseLogger): Promise<{
  scanned: number
  generated: number
  skipped: number
  failed: number
}> {
  const weekStart = mondayOfThisWeekUtc()
  const since = new Date(Date.now() - ACTIVE_WINDOW_DAYS * 24 * 60 * 60 * 1000)

  // Active users: onboarding done AND at least one completed workout recently.
  const activeUserIds = await prisma.user.findMany({
    where: {
      status: 'active',
      trainingProfile: { onboardingCompleted: true },
      workouts: { some: { status: { in: ['completed', 'posted'] }, endedAt: { gte: since } } },
    },
    select: { id: true },
  })

  log.info({ count: activeUserIds.length, weekStart }, 'weekly-plan cron: starting batch')

  let generated = 0
  let skipped = 0
  let failed = 0

  for (const { id: userId } of activeUserIds) {
    try {
      const existing = await prisma.plannedWorkout.findFirst({
        where: { userId, weekStart },
        select: { id: true },
      })
      if (existing) {
        skipped++
        continue
      }
      await generateAndPersistWeeklyPlan(
        userId,
        // skipGoalAdvice=true: it's an extra AI call we don't need at cron time
        // (advice is captured once during onboarding and rarely needs refresh).
        { applyDailyTargets: true, skipGoalAdvice: true, weekStart },
        log,
      )
      generated++
    } catch (err: any) {
      failed++
      if (err instanceof WeeklyPlanError) {
        log.warn({ err: err.code, userId }, 'weekly-plan cron: user failed (known error)')
      } else {
        log.error({ err: String(err?.message ?? err), userId }, 'weekly-plan cron: user failed (unexpected)')
      }
    }
    // Pace requests so DeepSeek doesn't throttle the whole batch.
    await sleep(SECONDS_BETWEEN_USERS * 1000)
  }

  log.info({ scanned: activeUserIds.length, generated, skipped, failed }, 'weekly-plan cron: batch done')
  return { scanned: activeUserIds.length, generated, skipped, failed }
}

function mondayOfThisWeekUtc(): string {
  const now = new Date()
  const dow = now.getUTCDay() // 0 = Sun, 1 = Mon, ...
  const offsetToMonday = dow === 0 ? -6 : 1 - dow
  const monday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + offsetToMonday))
  return monday.toISOString().split('T')[0]
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms))
}
