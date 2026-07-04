import cron, { type ScheduledTask } from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'

import { prisma } from '../lib/prisma'
import {
  createNotificationSafe,
  claimScheduledNotification,
  NotificationType,
} from './notification.service'
import { recomputeChallenge } from './challenge-recalc.service'

/**
 * Challenge ending/ended notifications.
 *
 * - ending_soon: a challenge you're in has <24h left → "ends soon, sprint!".
 * - ended: a challenge just finished (in the last 24h) → final result with the
 *   winner + your rank. Scored challenges get one last recompute first so the
 *   standings in the notification are fresh.
 *
 * Idempotent per (user, challenge) via NotificationSentLog so the twice-daily
 * job never double-notifies. FK-less ledger; one row claims the send.
 */

const HOUR_MS = 3_600_000

let cronTask: ScheduledTask | null = null

function challengeTitle(c: { kind: string; customTitle: string | null }): string {
  if (c.kind === 'custom' && c.customTitle?.trim()) return c.customTitle.trim()
  return 'Challenge'
}

function profileLabel(p: { displayName: string | null; username: string | null } | null): string {
  if (p?.displayName?.trim()) return p.displayName.trim()
  if (p?.username?.trim()) return `@${p.username.trim()}`
  return 'Athlete'
}

export function startChallengeEndingNotificationCron(log: FastifyBaseLogger): void {
  if (cronTask) {
    log.warn('challenge-ending cron already started — skipping duplicate init')
    return
  }
  // Twice daily (11:00 + 23:00 UTC) so an "ending soon" fires within ~12h.
  cronTask = cron.schedule(
    '0 11,23 * * *',
    () => {
      runChallengeEndingNotifications(log).catch((err) => {
        log.error({ err: String(err?.message ?? err) }, 'challenge-ending notifications crashed')
      })
    },
    { timezone: 'UTC' },
  )
  log.info('cron: challenge ending/ended notifications @ 11:00 + 23:00 UTC')
}

/** Public for tests / manual runs. Returns a summary. */
export async function runChallengeEndingNotifications(
  log: FastifyBaseLogger,
): Promise<{ endingSoon: number; ended: number }> {
  const now = new Date()
  const in24h = new Date(now.getTime() + 24 * HOUR_MS)
  const ago24h = new Date(now.getTime() - 24 * HOUR_MS)

  let endingSoonSent = 0
  let endedSent = 0

  // ── Ending soon (<24h left) ────────────────────────────────────────────
  const soon = await prisma.challenge.findMany({
    where: { endsAt: { gt: now, lte: in24h } },
    select: { id: true, kind: true, customTitle: true, endsAt: true, scoringType: true },
  })
  for (const c of soon) {
    const parts = await prisma.challengeParticipant.findMany({
      // Skip soft-deleted/disabled participants — they shouldn't be notified.
      where: { challengeId: c.id, status: 'accepted', user: { status: 'active', softDeletedAt: null } },
      select: { userId: true },
    })
    const title = challengeTitle(c)
    for (const p of parts) {
      const claimed = await claimScheduledNotification(
        p.userId,
        NotificationType.CHALLENGE_ENDING_SOON,
        c.id,
      )
      if (!claimed) continue
      await createNotificationSafe({
        recipientId: p.userId,
        actorId: null,
        type: NotificationType.CHALLENGE_ENDING_SOON,
        payload: { challengeId: c.id, title, endsAt: c.endsAt.toISOString(), scoringType: c.scoringType ?? null },
      })
      endingSoonSent++
    }
  }

  // ── Just ended (in the last 24h) ───────────────────────────────────────
  const ended = await prisma.challenge.findMany({
    where: { endsAt: { gt: ago24h, lte: now } },
    select: { id: true, kind: true, customTitle: true, endsAt: true, scoringType: true },
  })
  for (const c of ended) {
    // Freshen standings for scored challenges before announcing the winner.
    if (c.scoringType) {
      try {
        await recomputeChallenge(c.id)
      } catch (err) {
        log.warn({ err, challengeId: c.id }, 'final recompute failed for ended challenge')
      }
    }
    const parts = await prisma.challengeParticipant.findMany({
      where: {
        challengeId: c.id,
        status: { in: ['accepted', 'completed'] },
        user: { status: 'active', softDeletedAt: null },
      },
      orderBy: [{ rank: 'asc' }],
      include: {
        user: { select: { profile: { select: { displayName: true, username: true } } } },
      },
    })
    if (parts.length === 0) continue

    // Pick the winner. Scored challenges have fresh ranks from the recompute
    // above; legacy/manual ones (scoringType null) never rank participants, so
    // derive standings from summed progress logs (buildStandings parity) rather
    // than defaulting to the earliest joiner. No logged scores → no winner.
    let winner: (typeof parts)[number] | null = null
    if (c.scoringType) {
      winner = parts.find((p) => p.rank === 1) ?? parts[0]
    } else {
      const sums = await prisma.challengeProgressLog.groupBy({
        by: ['userId'],
        where: { challengeId: c.id },
        _sum: { amount: true },
      })
      const totals = new Map(sums.map((s) => [s.userId, Number(s._sum.amount ?? 0)]))
      let best = 0
      for (const p of parts) {
        const total = totals.get(p.userId) ?? 0
        if (total > best) {
          best = total
          winner = p
        }
      }
      // best === 0 → nobody logged anything; announce no winner.
    }
    const winnerName = winner ? profileLabel(winner.user.profile) : null
    const title = challengeTitle(c)
    for (const p of parts) {
      const claimed = await claimScheduledNotification(
        p.userId,
        NotificationType.CHALLENGE_ENDED,
        c.id,
      )
      if (!claimed) continue
      await createNotificationSafe({
        recipientId: p.userId,
        actorId: null,
        type: NotificationType.CHALLENGE_ENDED,
        payload: {
          challengeId: c.id,
          title,
          winnerName,
          myRank: p.rank ?? null,
          youWon: winner ? p.userId === winner.userId : false,
          scoringType: c.scoringType ?? null,
        },
      })
      endedSent++
    }
  }

  if (endingSoonSent > 0 || endedSent > 0) {
    log.info({ endingSoon: endingSoonSent, ended: endedSent }, 'challenge ending/ended notifications sent')
  }
  return { endingSoon: endingSoonSent, ended: endedSent }
}
