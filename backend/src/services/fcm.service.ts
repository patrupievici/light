import type { Notification as DbNotification } from '@prisma/client'
import { GoogleAuth } from 'google-auth-library'
import { prisma } from '../lib/prisma'
import { getUserDisplayHints, type UserDisplayHint } from '../lib/user-display'

let googleAuth: GoogleAuth | null | undefined

function getAuth(): GoogleAuth | null {
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim()
  const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim()
  if (!projectId || !json) return null
  if (googleAuth === undefined) {
    try {
      googleAuth = new GoogleAuth({
        credentials: JSON.parse(json) as object,
        scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
      })
    } catch {
      googleAuth = null
    }
  }
  return googleAuth
}

export function isFcmConfigured(): boolean {
  return !!getAuth() && !!process.env.FIREBASE_PROJECT_ID?.trim()
}

function actorLabel(h: UserDisplayHint | undefined): string {
  if (!h) return 'Someone'
  const d = h.displayName?.trim()
  if (d) return d
  const u = h.username?.trim()
  if (u) return `@${u}`
  const e = h.emailHint?.trim()
  if (e) return e
  return 'Someone'
}

function payloadToStringData(payload: unknown): Record<string, string> {
  if (!payload || typeof payload !== 'object') return {}
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(payload as Record<string, unknown>)) {
    if (v == null) continue
    out[k] = typeof v === 'string' ? v : JSON.stringify(v)
  }
  return out
}

function buildTitleBody(
  type: string,
  label: string,
  payloadData: Record<string, string>,
): { title: string; body: string } {
  switch (type) {
    case 'friend_request':
      return { title: 'Zvelt', body: `${label} sent you a friend request` }
    case 'friend_accepted':
      return { title: 'Zvelt', body: `${label} accepted your request` }
    case 'post_like':
      return { title: 'Zvelt', body: `${label} liked your post` }
    case 'post_comment': {
      const prev = payloadData.bodyPreview ?? ''
      const short = prev.length > 80 ? `${prev.slice(0, 77)}...` : prev
      return {
        title: 'Zvelt',
        body: short ? `${label}: ${short}` : `${label} commented on your post`,
      }
    }
    case 'dm_message': {
      const prev = payloadData.bodyPreview ?? ''
      const short = prev.length > 90 ? `${prev.slice(0, 87)}...` : prev
      return {
        title: label,
        body: short || 'New message',
      }
    }
    default:
      return { title: 'Zvelt', body: 'You have a new notification' }
  }
}

async function deleteInvalidToken(token: string) {
  try {
    await prisma.userPushToken.deleteMany({ where: { token } })
  } catch {
    /* ignore */
  }
}

async function sendOne(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const auth = getAuth()
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim()
  if (!auth || !projectId) return

  const client = await auth.getClient()
  const access = await client.getAccessToken()
  const bearer = access.token
  if (!bearer) return

  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${bearer}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: { priority: 'HIGH' },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      },
    }),
  })

  if (res.ok) return

  const text = await res.text().catch(() => '')
  if (
    res.status === 404 ||
    text.includes('UNREGISTERED') ||
    text.includes('registration-token-not-registered') ||
    text.includes('Requested entity was not found')
  ) {
    await deleteInvalidToken(token)
  } else {
    console.warn('[fcm] send failed', res.status, text.slice(0, 200))
  }
}

/** Send an arbitrary push to all of a user's registered tokens.
 *  Unlike `sendPushForInAppNotification`, this is NOT tied to a DB notification
 *  row — used for things like the goal-aware daily nudge where the message is
 *  AI-generated and ephemeral. Returns the number of tokens we actually
 *  attempted to send to (0 if FCM not configured / no tokens). */
export async function sendPlainPush(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string> = {},
): Promise<number> {
  if (!isFcmConfigured()) return 0
  const rows = await prisma.userPushToken.findMany({
    where: { userId },
    select: { token: true },
  })
  if (rows.length === 0) return 0
  await Promise.all(rows.map((r) => sendOne(r.token, title, body, data)))
  return rows.length
}

/** După o notificare in-app salvată în DB — trimite push pe toate token-urile userului. */
export async function sendPushForInAppNotification(row: DbNotification): Promise<void> {
  if (!isFcmConfigured()) return

  const rows = await prisma.userPushToken.findMany({
    where: { userId: row.userId },
    select: { token: true },
  })
  if (rows.length === 0) return

  const hints = row.actorId
    ? await getUserDisplayHints([row.actorId])
    : new Map<string, UserDisplayHint>()
  const label = actorLabel(row.actorId ? hints.get(row.actorId) : undefined)

  const payloadData = payloadToStringData(row.payload)
  const { title, body } = buildTitleBody(row.type, label, payloadData)

  const data: Record<string, string> = {
    type: row.type,
    notificationId: row.id,
    ...payloadData,
  }
  if (row.actorId) {
    data.actorId = row.actorId
    const h = hints.get(row.actorId)
    if (h?.username) data.actorUsername = h.username
    if (h?.displayName) data.actorDisplayName = h.displayName ?? ''
  }

  await Promise.all(rows.map((r) => sendOne(r.token, title, body, data)))
}
