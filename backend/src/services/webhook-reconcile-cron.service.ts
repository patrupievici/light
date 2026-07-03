import type { FastifyBaseLogger } from 'fastify'

import { processPending } from './webhook-inbox.service'

/**
 * Scheduled webhook reconciliation / backfill.
 *
 * Why: the aggregator (Terra) webhook handler persists each verified envelope to
 * `webhook_inbox` and processes it inline, fire-and-forget. Inline processing
 * can miss: a transient DB/import hiccup leaves the row `failed`, and a process
 * restart mid-flight can leave a row `received` that nobody ever drained. Without
 * a periodic sweep those rows sit forever and the user silently loses an import.
 *
 * What: every WEBHOOK_RECONCILE_MINUTES (default 15) we call
 * {@link processPending}, which drains rows still in `received`/`failed` under the
 * MAX_ATTEMPTS cap (oldest first). Each row's transition is idempotent and the
 * underlying import upserts on the existing unique index, so a row processed both
 * inline and by this sweep never produces duplicate health rows.
 *
 * This inbox-drain IS the reconciliation: there is currently no provider
 * historical-pull API to backfill from. Deeper per-provider backfill (querying
 * Terra for envelopes we never received at all) is a follow-up — see risks.
 *
 * Safety: best-effort and fully self-contained. The tick never rejects, overlap
 * is guarded (a slow sweep won't stack), and nothing here can crash the server.
 */

const DEFAULT_INTERVAL_MINUTES = 15
const MIN_INTERVAL_MINUTES = 1
const MAX_INTERVAL_MINUTES = 24 * 60 // a day; anything larger is almost certainly a typo

/**
 * Pure helper: resolve the sweep interval (in ms) from a raw env string.
 *
 * - undefined / empty / non-numeric → default (15 min)
 * - clamped to [MIN, MAX] so a `0`, negative, or absurd value can't spin the
 *   loop hot or effectively disable it by accident.
 *
 * Exported for unit testing without standing up timers.
 */
export function resolveReconcileIntervalMs(raw: string | undefined): number {
  const parsed = raw == null ? NaN : Number(raw.trim())
  const minutes = Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_INTERVAL_MINUTES
  const clamped = Math.min(MAX_INTERVAL_MINUTES, Math.max(MIN_INTERVAL_MINUTES, minutes))
  return Math.round(clamped * 60 * 1000)
}

/**
 * Pure helper: an overlap guard. `tryAcquire()` returns true and marks the gate
 * busy only when it was idle; `release()` clears it. This lets the cron skip a
 * tick while the previous sweep is still draining a large backlog instead of
 * running two sweeps concurrently.
 *
 * Exported for unit testing the skip-while-busy behaviour deterministically.
 */
export function createRunGuard(): {
  tryAcquire(): boolean
  release(): void
  readonly isRunning: boolean
} {
  let running = false
  return {
    tryAcquire() {
      if (running) return false
      running = true
      return true
    },
    release() {
      running = false
    },
    get isRunning() {
      return running
    },
  }
}

let timer: NodeJS.Timeout | null = null
const guard = createRunGuard()

/**
 * Run one reconciliation sweep, guarded against overlap. Best-effort: never
 * throws. Skips entirely (logging nothing noisy) if a previous sweep is still
 * in flight. Exported so an admin endpoint or tests can trigger it on demand.
 */
export async function runReconcileSweep(log: FastifyBaseLogger): Promise<void> {
  if (!guard.tryAcquire()) {
    log.info('webhook reconcile: previous sweep still running — skipping this tick')
    return
  }
  try {
    const result = await processPending({ log })
    if (result.picked > 0) {
      log.info(result, 'webhook reconcile: sweep done')
    }
  } catch (err) {
    // processPending is already best-effort, but belt-and-suspenders: a sweep
    // must never bubble an error up to the timer.
    log.error({ err: String((err as any)?.message ?? err) }, 'webhook reconcile: sweep crashed')
  } finally {
    guard.release()
  }
}

/**
 * Start the periodic reconciliation sweep. Idempotent: a second call is a no-op
 * (warns). Uses `unref()` so this timer never holds the process open on its own.
 */
export function startWebhookReconcileCron(log: FastifyBaseLogger): void {
  if (timer) {
    log.warn('webhook reconcile cron already started — skipping duplicate init')
    return
  }
  const intervalMs = resolveReconcileIntervalMs(process.env.WEBHOOK_RECONCILE_MINUTES)
  timer = setInterval(() => {
    runReconcileSweep(log).catch((err) => {
      // runReconcileSweep already swallows errors; this is a final guard.
      log.error({ err: String(err?.message ?? err) }, 'webhook reconcile cron crashed')
    })
  }, intervalMs)
  // Don't keep the event loop alive solely for this background sweep.
  timer.unref?.()
  log.info({ intervalMs }, `cron: webhook reconcile every ${Math.round(intervalMs / 60000)} min`)
}

