import { FastifyInstance } from 'fastify'
import type { Post } from '@prisma/client'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { computeRanks } from '../services/ranking.service'
import { updateStreak } from '../services/streak.service'
import { createNotificationSafe, NotificationType } from '../services/notification.service'
import { decodePostPhotoBase64, deleteUploadByUrl, savePostPhoto } from '../lib/post-photo'
import { getFriendIdsAndHidden } from '../lib/friendships'
import { stripControlChars } from '../lib/sanitize'
import { evaluateEditLimit } from '../services/anti-cheat.service'
import { canViewerSeePost } from '../lib/post-visibility'

const CreatePostSchema = z
  .object({
    /** Dacă lipsește = postare doar social (caption și/sau poză). */
    workoutId: z.string().uuid().optional(),
    visibility: z.enum(['private', 'friends', 'public']).default('friends'),
    caption: z.string().max(500).optional(),
    /** Base64 sau data:image/jpeg;base64,... — decodare max ~1.8MB; string mai lung permis (overhead base64). */
    photoBase64: z.string().max(4_000_000).optional(),
    privacySettings: z
      .object({
        hideWeights: z.boolean().optional(),
        hideReps: z.boolean().optional(),
        hideBodyweight: z.boolean().optional(),
      })
      .optional(),
  })
  .superRefine((val, ctx) => {
    if (!val.workoutId) {
      const cap = val.caption?.trim()
      const ph = val.photoBase64?.trim()
      if (!cap && !ph) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'Adaugă un mesaj sau o poză pentru postarea în feed.',
          path: ['caption'],
        })
      }
    }
  })

const AddCommentSchema = z.object({
  body: z.string().min(1).max(500),
})

const feedPostInclude = {
  privacySettings: true,
  workout: {
    include: {
      exercises: {
        include: {
          exercise: true,
          sets: { orderBy: { setIndex: 'asc' as const } },
        },
        orderBy: { position: 'asc' as const },
      },
    },
  },
  _count: { select: { likes: true, comments: true } },
}

/**
 * IDs (din `postIds`) pe care viewerul le-a apreciat deja. Un singur findMany
 * per pagină (fără N+1) — același pattern ca stories.ts `likedByMe`.
 */
async function likedPostIdsFor(viewerId: string, postIds: string[]): Promise<Set<string>> {
  if (postIds.length === 0) return new Set()
  const likes = await prisma.postLike.findMany({
    where: { postId: { in: postIds }, userId: viewerId },
    select: { postId: true },
  })
  return new Set(likes.map((l) => l.postId))
}

export async function postRoutes(app: FastifyInstance) {
  // POST /v1/posts — posteaza workout + calculeaza ranguri
  app.post('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const parsed = CreatePostSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const { workoutId, visibility, caption, privacySettings, photoBase64 } = parsed.data

    let photoBuf: Buffer | null = null
    if (photoBase64) {
      try {
        photoBuf = decodePostPhotoBase64(photoBase64)
      } catch {
        return reply.code(400).send({
          error: 'PHOTO_INVALID',
          message: 'Poza este prea mare sau format invalid (JPEG, PNG, WebP).',
          requestId: request.id,
        })
      }
    }

    const profile = await prisma.userProfile.findUnique({ where: { userId } })

    /** Relații explicite — evită XOR Prisma (userId + workoutId: null) pe client vechi / ambiguu. */
    const captionDb = caption?.trim() ? caption.trim() : null

    let post: Post

    if (workoutId) {
      const workout = await prisma.workout.findFirst({ where: { id: workoutId, userId } })
      if (!workout) {
        return reply.code(404).send({
          error: 'NOT_FOUND',
          message: 'Workout negasit',
          requestId: request.id,
        })
      }

      if (workout.status === 'draft') {
        return reply.code(400).send({
          error: 'WORKOUT_NOT_COMPLETED',
          message: 'Completeaza workout-ul inainte de a posta',
          requestId: request.id,
        })
      }

      const existingPost = await prisma.post.findUnique({ where: { workoutId } })
      if (existingPost) {
        return reply.code(409).send({
          error: 'ALREADY_POSTED',
          message: 'Acest workout a fost deja postat',
          requestId: request.id,
        })
      }

      post = await prisma.$transaction(async (tx) => {
        const newPost = await tx.post.create({
          data: {
            user: { connect: { id: userId } },
            workout: { connect: { id: workoutId } },
            visibility,
            caption: captionDb,
          },
        })

        if (privacySettings) {
          await tx.postPrivacySetting.create({
            data: {
              postId: newPost.id,
              hideWeights: privacySettings.hideWeights ?? false,
              hideReps: privacySettings.hideReps ?? false,
              hideBodyweight: privacySettings.hideBodyweight ?? false,
            },
          })
        }

        await tx.workout.update({
          where: { id: workoutId },
          data: { status: 'posted' },
        })

        return newPost
      })
    } else {
      post = await prisma.$transaction(async (tx) => {
        const newPost = await tx.post.create({
          data: {
            user: { connect: { id: userId } },
            visibility,
            caption: captionDb,
          },
        })

        if (privacySettings) {
          await tx.postPrivacySetting.create({
            data: {
              postId: newPost.id,
              hideWeights: privacySettings.hideWeights ?? false,
              hideReps: privacySettings.hideReps ?? false,
              hideBodyweight: privacySettings.hideBodyweight ?? false,
            },
          })
        }

        return newPost
      })
    }

    let postOut: Post = post
    if (photoBuf) {
      try {
        const rel = await savePostPhoto(post.id, userId, photoBuf)
        postOut = await prisma.post.update({
          where: { id: post.id },
          data: { imageUrl: rel },
        })
      } catch (err) {
        app.log.error({ err }, 'Salvare poza post esuata')
      }
    }

    let rankSummary = null
    if (workoutId && profile?.bodyweightKg) {
      try {
        rankSummary = await computeRanks(userId, workoutId)
      } catch (err: any) {
        app.log.error({ err }, 'Eroare la calculul rangurilor')
      }
    } else if (workoutId && !profile?.bodyweightKg) {
      app.log.info({ userId, workoutId }, 'Ranking omis: lipseste greutatea corporala (postarea a fost creata)')
    }

    // PR detection: a positive LP delta on any lift = a new personal best → flag
    // the post so the Feed "PRs" filter (kind=pr) can surface it.
    if (rankSummary && rankSummary.results.some((r) => r.lpDelta > 0)) {
      try {
        postOut = await prisma.post.update({
          where: { id: post.id },
          data: { isPr: true },
        })
      } catch (err) {
        app.log.error({ err }, 'Eroare la marcarea PR pe postare')
      }
    }

    // Update streak
    const streak = await updateStreak(userId)

    // Analytics
    await prisma.analyticsEvent.create({
      data: { userId, eventName: 'post_created' },
    })
    if (rankSummary) {
      await prisma.analyticsEvent.create({
        data: { userId, eventName: 'rank_calculated' },
      })
    }

    return reply.code(201).send({ post: postOut, rankSummary, streak })
  })

  // GET /v1/posts/feed — feed prieteni
  app.get('/feed', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const query = request.query as { page?: string; limit?: string; kind?: string }

    const page = Math.max(1, parseInt(query.page ?? '1'))
    const limit = Math.min(30, parseInt(query.limit ?? '10'))
    const skip = (page - 1) * limit
    // Feed "PRs" filter (mockup 9): only posts whose workout set a personal record.
    const prOnly = query.kind === 'pr'

    // Gaseste prietenii acceptati + postarile ascunse
    const { friendIds, hiddenIds } = await getFriendIdsAndHidden(userId)
    const activityHidden = await prisma.userProfile.findMany({
      where: { userId: { in: friendIds }, showActivityFeed: false },
      select: { userId: true },
    })
    const activityHiddenIds = new Set(activityHidden.map((row) => row.userId))
    const visibleFriendIds = friendIds.filter((id) => !activityHiddenIds.has(id))

    // Feed = postari proprii + ale prietenilor (visibility != private), fara cele ascunse
    const posts = await prisma.post.findMany({
      where: {
        id: { notIn: hiddenIds },
        ...(prOnly ? { isPr: true } : {}),
        OR: [
          { userId }, // propriile postari
          {
            userId: { in: visibleFriendIds },
            visibility: { in: ['friends', 'public'] },
          },
        ],
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
      include: {
        user: {
          select: {
            id: true,
            profile: {
              select: {
                displayName: true,
                username: true,
              },
            },
          },
        },
        ...feedPostInclude,
      },
    })

    // Seed the client's heart state: one findMany for the whole page (no N+1).
    const liked = await likedPostIdsFor(userId, posts.map((p) => p.id))
    const data = posts.map((p) => ({ ...p, likedByMe: liked.has(p.id) }))

    return reply.send({ data, meta: { page, limit } })
  })

  // GET /v1/posts/:id — o postare (pentru deep link / notificări)
  app.get('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId: viewerId } = request.user
    const { id: postId } = request.params as { id: string }

    const post = await prisma.post.findUnique({
      where: { id: postId },
      include: feedPostInclude,
    })

    if (!post) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Post negasit',
        requestId: request.id,
      })
    }

    const ok = await canViewerSeePost(viewerId, { userId: post.userId, visibility: post.visibility })
    if (!ok) {
      // Privacy: do NOT leak the post's existence to a viewer who can't see it.
      // Return the SAME 404 body as a truly-missing post so a private/non-friend
      // post is indistinguishable from one that doesn't exist (no enumeration).
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Post negasit',
        requestId: request.id,
      })
    }

    const liked = await likedPostIdsFor(viewerId, [post.id])
    return reply.send({ data: { ...post, likedByMe: liked.has(post.id) } })
  })

  // POST /v1/posts/:id/likes — toggle like
  app.post('/:id/likes', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: postId } = request.params as { id: string }

    // Privacy gate: you can only like a post you're allowed to see. 404 (not 403)
    // so a private/non-friend post stays indistinguishable from a missing one.
    const post = await prisma.post.findUnique({
      where: { id: postId },
      select: { userId: true, visibility: true },
    })
    if (!post || !(await canViewerSeePost(userId, post))) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negasit', requestId: request.id })
    }

    const existing = await prisma.postLike.findUnique({
      where: { postId_userId: { postId, userId } },
    })

    if (existing) {
      await prisma.postLike.delete({ where: { postId_userId: { postId, userId } } })
      const likeCount = await prisma.postLike.count({ where: { postId } })
      return reply.send({ liked: false, likeCount })
    } else {
      await prisma.postLike.create({ data: { postId, userId } })
      await prisma.analyticsEvent.create({
        data: { userId, eventName: 'post_liked' },
      })
      if (post.userId !== userId) {
        await createNotificationSafe({
          recipientId: post.userId,
          actorId: userId,
          type: NotificationType.POST_LIKE,
          payload: { postId },
        })
      }
      const likeCount = await prisma.postLike.count({ where: { postId } })
      return reply.send({ liked: true, likeCount })
    }
  })

  // POST /v1/posts/:id/comments
  app.post('/:id/comments', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: postId } = request.params as { id: string }

    const parsed = AddCommentSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Comment invalid',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    // Privacy gate: only comment on a post you can see (404 = no enumeration).
    const post = await prisma.post.findUnique({
      where: { id: postId },
      select: { userId: true, visibility: true },
    })
    if (!post || !(await canViewerSeePost(userId, post))) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negasit', requestId: request.id })
    }

    // Strip control chars + trim, but keep the text RAW (no HTML-entity
    // encoding): the Flutter `Text` client renders plain text, so encoding here
    // would corrupt display (`a < b` -> `a &lt; b`). The naive `<[^>]*>` strip
    // was misleading — it gives no real XSS protection (the client never uses
    // innerHTML) yet silently eats legitimate `<` / `>` chars. Length is already
    // capped by the Zod schema (`.max(500)`).
    const body = stripControlChars(parsed.data.body)

    const comment = await prisma.postComment.create({
      data: { postId, userId, body },
    })

    await prisma.analyticsEvent.create({
      data: { userId, eventName: 'post_commented' },
    })

    if (post.userId !== userId) {
      await createNotificationSafe({
        recipientId: post.userId,
        actorId: userId,
        type: NotificationType.POST_COMMENT,
        payload: { postId, bodyPreview: body.slice(0, 120) },
      })
    }

    return reply.code(201).send({ comment })
  })

  // GET /v1/posts/:id/comments
  app.get('/:id/comments', { preHandler: authenticate }, async (request, reply) => {
    const { userId: viewerId } = request.user
    const { id: postId } = request.params as { id: string }
    const query = request.query as { page?: string; limit?: string }

    // Privacy gate: don't expose a post's comments to someone who can't see the
    // post itself. 404 mirrors the post-not-found body (no enumeration).
    const post = await prisma.post.findUnique({
      where: { id: postId },
      select: { userId: true, visibility: true },
    })
    if (!post || !(await canViewerSeePost(viewerId, post))) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negasit', requestId: request.id })
    }

    const page = Math.max(1, parseInt(query.page ?? '1'))
    const limit = Math.min(50, parseInt(query.limit ?? '20'))
    const skip = (page - 1) * limit

    const [comments, total] = await Promise.all([
      prisma.postComment.findMany({
        where: { postId },
        orderBy: { createdAt: 'asc' },
        skip,
        take: limit,
        include: {
          user: { include: { profile: true } },
        },
      }),
      prisma.postComment.count({ where: { postId } }),
    ])

    return reply.send({
      data: comments,
      meta: { page, limit, total },
    })
  })

  // GET /v1/posts — gallery/explore
  app.get('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const q = request.query as { sort?: string; mine?: string; page?: string; limit?: string }
    const sort = q.sort === 'popular' ? 'popular' : 'recent'
    const mine = q.mine === 'true'
    const page = Math.max(1, parseInt(q.page ?? '1'))
    const limit = Math.min(30, parseInt(q.limit ?? '20'))
    const skip = (page - 1) * limit

    const { friendIds, hiddenIds: hiddenPostIds } = await getFriendIdsAndHidden(me)

    const where = mine
      ? { userId: me, id: { notIn: hiddenPostIds } }
      : {
          id: { notIn: hiddenPostIds },
          OR: [
            { userId: me },
            { userId: { in: friendIds }, visibility: { in: ['friends', 'public'] } },
            { visibility: 'public' },
          ],
        }

    const posts = await prisma.post.findMany({
      where,
      orderBy: sort === 'popular' ? { likes: { _count: 'desc' } } : { createdAt: 'desc' },
      skip,
      take: limit,
      include: {
        user: { select: { id: true, profile: { select: { displayName: true, username: true } } } },
        privacySettings: true,
        _count: { select: { likes: true, comments: true } },
      },
    })

    // Same single-query likedByMe seeding as /feed (no N+1).
    const liked = await likedPostIdsFor(me, posts.map((p) => p.id))
    const data = posts.map((p) => ({ ...p, likedByMe: liked.has(p.id) }))

    return reply.send({ data, meta: { page, limit } })
  })

  // PATCH /v1/posts/:id — edit caption/visibility (max 3 edits / 24h)
  app.patch('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: postId } = request.params as { id: string }

    const post = await prisma.post.findUnique({ where: { id: postId } })
    if (!post) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negăsit', requestId: request.id })
    if (post.userId !== me) return reply.code(403).send({ error: 'FORBIDDEN', message: 'Nu poți edita această postare', requestId: request.id })

    // Anti-cheat: max 3 edits / 24h. The pure validator (anti-cheat.service) is
    // the single source of truth — crucially it RESETS the counter once the 24h
    // window has rolled over. The old inline check never reset, so editCount grew
    // unbounded and eventually locked a post out forever.
    const editVerdict = evaluateEditLimit(
      { editCount: post.editCount, lastEditAt: post.lastEditAt },
      new Date(),
    )
    if (!editVerdict.allowed) {
      return reply.code(429).send({ error: 'EDIT_LIMIT', message: 'Maxim 3 editări per 24h', requestId: request.id })
    }

    const body = request.body as { caption?: string; visibility?: string }
    const updates: Record<string, unknown> = { editCount: editVerdict.nextEditCount, lastEditAt: new Date() }
    if (body.caption !== undefined) updates.caption = body.caption?.trim() || null
    if (body.visibility && ['private', 'friends', 'public'].includes(body.visibility)) {
      updates.visibility = body.visibility
    }

    const updated = await prisma.post.update({ where: { id: postId }, data: updates })
    return reply.send({ data: updated })
  })

  // DELETE /v1/posts/:id
  app.delete('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: postId } = request.params as { id: string }

    const post = await prisma.post.findUnique({ where: { id: postId } })
    if (!post) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negăsit', requestId: request.id })
    if (post.userId !== me) return reply.code(403).send({ error: 'FORBIDDEN', message: 'Nu poți șterge această postare', requestId: request.id })

    await prisma.post.delete({ where: { id: postId } })
    // The media route independently rejects a missing post, but remove the
    // bytes as well so deletion does not leave private material on disk.
    await deleteUploadByUrl(post.imageUrl)
    return reply.code(204).send()
  })

  // POST /v1/posts/:id/bookmark — toggle
  app.post('/:id/bookmark', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: postId } = request.params as { id: string }

    // Privacy gate: don't let a viewer bookmark (and thus track / leak the
    // existence of) a post they aren't allowed to see.
    const post = await prisma.post.findUnique({
      where: { id: postId },
      select: { userId: true, visibility: true },
    })
    if (!post || !(await canViewerSeePost(me, post))) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negăsit', requestId: request.id })
    }

    const existing = await prisma.postBookmark.findUnique({
      where: { postId_userId: { postId, userId: me } },
    })
    if (existing) {
      await prisma.postBookmark.delete({ where: { postId_userId: { postId, userId: me } } })
      return reply.send({ bookmarked: false })
    }
    await prisma.postBookmark.create({ data: { postId, userId: me } })
    return reply.send({ bookmarked: true })
  })

  // POST /v1/posts/:id/hide
  app.post('/:id/hide', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: postId } = request.params as { id: string }

    // Privacy gate: a post you can't see isn't in your feed, so there's nothing
    // legitimate to hide — and a 201 here would leak its existence.
    const post = await prisma.post.findUnique({
      where: { id: postId },
      select: { userId: true, visibility: true },
    })
    if (!post || !(await canViewerSeePost(me, post))) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negăsit', requestId: request.id })
    }

    await prisma.postHide.upsert({
      where: { postId_userId: { postId, userId: me } },
      update: {},
      create: { postId, userId: me },
    })
    return reply.send({ ok: true })
  })

  // POST /v1/posts/:id/report
  app.post('/:id/report', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: postId } = request.params as { id: string }
    const body = request.body as { reason?: string }
    const reason = body?.reason?.trim().slice(0, 200) || null

    // Privacy gate: you can only report a post you can actually see — otherwise a
    // 201 leaks existence and lets someone spuriously report invisible posts.
    const post = await prisma.post.findUnique({
      where: { id: postId },
      select: { userId: true, visibility: true },
    })
    if (!post || !(await canViewerSeePost(me, post))) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negăsit', requestId: request.id })
    }

    const report = await prisma.postReport.upsert({
      where: { postId_userId: { postId, userId: me } },
      update: { reason },
      create: { postId, userId: me, reason },
    })

    await prisma.analyticsEvent.create({
      data: { userId: me, eventName: 'post_reported', props: { postId } },
    })

    return reply.code(201).send({ ok: true, reportId: report.id })
  })
}
