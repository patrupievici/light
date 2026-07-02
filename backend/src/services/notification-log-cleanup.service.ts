import cron, { type ScheduledTask } from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'

import { prisma } from '../lib/prisma'

/**
 * Daily prune of the NotificationSentLog idempotency ledger.
 *
 * That table is append-only (one row per scheduled-notification claim), so it
 * grows ~1 row/engaged-user/day plus challenge events. The dedupe keys only
 * matter for a short window (a UTC day for streak; the lifetime of a live
 * challenge for ending/ended), so anything older than the retention window is
 * dead weight — drop it. 90 days is comfortably longer than any challenge.
 */

const DAY_MS = 86_400_000

let cronTask: ScheduledTask | null = null

export function startNotificationLogCleanupCron(log: FastifyBaseLogger): void {
  if (cronTask) {
    log.warn('notification-log cleanup cron already started — skipping duplicate init')
    return
  }
  cronTask = cron.schedule(
    '15 3 * * *',
    () => {
      runNotificationLogCleanup(log).catch((err) => {
        log.error({ err: String(err?.message ?? err) }, 'notification-log cleanup crashed')
      })
    },
    { timezone: 'UTC' },
  )
  log.info('cron: notification-sent-log cleanup @ 03:15 UTC daily')
}

export function stopNotificationLogCleanupCron(): void {
  cronTask?.stop()
  cronTask = null
}

/** Public for tests / manual runs. Deletes claims older than retentionDays. */
export async function runNotificationLogCleanup(
  log: FastifyBaseLogger,
  retentionDays = 90,
): Promise<{ deleted: number }> {
  const cutoff = new Date(Date.now() - retentionDays * DAY_MS)
  const res = await prisma.notificationSentLog.deleteMany({ where: { createdAt: { lt: cutoff } } })
  if (res.count > 0) log.info({ deleted: res.count }, 'notification-sent-log cleanup done')
  return { deleted: res.count }
}
