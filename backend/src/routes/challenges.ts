import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { acceptedFriendIds } from '../lib/friendships'

const CreateChallengeSchema = z
  .object({
    kind: z.enum(['pullUps', 'deadlift', 'squat', 'benchPress', 'custom']),
    customTitle: z.string().max(80).optional(),
    visibility: z.enum(['friends', 'public']),
    targetHint: z.string().max(60).optional(),
    durationDays: z.number().int().min(1).max(365),
  })
  .superRefine((val, ctx) => {
    if (val.kind === 'custom') {
      const t = val.customTitle?.trim()
      if (!t) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'Titlul e obligatoriu pentru provocare custom.',
          path: ['customTitle'],
        })
      }
    }
  })

function creatorLabel(profile: { username: string | null; displayName: string | null } | null): string {
  if (!profile) return 'Athlete'
  const d = profile.displayName?.trim()
  if (d) return d
  const u = profile.username?.trim()
  if (u) return u
  return 'Athlete'
}

function serializeChallenge(
  row: {
    id: string
    creatorId: string
    kind: string
    customTitle: string | null
    visibility: string
    targetHint: string | null
    durationDays: number
    endsAt: Date
    createdAt: Date
    creator: {
      profile: { username: string | null; displayName: string | null } | null
    }
  },
  viewerId: string,
) {
  const title =
    row.kind === 'custom' && row.customTitle?.trim()
      ? row.customTitle.trim()
      : defaultTitle(row.kind)

  return {
    id: row.id,
    creatorId: row.creatorId,
    creatorDisplayName: creatorLabel(row.creator.profile),
    isMine: row.creatorId === viewerId,
    kind: row.kind,
    customTitle: row.customTitle ?? '',
    title,
    visibility: row.visibility,
    targetHint: row.targetHint,
    durationDays: row.durationDays,
    createdAt: row.createdAt.toISOString(),
    endsAt: row.endsAt.toISOString(),
  }
}

function defaultTitle(kind: string): string {
  switch (kind) {
    case 'pullUps':
      return 'Pull-up challenge'
    case 'deadlift':
      return 'Deadlift challenge'
    case 'squat':
      return 'Squat challenge'
    case 'benchPress':
      return 'Bench press challenge'
    case 'custom':
      return 'Challenge'
    default:
      return 'Challenge'
  }
}

/// Validates the `:id` route param as a UUID. Returns the id, or sends the
/// 400 and returns null (caller must early-return on null).
function requireUuidParam(request: any, reply: any): string | null {
  const id = (request.params as { id?: string }).id
  if (!id || !z.string().uuid().safeParse(id).success) {
    reply.code(400).send({ error: 'VALIDATION_ERROR', message: 'ID invalid', requestId: request.id })
    return null
  }
  return id
}

export async function challengeRoutes(app: FastifyInstance) {
  // POST /v1/challenges
  app.post('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CreateChallengeSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const { kind, customTitle, visibility, targetHint, durationDays } = parsed.data
    const customDb = kind === 'custom' ? customTitle!.trim() : customTitle?.trim() ? customTitle.trim() : null
    const hintDb = targetHint?.trim() ? targetHint.trim().slice(0, 120) : null

    const createdAt = new Date()
    const endsAt = new Date(createdAt.getTime() + durationDays * 86_400_000)

    const row = await prisma.challenge.create({
      data: {
        creatorId: userId,
        kind,
        customTitle: customDb,
        visibility,
        targetHint: hintDb,
        durationDays,
        endsAt,
      },
      include: {
        creator: {
          select: {
            profile: { select: { username: true, displayName: true } },
          },
        },
      },
    })

    return reply.code(201).send({
      data: serializeChallenge(row, userId),
      requestId: request.id,
    })
  })

  // GET /v1/challenges/feed — active (endsAt > now), vizibile pentru viewer
  app.get('/feed', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const friendIds = await acceptedFriendIds(me)
    const now = new Date()

    const rows = await prisma.challenge.findMany({
      where: {
        endsAt: { gt: now },
        OR: [{ creatorId: me }, { visibility: 'public' }, { visibility: 'friends', creatorId: { in: friendIds } }],
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: {
        creator: {
          select: {
            profile: { select: { username: true, displayName: true } },
          },
        },
      },
    })

    const data = rows.map((r) => serializeChallenge(r, me))
    return reply.send({ data, requestId: request.id })
  })

  // POST /v1/challenges/:id/join
  app.post('/:id/join', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const challenge = await loadVisibleChallenge(request, reply)
    if (!challenge) return
    if (challenge.endsAt <= new Date()) {
      return reply.code(400).send({ error: 'CHALLENGE_EXPIRED', message: 'Provocarea a expirat', requestId: request.id })
    }
    const existing = await prisma.challengeParticipant.findUnique({
      where: { challengeId_userId: { challengeId: challenge.id, userId: me } },
    })
    if (existing) {
      return reply.send({ message: 'already joined', data: { challengeId: challenge.id, userId: me, joinedAt: existing.joinedAt.toISOString() } })
    }
    const participant = await prisma.challengeParticipant.create({
      data: { challengeId: challenge.id, userId: me },
    })
    return reply.code(201).send({ data: { challengeId: challenge.id, userId: me, joinedAt: participant.joinedAt.toISOString() } })
  })

  // DELETE /v1/challenges/:id/leave
  app.delete('/:id/leave', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const id = requireUuidParam(request, reply)
    if (!id) return
    await prisma.challengeParticipant.deleteMany({
      where: { challengeId: id, userId: me },
    })
    return reply.code(204).send()
  })

  // GET /v1/challenges/:id/participants
  app.get('/:id/participants', { preHandler: authenticate }, async (request, reply) => {
    const challenge = await loadVisibleChallenge(request, reply)
    if (!challenge) return
    const participants = await prisma.challengeParticipant.findMany({
      where: { challengeId: challenge.id },
      orderBy: { joinedAt: 'asc' },
      include: {
        user: { select: { profile: { select: { username: true, displayName: true } } } },
      },
    })
    const data = participants.map((p) => ({
      userId: p.userId,
      displayName: p.user.profile?.displayName ?? p.user.profile?.username ?? 'Athlete',
      username: p.user.profile?.username ?? null,
      joinedAt: p.joinedAt.toISOString(),
    }))
    return reply.send({ data, total: data.length, requestId: request.id })
  })

  /// Shared access gate for progress/standings/chat: challenge must exist
  /// and be visible to the viewer (public, mine, or friend's). Returns the
  /// challenge row or replies with the error and returns null.
  async function loadVisibleChallenge(request: any, reply: any): Promise<{ id: string; creatorId: string; visibility: string; endsAt: Date } | null> {
    const { userId: me } = request.user
    const id = requireUuidParam(request, reply)
    if (!id) return null
    const challenge = await prisma.challenge.findUnique({ where: { id } })
    if (!challenge) {
      reply.code(404).send({ error: 'NOT_FOUND', message: 'Provocarea nu există', requestId: request.id })
      return null
    }
    if (challenge.visibility === 'friends' && challenge.creatorId !== me) {
      const friendIds = await acceptedFriendIds(me)
      if (!friendIds.includes(challenge.creatorId)) {
        reply.code(403).send({ error: 'FORBIDDEN', message: 'Nu ai acces la această provocare', requestId: request.id })
        return null
      }
    }
    return challenge
  }

  /// Access gate for owner-only mutations (delete): challenge must exist and
  /// be owned by the viewer. Returns the row or replies with the error and
  /// returns null. Keeps its own ownership 403 distinct from visibility 403.
  async function loadOwnedChallenge(request: any, reply: any): Promise<{ id: string; creatorId: string } | null> {
    const { userId: me } = request.user
    const id = requireUuidParam(request, reply)
    if (!id) return null
    const challenge = await prisma.challenge.findUnique({ where: { id } })
    if (!challenge) {
      reply.code(404).send({ error: 'NOT_FOUND', message: 'Provocarea nu există', requestId: request.id })
      return null
    }
    if (challenge.creatorId !== me) {
      reply.code(403).send({ error: 'FORBIDDEN', message: 'Nu poți șterge provocarea altcuiva', requestId: request.id })
      return null
    }
    return challenge
  }

  /// Standings rows: every participant + SUM of their progress logs,
  /// sorted desc. Participants with no logs appear with total 0 (joined
  /// counts — design shows the full roster).
  async function buildStandings(challengeId: string) {
    const [participants, sums] = await Promise.all([
      prisma.challengeParticipant.findMany({
        where: { challengeId },
        include: {
          user: { select: { profile: { select: { username: true, displayName: true } } } },
        },
        orderBy: { joinedAt: 'asc' },
      }),
      prisma.challengeProgressLog.groupBy({
        by: ['userId'],
        where: { challengeId },
        _sum: { amount: true },
        _max: { createdAt: true },
      }),
    ])
    const totals = new Map(sums.map((s) => [s.userId, { total: Number(s._sum.amount ?? 0), lastAt: s._max.createdAt }]))
    const rows = participants.map((p) => ({
      userId: p.userId,
      displayName: p.user.profile?.displayName ?? p.user.profile?.username ?? 'Athlete',
      username: p.user.profile?.username ?? null,
      total: totals.get(p.userId)?.total ?? 0,
      lastLoggedAt: totals.get(p.userId)?.lastAt?.toISOString() ?? null,
      joinedAt: p.joinedAt.toISOString(),
    }))
    rows.sort((a, b) => b.total - a.total)
    return rows
  }

  // POST /v1/challenges/:id/progress — log progress (auto-joins the race).
  app.post('/:id/progress', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const challenge = await loadVisibleChallenge(request, reply)
    if (!challenge) return
    if (challenge.endsAt <= new Date()) {
      return reply.code(400).send({ error: 'CHALLENGE_EXPIRED', message: 'Provocarea a expirat', requestId: request.id })
    }
    const parsed = z.object({ amount: z.number().positive().max(100_000) }).safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body: amount (0 < n ≤ 100000)',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    // Logging progress implies participation — upsert keeps it idempotent.
    await prisma.challengeParticipant.upsert({
      where: { challengeId_userId: { challengeId: challenge.id, userId: me } },
      create: { challengeId: challenge.id, userId: me },
      update: {},
    })
    await prisma.challengeProgressLog.create({
      data: { challengeId: challenge.id, userId: me, amount: parsed.data.amount },
    })
    const rows = await buildStandings(challenge.id)
    const myRank = rows.findIndex((r) => r.userId === me) + 1
    const mine = rows.find((r) => r.userId === me)
    return reply.code(201).send({
      data: { total: mine?.total ?? parsed.data.amount, rank: myRank, participants: rows.length },
      requestId: request.id,
    })
  })

  // GET /v1/challenges/:id/standings — full roster with totals + my rank.
  app.get('/:id/standings', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const challenge = await loadVisibleChallenge(request, reply)
    if (!challenge) return
    const rows = await buildStandings(challenge.id)
    const myIdx = rows.findIndex((r) => r.userId === me)
    return reply.send({
      data: rows,
      me: myIdx >= 0 ? { rank: myIdx + 1, total: rows[myIdx].total } : null,
      requestId: request.id,
    })
  })

  // GET /v1/challenges/:id/messages?limit=&before= — shared race chat.
  app.get('/:id/messages', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const challenge = await loadVisibleChallenge(request, reply)
    if (!challenge) return
    const q = request.query as { limit?: string; before?: string }
    const limit = Math.min(100, Math.max(1, parseInt(q.limit ?? '50', 10) || 50))
    const before = q.before ? new Date(q.before) : null
    const messages = await prisma.challengeMessage.findMany({
      where: {
        challengeId: challenge.id,
        ...(before && !isNaN(before.getTime()) ? { createdAt: { lt: before } } : {}),
      },
      include: {
        user: { select: { profile: { select: { username: true, displayName: true } } } },
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
    })
    // Oldest-first for direct rendering.
    messages.reverse()
    return reply.send({
      data: messages.map((m) => ({
        id: m.id,
        userId: m.userId,
        displayName: m.user.profile?.displayName ?? m.user.profile?.username ?? 'Athlete',
        username: m.user.profile?.username ?? null,
        body: m.body,
        createdAt: m.createdAt.toISOString(),
        mine: m.userId === me,
      })),
      requestId: request.id,
    })
  })

  // POST /v1/challenges/:id/messages — send to the race chat (auto-joins).
  app.post('/:id/messages', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const challenge = await loadVisibleChallenge(request, reply)
    if (!challenge) return
    const parsed = z.object({ body: z.string().trim().min(1).max(500) }).safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body: body (1–500 chars)',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    await prisma.challengeParticipant.upsert({
      where: { challengeId_userId: { challengeId: challenge.id, userId: me } },
      create: { challengeId: challenge.id, userId: me },
      update: {},
    })
    const saved = await prisma.challengeMessage.create({
      data: { challengeId: challenge.id, userId: me, body: parsed.data.body },
      include: {
        user: { select: { profile: { select: { username: true, displayName: true } } } },
      },
    })
    return reply.code(201).send({
      data: {
        id: saved.id,
        userId: saved.userId,
        displayName: saved.user.profile?.displayName ?? saved.user.profile?.username ?? 'Athlete',
        username: saved.user.profile?.username ?? null,
        body: saved.body,
        createdAt: saved.createdAt.toISOString(),
        mine: true,
      },
      requestId: request.id,
    })
  })

  // DELETE /v1/challenges/:id — doar creatorul
  app.delete('/:id', { preHandler: authenticate }, async (request, reply) => {
    const challenge = await loadOwnedChallenge(request, reply)
    if (!challenge) return

    await prisma.challenge.delete({ where: { id: challenge.id } })
    return reply.code(204).send()
  })
}
