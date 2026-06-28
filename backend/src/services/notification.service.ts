import { Prisma } from '@prisma/client'

import { prisma } from '../lib/prisma'
import { sendPushForInAppNotification } from './fcm.service'

export const NotificationType = {
  FRIEND_REQUEST: 'friend_request',
  FRIEND_ACCEPTED: 'friend_accepted',
  POST_LIKE: 'post_like',
  POST_COMMENT: 'post_comment',
  DM_MESSAGE: 'dm_message',
  CHALLENGE_INVITE: 'challenge_invite',
  CHALLENGE_JOINED: 'challenge_joined',
  STREAK_RISK: 'streak_risk',
  CHALLENGE_ENDING_SOON: 'challenge_ending_soon',
  CHALLENGE_ENDED: 'challenge_ended',
} as const

/** Nu aruncă — notificarea nu trebuie să blocheze fluxul principal. */
export async function createNotificationSafe(params: {
  recipientId: string
  actorId: string | null | undefined
  type: string
  payload?: Record<string, unknown>
}): Promise<void> {
  const { recipientId, actorId, type, payload = {} } = params
  if (actorId && recipientId === actorId) return
  try {
    const row = await prisma.notification.create({
      data: {
        userId: recipientId,
        type,
        actorId: actorId ?? null,
        payload: payload as Prisma.InputJsonValue,
      },
    })
    void sendPushForInAppNotification(row).catch((e) => console.error('[fcm] push', e))
  } catch (err) {
    console.error('[notification] create failed', err)
  }
}

/**
 * Atomically claim a scheduled-notification slot. Inserts a NotificationSentLog
 * row (unique on userId+type+dedupeKey); returns true if this caller won the
 * slot (should send), false if it was already claimed (a cron re-run / restart
 * already sent it). The unique-constraint insert is the lock — no read-then-write
 * race.
 */
export async function claimScheduledNotification(
  userId: string,
  type: string,
  dedupeKey: string,
): Promise<boolean> {
  try {
    await prisma.notificationSentLog.create({ data: { userId, type, dedupeKey } })
    return true
  } catch {
    // Unique violation (already claimed) — or any DB hiccup; treat as "skip".
    return false
  }
}
