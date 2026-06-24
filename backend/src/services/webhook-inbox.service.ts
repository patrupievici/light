import type { FastifyBaseLogger } from 'fastify'
import { prisma } from '../lib/prisma'
import { persistTerraDataPayload } from '../routes/integrations'

/**
 * Durable raw-envelope webhook inbox.
 *
 * The aggregator (Terra) webhook handler persists every verified envelope to
 * `webhook_inbox` (status `received`) BEFORE doing any work, then acks the
 * provider with a fast 200. The actual import is deferred to this service so a
 * processing failure never costs us the envelope — it stays on disk for retry.
 *
 * Processing is triggered two ways:
 *  - inline, fire-and-forget, right after the envelope is stored (low latency
 *    in the happy path), and
 *  - via {@link processPending}, drained by a cron/worker, which sweeps up
 *    anything that was never processed inline or that previously failed.
 *
 * Idempotency is inherited from the import layer: `persistTerraDataPayload`
 * upserts on the existing `user_health_imports` unique index, so reprocessing
 * the same envelope never duplicates rows.
 */

export const WEBHOOK_INBOX_CONSTANTS = {
  /**
   * After this many failed attempts a row is left in `failed` and no longer
   * picked up by {@link processPending} — it needs human/manual attention
   * rather than burning more retries on a deterministic failure.
   */
  MAX_ATTEMPTS: 5,
  /** Default batch size for a single {@link processPending} sweep. */
  DEFAULT_BATCH_SIZE: 50,
} as const

const NOOP_LOG: Pick<FastifyBaseLogger, 'error' | 'warn' | 'info'> = {
  error: () => {},
  warn: () => {},
  info: () => {},
}

type InboxLogger = Pick<FastifyBaseLogger, 'error' | 'warn' | 'info'>

export type ProcessInboxResult =
  | { status: 'processed'; imported: number }
  | { status: 'failed'; error: string }
  | { status: 'skipped'; reason: 'not_found' | 'already_processed' | 'max_attempts' }

/**
 * Process a single inbox row by id. Loads the row, runs the wave-1 persist
 * logic against the stored payload, and transitions the row to `processed`
 * (with `processedAt`) on success or `failed` (incrementing `attempts` and
 * storing the error) on failure.
 *
 * Never throws: callers (inline fire-and-forget + cron) treat this as
 * best-effort. The outcome is reported via the returned status.
 */
export async function processInboxItem(
  id: string,
  log: InboxLogger = NOOP_LOG,
): Promise<ProcessInboxResult> {
  let row: {
    id: string
    status: string
    attempts: number
    payload: unknown
  } | null = null
  try {
    row = await prisma.webhookInbox.findUnique({
      where: { id },
      select: { id: true, status: true, attempts: true, payload: true },
    })
  } catch (err) {
    log.error({ err, inboxId: id }, 'webhook inbox: load failed')
    return { status: 'failed', error: errorMessage(err) }
  }

  if (!row) return { status: 'skipped', reason: 'not_found' }
  if (row.status === 'processed') return { status: 'skipped', reason: 'already_processed' }
  if (row.attempts >= WEBHOOK_INBOX_CONSTANTS.MAX_ATTEMPTS) {
    return { status: 'skipped', reason: 'max_attempts' }
  }

  try {
    const imported = await persistTerraDataPayload(row.payload as any, log as FastifyBaseLogger)
    await prisma.webhookInbox.update({
      where: { id: row.id },
      data: {
        status: 'processed',
        processedAt: new Date(),
        attempts: { increment: 1 },
        error: null,
      },
    })
    return { status: 'processed', imported }
  } catch (err) {
    const message = errorMessage(err)
    log.error({ err, inboxId: id }, 'webhook inbox: processing failed')
    // Best-effort failure bookkeeping; if even this write fails the row simply
    // stays `received`/`failed` and gets retried on the next sweep.
    try {
      await prisma.webhookInbox.update({
        where: { id: row.id },
        data: {
          status: 'failed',
          attempts: { increment: 1 },
          error: message.slice(0, 2000),
        },
      })
    } catch (bookkeepErr) {
      log.error({ err: bookkeepErr, inboxId: id }, 'webhook inbox: failure bookkeeping failed')
    }
    return { status: 'failed', error: message }
  }
}

export type ProcessPendingResult = {
  picked: number
  processed: number
  failed: number
  skipped: number
}

/**
 * Drain pending inbox rows: anything in `received` or `failed` that has not yet
 * exhausted its attempt budget, oldest first. Intended for a cron/worker; safe
 * to run concurrently with inline processing because each row's transition is
 * idempotent and the underlying import upserts.
 */
export async function processPending(
  opts: { limit?: number; log?: InboxLogger } = {},
): Promise<ProcessPendingResult> {
  const limit = opts.limit ?? WEBHOOK_INBOX_CONSTANTS.DEFAULT_BATCH_SIZE
  const log = opts.log ?? NOOP_LOG
  const result: ProcessPendingResult = { picked: 0, processed: 0, failed: 0, skipped: 0 }

  let rows: Array<{ id: string }>
  try {
    rows = await prisma.webhookInbox.findMany({
      where: {
        status: { in: ['received', 'failed'] },
        attempts: { lt: WEBHOOK_INBOX_CONSTANTS.MAX_ATTEMPTS },
      },
      orderBy: { receivedAt: 'asc' },
      take: limit,
      select: { id: true },
    })
  } catch (err) {
    log.error({ err }, 'webhook inbox: pending scan failed')
    return result
  }

  result.picked = rows.length
  for (const row of rows) {
    const outcome = await processInboxItem(row.id, log)
    if (outcome.status === 'processed') result.processed++
    else if (outcome.status === 'failed') result.failed++
    else result.skipped++
  }

  if (result.failed > 0) {
    log.warn(result, 'webhook inbox: sweep completed with failures')
  }
  return result
}

function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message
  if (typeof err === 'string') return err
  try {
    return JSON.stringify(err)
  } catch {
    return 'unknown error'
  }
}
