import { Prisma } from '@prisma/client'

import { prisma } from '../lib/prisma'
import { sendPushForInAppNotification } from './fcm.service'

export const NotificationType = {
  FRIEND_REQUEST: 'friend_request',
  FRIEND_ACCEPTED: 'friend_accepted',
  POST_LIKE: 'post_like',
  POST_COMMENT: 'post_comment',
  DM_MESSAGE: 'dm_message',
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
