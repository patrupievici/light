import { FastifyInstance } from 'fastify'
import { Prisma } from '@prisma/client'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { createNotificationSafe, NotificationType } from '../services/notification.service'
import { markFriendRequestNotificationsReadForPair } from '../services/notification-read.service'
import { getUserDisplayHints } from '../lib/user-display'
import { acceptedFriendIds } from '../lib/friendships'

const UserIdBody = z.object({
  userId: z.string().uuid(),
})

export async function friendRoutes(app: FastifyInstance) {
  // GET /v1/friends — prieteni acceptați
  app.get('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user

    const ids = await acceptedFriendIds(me)
    const hints = await getUserDisplayHints(ids)

    const data = ids.map((id) => ({
      userId: id,
      username: hints.get(id)?.username ?? null,
      displayName: hints.get(id)?.displayName ?? null,
      emailHint: hints.get(id)?.emailHint ?? null,
    }))

    return reply.send({ data })
  })

  // GET /v1/friends/search?query= — după username (prefix), exclude self
  app.get('/search', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const q = ((request.query as { query?: string })?.query ?? '').trim()

    if (q.length < 2) {
      return reply.send({ data: [] })
    }

    const profiles = await prisma.userProfile.findMany({
      where: {
        userId: { not: me },
        discoveryOptIn: true,
        username: { not: null, startsWith: q, mode: 'insensitive' },
      },
      take: 20,
      select: { userId: true, username: true, displayName: true },
      orderBy: { username: 'asc' },
    })

    const hintMap = await getUserDisplayHints(profiles.map((p) => p.userId))

    return reply.send({
      data: profiles.map((p) => ({
        userId: p.userId,
        username: p.username,
        displayName: p.displayName,
        emailHint: hintMap.get(p.userId)?.emailHint ?? null,
      })),
    })
  })

  // GET /v1/friends/requests/incoming
  app.get('/requests/incoming', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user

    const rows = await prisma.friendship.findMany({
      where: { friendUserId: me, status: 'requested' },
      orderBy: { createdAt: 'desc' },
    })

    const ids = rows.map((r) => r.userId)
    const hints = await getUserDisplayHints(ids)

    const data = rows.map((r) => ({
      friendshipId: r.id,
      userId: r.userId,
      username: hints.get(r.userId)?.username ?? null,
      displayName: hints.get(r.userId)?.displayName ?? null,
      emailHint: hints.get(r.userId)?.emailHint ?? null,
      createdAt: r.createdAt.toISOString(),
    }))

    return reply.send({ data })
  })

  // GET /v1/friends/requests/outgoing
  app.get('/requests/outgoing', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user

    const rows = await prisma.friendship.findMany({
      where: { userId: me, status: 'requested' },
      orderBy: { createdAt: 'desc' },
    })

    const ids = rows.map((r) => r.friendUserId)
    const hints = await getUserDisplayHints(ids)

    const data = rows.map((r) => ({
      friendshipId: r.id,
      userId: r.friendUserId,
      username: hints.get(r.friendUserId)?.username ?? null,
      displayName: hints.get(r.friendUserId)?.displayName ?? null,
      emailHint: hints.get(r.friendUserId)?.emailHint ?? null,
      createdAt: r.createdAt.toISOString(),
    }))

    return reply.send({ data })
  })

  // POST /v1/friends/requests — trimite cerere
  app.post('/requests', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const parsed = UserIdBody.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'userId invalid',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const target = parsed.data.userId
    if (target === me) {
      return reply.code(400).send({
        error: 'INVALID_TARGET',
        message: 'Nu te poți adăuga pe tine însuți',
        requestId: request.id,
      })
    }

    const exists = await prisma.user.findUnique({ where: { id: target }, select: { id: true } })
    if (!exists) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Utilizator inexistent',
        requestId: request.id,
      })
    }

    const existing = await prisma.friendship.findFirst({
      where: {
        OR: [
          { userId: me, friendUserId: target },
          { userId: target, friendUserId: me },
        ],
      },
    })

    if (existing?.status === 'accepted') {
      return reply.code(409).send({
        error: 'ALREADY_FRIENDS',
        message: 'Sunteți deja prieteni',
        requestId: request.id,
      })
    }

    if (existing?.status === 'requested') {
      if (existing.userId === me) {
        return reply.code(409).send({
          error: 'REQUEST_PENDING',
          message: 'Cererea a fost deja trimisă',
          requestId: request.id,
        })
      }
      // Ei ți-au trimis ție — acceptăm automat
      await prisma.friendship.update({
        where: { id: existing.id },
        data: { status: 'accepted' },
      })
      await createNotificationSafe({
        recipientId: existing.userId,
        actorId: me,
        type: NotificationType.FRIEND_ACCEPTED,
        payload: { friendshipId: existing.id },
      })
      await markFriendRequestNotificationsReadForPair({
        recipientUserId: me,
        actorUserId: existing.userId,
      })
      return reply.code(201).send({ status: 'accepted', friendshipId: existing.id })
    }

    if (existing?.status === 'blocked') {
      return reply.code(403).send({
        error: 'BLOCKED',
        message: 'Nu poți trimite cerere',
        requestId: request.id,
      })
    }

    const created = await prisma.friendship.create({
      data: { userId: me, friendUserId: target, status: 'requested' },
    })

    await createNotificationSafe({
      recipientId: target,
      actorId: me,
      type: NotificationType.FRIEND_REQUEST,
      payload: { friendshipId: created.id },
    })

    return reply.code(201).send({ status: 'requested', friendshipId: created.id })
  })

  // POST /v1/friends/accept — acceptă cererea de la userId (cel care a trimis)
  app.post('/accept', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const parsed = UserIdBody.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'userId invalid',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const from = parsed.data.userId
    const row = await prisma.friendship.findFirst({
      where: { userId: from, friendUserId: me, status: 'requested' },
    })

    if (!row) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Nicio cerere de la acest utilizator',
        requestId: request.id,
      })
    }

    await prisma.friendship.update({
      where: { id: row.id },
      data: { status: 'accepted' },
    })

    await createNotificationSafe({
      recipientId: from,
      actorId: me,
      type: NotificationType.FRIEND_ACCEPTED,
      payload: { friendshipId: row.id },
    })

    await markFriendRequestNotificationsReadForPair({
      recipientUserId: me,
      actorUserId: from,
    })

    return reply.send({ ok: true, friendshipId: row.id })
  })

  // DELETE /v1/friends/:userId — unfriend sau anulează cererea trimisă
  app.delete('/:userId', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const other = (request.params as { userId: string }).userId

    const res = await prisma.friendship.deleteMany({
      where: {
        OR: [
          { userId: me, friendUserId: other },
          { userId: other, friendUserId: me },
        ],
      },
    })

    if (res.count === 0) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Nu există relație cu acest utilizator',
        requestId: request.id,
      })
    }

    return reply.send({ ok: true })
  })

  // GET /v1/friends/streaks — streak curent al fiecărui prieten acceptat
  app.get('/streaks', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const friendIds = await acceptedFriendIds(me)
    if (friendIds.length === 0) return reply.send({ data: [] })

    const hints = await getUserDisplayHints(friendIds)

    // Calculate streak per friend: consecutive days with at least one completed/posted workout.
    // One bounded query for all friends: distinct (user_id, UTC day) within the last 40 days.
    // The 40-day bound only caps streaks longer than 40 days (accepted UI trade-off).
    // started_at is `timestamp without time zone` storing UTC, so to_char on it
    // yields the UTC calendar date directly — exactly matching the previous
    // JS `startedAt.toISOString().slice(0, 10)` keying, with no session-timezone
    // or driver Date-parsing dependence.
    const dayRows = await prisma.$queryRaw<{ user_id: string; day: string }[]>`
      SELECT DISTINCT user_id, to_char(started_at, 'YYYY-MM-DD') AS day
      FROM workouts
      WHERE user_id IN (${Prisma.join(friendIds)})
        AND status IN ('completed', 'posted')
        AND started_at >= now() - interval '40 days'
    `
    const daysByFriend = new Map<string, Set<string>>()
    for (const row of dayRows) {
      const dayStr = row.day
      let set = daysByFriend.get(row.user_id)
      if (!set) {
        set = new Set<string>()
        daysByFriend.set(row.user_id, set)
      }
      set.add(dayStr)
    }

    const streakResults = friendIds.map((fid) => {
      const days = Array.from(daysByFriend.get(fid) ?? []).sort().reverse()

      let streak = 0
      const today = new Date()
      today.setUTCHours(0, 0, 0, 0)

      for (let i = 0; i < days.length; i++) {
        const expected = new Date(today)
        expected.setUTCDate(expected.getUTCDate() - i)
        const expectedStr = expected.toISOString().slice(0, 10)
        if (days[i] === expectedStr) {
          streak++
        } else {
          // Allow 1-day gap for today (streak "at risk" still counts)
          if (i === 0 && days[0] !== expectedStr) {
            // Check yesterday
            const yesterday = new Date(today)
            yesterday.setUTCDate(yesterday.getUTCDate() - 1)
            if (days[0] === yesterday.toISOString().slice(0, 10)) {
              streak++
              continue
            }
          }
          break
        }
      }

      return {
        userId: fid,
        displayName: hints.get(fid)?.displayName ?? hints.get(fid)?.username ?? 'Athlete',
        username: hints.get(fid)?.username ?? null,
        currentStreak: streak,
      }
    })

    return reply.send({ data: streakResults })
  })

  // GET /v1/friends/activity — câți prieteni au antrenat azi (UTC)
  app.get('/activity', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const friendIds = await acceptedFriendIds(me)
    if (friendIds.length === 0) return reply.send({ data: { todayCount: 0 } })

    const todayStart = new Date()
    todayStart.setUTCHours(0, 0, 0, 0)

    const count = await prisma.workout.groupBy({
      by: ['userId'],
      where: {
        userId: { in: friendIds },
        status: { in: ['completed', 'posted'] },
        startedAt: { gte: todayStart },
      },
    })

    return reply.send({ data: { todayCount: count.length } })
  })
}
