import cron, { type ScheduledTask } from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'

import { prisma } from '../lib/prisma'
import {
  createNotificationSafe,
  claimScheduledNotification,
  NotificationType,
} from './notification.service'

/**
 * Daily "streak at risk" notification.
 *
 * Streak rule (CLAUDE.md): 3 consecutive days without a post breaks a streak.
 * We warn at the 2-dayless-day mark — i.e. a user whose most recent post was
 * 2–3 days ago (48–72h): yesterday and today are postless, one more postless
 * day breaks it. Posting today saves the streak.
 *
 * Scope: only engaged users (a post within the last 14 days) so we never nag
 * dormant accounts. Idempotent per UTC day via NotificationSentLog so the job
 * (or a restart) can re-run safely.
 */

const DAY_MS = 86_400_000

let cronTask: ScheduledTask | null = null

export function startStreakRiskNotificationCron(log: FastifyBaseLogger): void {
  if (cronTask) {
    log.warn('streak-risk cron already started — skipping duplicate init')
    return
  }
  // 23:30 UTC daily — last call before the day rolls over.
  cronTask = cron.schedule(
    '30 23 * * *',
    () => {
      runStreakRiskNotifications(log).catch((err) => {
        log.error({ err: String(err?.message ?? err) }, 'streak-risk notifications crashed')
      })
    },
    { timezone: 'UTC' },
  )
  log.info('cron: streak-risk notifications @ 23:30 UTC daily')
}

export function stopStreakRiskNotificationCron(): void {
  cronTask?.stop()
  cronTask = null
}

/** Public for tests / manual runs. Returns a summary. */
export async function runStreakRiskNotifications(
  log: FastifyBaseLogger,
): Promise<{ candidates: number; sent: number }> {
  const now = new Date()
  const fourteenDaysAgo = new Date(now.getTime() - 14 * DAY_MS)
  const twoDaysAgo = new Date(now.getTime() - 2 * DAY_MS)
  const threeDaysAgo = new Date(now.getTime() - 3 * DAY_MS)
  const dedupeKey = now.toISOString().slice(0, 10) // YYYY-MM-DD (UTC)

  // Most recent post per engaged user (posted in the last 14 days).
  const groups = await prisma.post.groupBy({
    by: ['userId'],
    where: { createdAt: { gt: fourteenDaysAgo } },
    _max: { createdAt: true },
  })

  // At risk = last post 2–3 days ago (the day before a 3-day break).
  const atRisk = groups.filter((g) => {
    const last = g._max.createdAt
    return last != null && last < twoDaysAgo && last >= threeDaysAgo
  })

  let sent = 0
  for (const g of atRisk) {
    const claimed = await claimScheduledNotification(g.userId, NotificationType.STREAK_RISK, dedupeKey)
    if (!claimed) continue
    await createNotificationSafe({
      recipientId: g.userId,
      actorId: null,
      type: NotificationType.STREAK_RISK,
      payload: { lastPostAt: g._max.createdAt?.toISOString() ?? null },
    })
    sent++
  }

  if (sent > 0) log.info({ candidates: atRisk.length, sent }, 'streak-risk notifications sent')
  return { candidates: atRisk.length, sent }
}
