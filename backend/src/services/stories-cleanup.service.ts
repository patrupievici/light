import cron, { type ScheduledTask } from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'

import { prisma } from '../lib/prisma'
import { deleteStoryPhoto } from '../lib/post-photo'

/**
 * Hourly sweep that hard-deletes expired stories (rows + on-disk files).
 *
 * Why hourly: TTL is 24h so an hourly granularity means a story lingers at
 * most ~1h past its expiry, which is fine for ephemeral content. Cheaper
 * than every-minute and feed reads already filter on `expiresAt > now`, so
 * users never see expired rows even between sweeps.
 */

let cronTask: ScheduledTask | null = null

export function startStoriesCleanupCron(log: FastifyBaseLogger): void {
  if (cronTask) {
    log.warn('stories cleanup cron already started — skipping duplicate init')
    return
  }
  cronTask = cron.schedule(
    '7 * * * *',
    () => {
      runStoriesCleanup(log).catch((err) => {
        log.error({ err: String(err?.message ?? err) }, 'stories cleanup crashed')
      })
    },
    { timezone: 'UTC' },
  )
  log.info('cron: stories cleanup @ :07 every hour UTC')
}

/**
 * Public for manual invocation (e.g. admin endpoint or tests). Returns a
 * summary so the caller can log/assert.
 */
export async function runStoriesCleanup(log: FastifyBaseLogger): Promise<{
  scanned: number
  filesDeleted: number
  rowsDeleted: number
}> {
  const now = new Date()
  // Limit batch size so a backlog doesn't OOM the box on first run after a
  // long downtime. Next tick picks up the rest.
  const expired = await prisma.story.findMany({
    where: { expiresAt: { lt: now } },
    select: { id: true, imageUrl: true },
    take: 500,
  })

  let filesDeleted = 0
  for (const s of expired) {
    try {
      // Razvan's schema made imageUrl nullable; skip when absent.
      if (s.imageUrl == null) continue
      await deleteStoryPhoto(s.imageUrl)
      filesDeleted++
    } catch (err) {
      // File missing is non-fatal — DB cleanup proceeds regardless.
      log.debug({ err, storyId: s.id }, 'story file cleanup miss')
    }
  }

  const result = await prisma.story.deleteMany({
    where: { id: { in: expired.map((s) => s.id) } },
  })

  if (expired.length > 0) {
    log.info(
      { scanned: expired.length, filesDeleted, rowsDeleted: result.count },
      'stories cleanup batch done',
    )
  }
  return { scanned: expired.length, filesDeleted, rowsDeleted: result.count }
}
