import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { acceptedFriendIds } from '../lib/friendships'
import { recomputeChallenge } from '../services/challenge-recalc.service'
import { createNotificationSafe, claimScheduledNotification, NotificationType } from '../services/notification.service'

const CreateChallengeSchema = z
  .object({
    kind: z.enum(['pullUps', 'deadlift', 'squat', 'benchPress', 'custom']),
    customTitle: z.string().max(80).optional(),
    visibility: z.enum(['friends', 'public']),
    targetHint: z.string().max(60).optional(),
    durationDays: z.number().int().min(1).max(365),
    // ── Auto-scoring (Feed & Challenges v1) — optional; absent = legacy/manual.
    scoringType: z
      .enum(['workout_streak', 'most_workouts', 'total_volume', 'pr_battle', 'consistency'])
      .optional(),
    startsAt: z.string().datetime().optional(),
    rules: z
      .object({
        minDurationMin: z.number().int().min(0).max(600),
        minSets: z.number().int().min(0).max(100),
        minExercises: z.number().int().min(0).max(50),
        maxPerDay: z.number().int().min(1).max(10),
      })
      .partial()
      .optional(),
    exerciseId: z.string().uuid().optional(), // pr_battle target
    targetDays: z.number().int().min(1).max(31).optional(), // consistency target
    inviteUserIds: z.array(z.string().uuid()).max(20).optional(),
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

/// Display label for a (possibly missing) profile: trimmed displayName, else
/// trimmed username, else 'Athlete'. One helper for every roster/creator label.
function profileLabel(profile: { username: string | null; displayName: string | null } | null): string {
  const d = profile?.displayName?.trim()
  if (d) return d
  const u = profile?.username?.trim()
  if (u) return u
  return 'Athlete'
}

/// Human title for a challenge row: a custom challenge shows its trimmed
/// customTitle; everything else (and a blank custom title) falls back to the
/// kind's default title.
function challengeTitle(row: { kind: string; customTitle: string | null }): string {
  if (row.kind === 'custom' && row.customTitle?.trim()) return row.customTitle.trim()
  return defaultTitle(row.kind)
}

function serializeChallenge(
  row: {
    id: string
    creatorId: string
    kind: string
    customTitle: string | null
    visibility: string
    isOfficial?: boolean
    targetHint: string | null
    durationDays: number
    endsAt: Date
    createdAt: Date
    creator: {
      profile: { username: string | null; displayName: string | null } | null
    }
  },
  viewerId: string,
  extra?: { participantsCount?: number; joined?: boolean },
) {
  const title = challengeTitle(row)

  return {
    id: row.id,
    creatorId: row.creatorId,
    creatorDisplayName: profileLabel(row.creator.profile),
    isMine: row.creatorId === viewerId,
    isOfficial: row.isOfficial ?? false,
    kind: row.kind,
    customTitle: row.customTitle ?? '',
    title,
    visibility: row.visibility,
    targetHint: row.targetHint,
    durationDays: row.durationDays,
    createdAt: row.createdAt.toISOString(),
    endsAt: row.endsAt.toISOString(),
    ...(extra?.participantsCount !== undefined ? { participantsCount: extra.participantsCount } : {}),
    ...(extra?.joined !== undefined ? { joined: extra.joined } : {}),
  }
}

// custom + any unknown kind both fall through to 'Challenge'.
const TITLES: Record<string, string> = {
  pullUps: 'Pull-up challenge',
  deadlift: 'Deadlift challenge',
  squat: 'Squat challenge',
  benchPress: 'Bench press challenge',
}

function defaultTitle(kind: string): string {
  return TITLES[kind] ?? 'Challenge'
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

    const { kind, customTitle, visibility, targetHint, durationDays, scoringType, startsAt, rules, exerciseId, targetDays, inviteUserIds } = parsed.data

    // Cross-validate the scoring config.
    if (scoringType === 'pr_battle' && !exerciseId) {
      return reply.code(400).send({ error: 'EXERCISE_REQUIRED', message: 'PR Battle needs a target exercise.', requestId: request.id })
    }
    if (scoringType === 'consistency' && !targetDays) {
      return reply.code(400).send({ error: 'TARGET_REQUIRED', message: 'Consistency needs a target number of days.', requestId: request.id })
    }

    const customDb = kind === 'custom' ? customTitle!.trim() : customTitle?.trim() ? customTitle.trim() : null
    const hintDb = targetHint?.trim() ? targetHint.trim().slice(0, 120) : null

    const createdAt = new Date()
    const startDate = startsAt ? new Date(startsAt) : createdAt
    const endsAt = new Date(startDate.getTime() + durationDays * 86_400_000)

    const row = await prisma.challenge.create({
      data: {
        creatorId: userId,
        kind,
        customTitle: customDb,
        visibility,
        targetHint: hintDb,
        durationDays,
        endsAt,
        // Auto-scoring config (null when legacy/manual).
        scoringType: scoringType ?? null,
        startsAt: scoringType ? startDate : null,
        ruleMinDurationMin: rules?.minDurationMin ?? null,
        ruleMinSets: rules?.minSets ?? null,
        ruleMinExercises: rules?.minExercises ?? null,
        ruleMaxPerDay: rules?.maxPerDay ?? null,
        ruleExerciseId: exerciseId ?? null,
        ruleTargetDays: targetDays ?? null,
      },
      include: {
        creator: {
          select: {
            profile: { select: { username: true, displayName: true } },
          },
        },
      },
    })

    // Creator auto-joins as accepted; invited friends start as 'invited'.
    await prisma.challengeParticipant.create({
      data: { challengeId: row.id, userId, status: 'accepted', acceptedAt: createdAt },
    })
    if (inviteUserIds?.length) {
      // Only the creator's accepted friends can be invited. Arbitrary user IDs
      // would spam strangers and, for friends-visibility challenges, create
      // dead-end invites a non-friend could never accept.
      const friendSet = new Set(await acceptedFriendIds(userId))
      // De-dupe: a repeated ID must not send multiple invite notifications
      // (participant createMany is skipDuplicates-safe; the notify loop is not).
      const invitees = [...new Set(inviteUserIds.filter((uid) => uid !== userId && friendSet.has(uid)))]
      if (invitees.length) {
        await prisma.challengeParticipant.createMany({
          data: invitees.map((uid) => ({ challengeId: row.id, userId: uid, status: 'invited' })),
          skipDuplicates: true,
        })
        // Notify each invited friend (fire-and-forget; never blocks create).
        const inviteTitle = challengeTitle(row)
        for (const uid of invitees) {
          void createNotificationSafe({
            recipientId: uid,
            actorId: userId,
            type: NotificationType.CHALLENGE_INVITE,
            payload: {
              challengeId: row.id,
              title: inviteTitle,
              scoringType: scoringType ?? null,
              endsAt: row.endsAt.toISOString(),
            },
          })
        }
      }
    }

    // Seed the standings snapshot for auto-scored challenges.
    if (scoringType) {
      try {
        await recomputeChallenge(row.id)
      } catch (err) {
        request.log.warn({ err, challengeId: row.id }, 'Initial challenge recompute failed')
      }
    }

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
        // Official "rooms" are permanent and Discover-only — they'd clutter this
        // time-boxed feed with "9999 days left" entries, so exclude them here.
        OR: [
          { creatorId: me },
          { visibility: 'public', isOfficial: false },
          { visibility: 'friends', creatorId: { in: friendIds } },
        ],
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

    if (rows.length === 0) return reply.send({ data: [], requestId: request.id })

    // Hydrate joined-state + participant counts (same batch queries as /discover)
    // so the feed's Join/Leave button reflects reality — without this every row
    // reported joined=false, hiding the Leave action for joined users.
    const ids = rows.map((r) => r.id)
    const [counts, mine] = await Promise.all([
      prisma.challengeParticipant.groupBy({
        by: ['challengeId'],
        where: { challengeId: { in: ids } },
        _count: { challengeId: true },
      }),
      prisma.challengeParticipant.findMany({
        where: { challengeId: { in: ids }, userId: me },
        select: { challengeId: true },
      }),
    ])
    const countBy = new Map(counts.map((c) => [c.challengeId, c._count.challengeId]))
    const joined = new Set(mine.map((m) => m.challengeId))

    const data = rows.map((r) =>
      serializeChallenge(r, me, {
        participantsCount: countBy.get(r.id) ?? 0,
        joined: joined.has(r.id),
      }),
    )
    return reply.send({ data, requestId: request.id })
  })

  // GET /v1/challenges/invites — challenges you've been invited to but haven't
  // accepted/declined yet (participant status = 'invited'), still active. Powers
  // the pending-invites strip at the top of the Challenges sub-tab so a user can
  // accept/decline without opening each challenge.
  app.get('/invites', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const now = new Date()
    const rows = await prisma.challengeParticipant.findMany({
      where: {
        userId: me,
        status: 'invited',
        // Hide invites whose creator deleted/disabled their account (don't leak
        // their profile or surface a dead challenge).
        challenge: {
          endsAt: { gt: now },
          creator: { status: 'active', softDeletedAt: null },
        },
      },
      orderBy: { challenge: { createdAt: 'desc' } },
      take: 50,
      include: {
        challenge: {
          include: {
            creator: { select: { profile: { select: { username: true, displayName: true } } } },
          },
        },
      },
    })
    const data = rows.map((p) => {
      const c = p.challenge
      return {
        id: c.id,
        title: challengeTitle(c),
        scoringType: c.scoringType ?? null,
        endsAt: c.endsAt.toISOString(),
        creatorDisplayName: profileLabel(c.creator.profile),
      }
    })
    return reply.send({ data, requestId: request.id })
  })

  // GET /v1/challenges/discover — public rooms (Camere publice): every PUBLIC,
  // still-active challenge regardless of friendship, official rooms first, with
  // real participant counts + the viewer's joined flag so the browse UI can show
  // "1.2K in this room" + a Join/Open button. Page/limit paginated.
  app.get('/discover', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const q = request.query as { page?: string; limit?: string }
    const limit = Math.min(50, Math.max(1, parseInt(q.limit ?? '20', 10) || 20))
    const page = Math.max(1, parseInt(q.page ?? '1', 10) || 1)
    const now = new Date()

    const rows = await prisma.challenge.findMany({
      where: { visibility: 'public', endsAt: { gt: now } },
      // Official rooms first, then newest. (createdAt is the stable tiebreaker.)
      orderBy: [{ isOfficial: 'desc' }, { createdAt: 'desc' }],
      skip: (page - 1) * limit,
      take: limit,
      include: {
        creator: { select: { profile: { select: { username: true, displayName: true } } } },
      },
    })

    if (rows.length === 0) return reply.send({ data: [], meta: { page, limit }, requestId: request.id })

    const ids = rows.map((r) => r.id)
    const [counts, mine] = await Promise.all([
      prisma.challengeParticipant.groupBy({
        by: ['challengeId'],
        where: { challengeId: { in: ids } },
        _count: { challengeId: true },
      }),
      prisma.challengeParticipant.findMany({
        where: { challengeId: { in: ids }, userId: me },
        select: { challengeId: true },
      }),
    ])
    const countBy = new Map(counts.map((c) => [c.challengeId, c._count.challengeId]))
    const joined = new Set(mine.map((m) => m.challengeId))

    const data = rows.map((r) =>
      serializeChallenge(r, me, {
        participantsCount: countBy.get(r.id) ?? 0,
        joined: joined.has(r.id),
      }),
    )
    return reply.send({ data, meta: { page, limit }, requestId: request.id })
  })

  // POST /v1/challenges/:id/join
  app.post('/:id/join', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const challenge = await loadVisibleChallenge(request, reply)
    if (!challenge) return
    if (challenge.endsAt <= new Date()) {
      return reply.code(400).send({ error: 'CHALLENGE_EXPIRED', message: 'Provocarea a expirat', requestId: request.id })
    }
    // Join == accept (also accepts a pending invite). Idempotent.
    const now = new Date()
    const participant = await prisma.challengeParticipant.upsert({
      where: { challengeId_userId: { challengeId: challenge.id, userId: me } },
      create: { challengeId: challenge.id, userId: me, status: 'accepted', acceptedAt: now },
      update: { status: 'accepted', acceptedAt: now },
    })
    // Recompute standings so the new participant is scored/ranked immediately.
    // recomputeChallenge is a no-op for legacy/manual challenges, so it's safe
    // to call unconditionally.
    try {
      await recomputeChallenge(challenge.id)
    } catch (err) {
      request.log.warn({ err, challengeId: challenge.id }, 'Recompute on join failed')
    }

    // Tell the creator someone joined — exactly once per (joiner, challenge)
    // via the dedupe ledger, so a double-tap / leave-then-rejoin never
    // double-notifies (race-proof, unlike a read-then-write status check).
    // Skip self-joins and soft-deleted/disabled creators.
    if (me !== challenge.creatorId) {
      const claimed = await claimScheduledNotification(
        challenge.creatorId,
        NotificationType.CHALLENGE_JOINED,
        `${challenge.id}:${me}`,
      )
      if (claimed) {
        const creator = await prisma.user.findUnique({
          where: { id: challenge.creatorId },
          select: { status: true, softDeletedAt: true },
        })
        if (creator && creator.status === 'active' && creator.softDeletedAt == null) {
          const title = challengeTitle(challenge)
          void createNotificationSafe({
            recipientId: challenge.creatorId,
            actorId: me,
            type: NotificationType.CHALLENGE_JOINED,
            payload: {
              challengeId: challenge.id,
              title,
              scoringType: challenge.scoringType ?? null,
              endsAt: challenge.endsAt.toISOString(),
            },
          })
        }
      }
    }
    return reply.code(201).send({
      data: {
        challengeId: challenge.id,
        userId: me,
        status: 'accepted',
        joinedAt: participant.joinedAt.toISOString(),
      },
    })
  })

  // POST /v1/challenges/:id/decline — decline a pending invite.
  app.post('/:id/decline', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const id = requireUuidParam(request, reply)
    if (!id) return
    // Scope the flip to a still-pending invite: without the status filter,
    // declining would knock an already-ACCEPTED member back to 'declined'
    // (i.e. silently unjoin them). Only an 'invited' row is a valid decline.
    const res = await prisma.challengeParticipant.updateMany({
      where: { challengeId: id, userId: me, status: 'invited' },
      data: { status: 'declined' },
    })
    if (res.count === 0) {
      return reply.code(409).send({
        error: 'NOT_INVITED',
        message: 'No pending invite to decline',
        requestId: request.id,
      })
    }
    return reply.code(204).send()
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
      displayName: profileLabel(p.user.profile),
      username: p.user.profile?.username ?? null,
      joinedAt: p.joinedAt.toISOString(),
    }))
    return reply.send({ data, total: data.length, requestId: request.id })
  })

  /// Shared preamble for the access gates below: validate the :id UUID, load
  /// the challenge, and 404 if missing. Returns the row or replies + null.
  async function loadChallengeOr404(request: any, reply: any) {
    const id = requireUuidParam(request, reply)
    if (!id) return null
    const challenge = await prisma.challenge.findUnique({ where: { id } })
    if (!challenge) {
      reply.code(404).send({ error: 'NOT_FOUND', message: 'Provocarea nu există', requestId: request.id })
      return null
    }
    return challenge
  }

  /// Shared access gate for progress/standings/chat: challenge must exist
  /// and be visible to the viewer (public, mine, or friend's). Returns the
  /// challenge row or replies with the error and returns null.
  async function loadVisibleChallenge(request: any, reply: any): Promise<{ id: string; creatorId: string; visibility: string; endsAt: Date; kind: string; customTitle: string | null; scoringType: string | null } | null> {
    const { userId: me } = request.user
    const challenge = await loadChallengeOr404(request, reply)
    if (!challenge) return null
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
    const challenge = await loadChallengeOr404(request, reply)
    if (!challenge) return null
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
    const [challenge, participants] = await Promise.all([
      prisma.challenge.findUnique({ where: { id: challengeId }, select: { scoringType: true } }),
      prisma.challengeParticipant.findMany({
        where: { challengeId },
        include: {
          user: { select: { profile: { select: { username: true, displayName: true } } } },
        },
        orderBy: { joinedAt: 'asc' },
      }),
    ])

    // Auto-scored challenge → official score/rank from challenge-recalc.service.
    if (challenge?.scoringType) {
      const rows = participants
        .filter((p) => p.status === 'accepted')
        .map((p) => ({
          userId: p.userId,
          displayName: profileLabel(p.user.profile),
          username: p.user.profile?.username ?? null,
          total: p.score,
          lastLoggedAt: p.lastScoreUpdate?.toISOString() ?? null,
          joinedAt: p.joinedAt.toISOString(),
        }))
      rows.sort((a, b) => b.total - a.total)
      return rows
    }

    // Legacy/manual challenge → standings from manual progress logs.
    const sums = await prisma.challengeProgressLog.groupBy({
      by: ['userId'],
      where: { challengeId },
      _sum: { amount: true },
      _max: { createdAt: true },
    })
    const totals = new Map(sums.map((s) => [s.userId, { total: Number(s._sum.amount ?? 0), lastAt: s._max.createdAt }]))
    const rows = participants.map((p) => ({
      userId: p.userId,
      displayName: profileLabel(p.user.profile),
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
        displayName: profileLabel(m.user.profile),
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
        displayName: profileLabel(saved.user.profile),
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
