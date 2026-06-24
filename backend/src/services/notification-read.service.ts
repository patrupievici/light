import { prisma } from '../lib/prisma'
import { NotificationType } from './notification.service'

/** După accept cerere: marchează notificările friend_request de la acel user ca citite. */
export async function markFriendRequestNotificationsReadForPair(params: {
  recipientUserId: string
  actorUserId: string
}): Promise<void> {
  const { recipientUserId, actorUserId } = params
  await prisma.notification.updateMany({
    where: {
      userId: recipientUserId,
      type: NotificationType.FRIEND_REQUEST,
      actorId: actorUserId,
      readAt: null,
    },
    data: { readAt: new Date() },
  })
}
