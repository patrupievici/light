import { FastifyInstance } from 'fastify'
import type { Post } from '@prisma/client'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { computeRanks } from '../services/ranking.service'
import { updateStreak } from '../services/streak.service'
import { createNotificationSafe, NotificationType } from '../services/notification.service'
import { decodePostPhotoBase64, savePostPhoto } from '../lib/post-photo'
import { areFriends, getFriendIdsAndHidden } from '../lib/friendships'
import { stripControlChars } from '../lib/sanitize'

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

async function canViewerSeePost(
  viewerId: string,
  post: { userId: string; visibility: string },
): Promise<boolean> {
  if (post.userId === viewerId) return true
  const sharing = await prisma.userProfile.findUnique({
    where: { userId: post.userId },
    select: { showActivityFeed: true },
  })
  if (sharing?.showActivityFeed === false) return false
  if (post.visibility === 'private') return false
  if (post.visibility === 'public') return true
  return areFriends(viewerId, post.userId)
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
        const rel = await savePostPhoto(post.id, photoBuf)
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

    return reply.send({ data: posts, meta: { page, limit } })
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

    return reply.send({ data: post })
  })

  // POST /v1/posts/:id/likes — toggle like
  app.post('/:id/likes', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id: postId } = request.params as { id: string }

    const existing = await prisma.postLike.findUnique({
      where: { postId_userId: { postId, userId } },
    })

    if (existing) {
      await prisma.postLike.delete({ where: { postId_userId: { postId, userId } } })
      return reply.send({ liked: false })
    } else {
      await prisma.postLike.create({ data: { postId, userId } })
      await prisma.analyticsEvent.create({
        data: { userId, eventName: 'post_liked' },
      })
      const owner = await prisma.post.findUnique({
        where: { id: postId },
        select: { userId: true },
      })
      if (owner && owner.userId !== userId) {
        await createNotificationSafe({
          recipientId: owner.userId,
          actorId: userId,
          type: NotificationType.POST_LIKE,
          payload: { postId },
        })
      }
      return reply.send({ liked: true })
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

    const owner = await prisma.post.findUnique({
      where: { id: postId },
      select: { userId: true },
    })
    if (owner && owner.userId !== userId) {
      await createNotificationSafe({
        recipientId: owner.userId,
        actorId: userId,
        type: NotificationType.POST_COMMENT,
        payload: { postId, bodyPreview: body.slice(0, 120) },
      })
    }

    return reply.code(201).send({ comment })
  })

  // GET /v1/posts/:id/comments
  app.get('/:id/comments', { preHandler: authenticate }, async (request, reply) => {
    const { id: postId } = request.params as { id: string }
    const query = request.query as { page?: string; limit?: string }

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

    return reply.send({ data: posts, meta: { page, limit } })
  })

  // PATCH /v1/posts/:id — edit caption/visibility (max 3 edits / 24h)
  app.patch('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: postId } = request.params as { id: string }

    const post = await prisma.post.findUnique({ where: { id: postId } })
    if (!post) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Post negăsit', requestId: request.id })
    if (post.userId !== me) return reply.code(403).send({ error: 'FORBIDDEN', message: 'Nu poți edita această postare', requestId: request.id })

    // Anti-cheat: max 3 edits per 24h
    const windowStart = new Date(Date.now() - 86_400_000)
    if (post.lastEditAt && post.lastEditAt > windowStart && post.editCount >= 3) {
      return reply.code(429).send({ error: 'EDIT_LIMIT', message: 'Maxim 3 editări per 24h', requestId: request.id })
    }

    const body = request.body as { caption?: string; visibility?: string }
    const updates: Record<string, unknown> = { editCount: post.editCount + 1, lastEditAt: new Date() }
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
    return reply.code(204).send()
  })

  // POST /v1/posts/:id/bookmark — toggle
  app.post('/:id/bookmark', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const { id: postId } = request.params as { id: string }

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
