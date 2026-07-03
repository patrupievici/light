import cron, { type ScheduledTask } from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'

import { prisma } from '../lib/prisma'
import { eraseUser } from '../routes/gdpr'

/**
 * Soft-delete sweep: hard-erases accounts whose grace window has elapsed.
 *
 * Part of the OPT-IN soft-delete flow (DELETE /v1/me/account marks an account
 * deleted + sets scheduledHardEraseAt when ZVELT_SOFT_DELETE is on). This cron
 * is safe to run unconditionally: if nobody is soft-deleted the query returns
 * no rows and it does nothing. It calls the SAME eraseUser cascade used by the
 * immediate-delete path, so the on-disk + DB cleanup is identical.
 *
 * Best-effort per user: one user's erasure failure is logged and does not
 * abort the rest of the batch (next sweep retries it).
 */

let cronTask: ScheduledTask | null = null

/** Default sweep cadence (minutes) when SOFT_DELETE_SWEEP_MINUTES is unset/invalid. */
const DEFAULT_SWEEP_MINUTES = 60

/** Per-sweep batch cap so a large backlog can't run unbounded in one tick. */
const SWEEP_BATCH_SIZE = 200

/** Overlap guard: skip a tick if the previous sweep is still running. */
let sweepRunning = false

/** Resolve the sweep interval (minutes) from env, clamped to a sane range. */
function resolveSweepMinutes(): number {
  const raw = Number(process.env.SOFT_DELETE_SWEEP_MINUTES)
  if (!Number.isFinite(raw) || raw <= 0) return DEFAULT_SWEEP_MINUTES
  // Cap at 24h; floor at 1 minute to keep the cron expression valid.
  return Math.min(Math.max(Math.floor(raw), 1), 24 * 60)
}

export function startSoftDeleteCron(log: FastifyBaseLogger): void {
  if (cronTask) {
    log.warn('soft-delete cron already started — skipping duplicate init')
    return
  }
  const minutes = resolveSweepMinutes()
  // node-cron uses minute granularity; `*/N * * * *` runs every N minutes.
  const expression = minutes >= 60 ? `0 */${Math.floor(minutes / 60)} * * *` : `*/${minutes} * * * *`
  cronTask = cron.schedule(
    expression,
    () => {
      void runSoftDeleteSweep(log)
    },
    { timezone: 'UTC' },
  )
  log.info({ minutes }, 'cron: soft-delete hard-erase sweep started')
}

/**
 * Find accounts past their scheduled hard-erase time and erase each. Public for
 * manual invocation (admin/tests). Overlap-guarded: a still-running sweep makes
 * the next tick a no-op. Returns a summary for logging/assertions.
 */
export async function runSoftDeleteSweep(log: FastifyBaseLogger): Promise<{
  scanned: number
  erased: number
  failed: number
  skipped: boolean
}> {
  if (sweepRunning) {
    log.warn('soft-delete sweep overlap — previous run still in progress, skipping')
    return { scanned: 0, erased: 0, failed: 0, skipped: true }
  }
  sweepRunning = true
  try {
    return await processScheduledErasures(log)
  } finally {
    sweepRunning = false
  }
}

/**
 * Core sweep without the overlap guard (so tests can call it directly). Selects
 * soft-deleted users whose scheduledHardEraseAt is due and erases them
 * best-effort.
 */
export async function processScheduledErasures(log: FastifyBaseLogger): Promise<{
  scanned: number
  erased: number
  failed: number
  skipped: boolean
}> {
  const now = new Date()
  const due = await prisma.user.findMany({
    where: {
      softDeletedAt: { not: null },
      scheduledHardEraseAt: { lte: now },
    },
    select: { id: true },
    take: SWEEP_BATCH_SIZE,
  })

  let erased = 0
  let failed = 0
  for (const u of due) {
    try {
      await eraseUser(u.id, log)
      erased++
    } catch (err) {
      // One user's failure must not abort the batch; the next sweep retries it.
      failed++
      log.error({ err: String((err as Error)?.message ?? err), userId: u.id }, 'soft-delete sweep: erase failed')
    }
  }

  if (due.length > 0) {
    log.info({ scanned: due.length, erased, failed }, 'soft-delete sweep batch done')
  }
  return { scanned: due.length, erased, failed, skipped: false }
}
