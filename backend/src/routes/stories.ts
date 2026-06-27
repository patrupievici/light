import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { getUserDisplayHints } from '../lib/user-display'
import { decodePostPhotoBase64, saveStoryPhoto, deleteStoryPhoto } from '../lib/post-photo'
import { acceptedFriendIds } from '../lib/friendships'

const CreateStorySchema = z.object({
  caption: z.string().max(500).optional(),
  imageBase64: z.string().max(4_000_000).optional(),
  location: z.string().max(200).optional(),
})

export async function storyRoutes(app: FastifyInstance) {
  // POST /v1/stories — creeaza story cu durată 24h
  app.post('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = CreateStorySchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const { caption, imageBase64, location } = parsed.data
    const captionDb = caption?.trim() || null
    const locationDb = location?.trim() || null

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000)

    const story = await prisma.story.create({
      data: { userId, caption: captionDb, location: locationDb, expiresAt },
    })

    if (imageBase64) {
      try {
        const buf = decodePostPhotoBase64(imageBase64)
        const rel = await saveStoryPhoto(story.id, buf)
        await prisma.story.update({ where: { id: story.id }, data: { imageUrl: rel } })
        return reply.code(201).send({ data: { ...story, imageUrl: rel } })
      } catch (err) {
        app.log.error({ err }, 'Story image save failed')
      }
    }

    return reply.code(201).send({ data: story })
  })

  // GET /v1/stories/feed — stories active ale prietenilor + ale mele
  app.get('/feed', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const now = new Date()

    const friendIds = await acceptedFriendIds(me)

    const stories = await prisma.story.findMany({
      where: {
        expiresAt: { gt: now },
        userId: { in: [me, ...friendIds] },
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    })

    if (stories.length === 0) return reply.send({ data: [] })

    const userIds = Array.from(new Set(stories.map((s) => s.userId)))
    const storyIds = stories.map((s) => s.id)
    const [hints, likeCounts, myLikes] = await Promise.all([
      getUserDisplayHints(userIds),
      prisma.storyLike.groupBy({
        by: ['storyId'],
        where: { storyId: { in: storyIds } },
        _count: { storyId: true },
      }),
      prisma.storyLike.findMany({
        where: { storyId: { in: storyIds }, userId: me },
        select: { storyId: true },
      }),
    ])
    const countByStory = new Map(likeCounts.map((c) => [c.storyId, c._count.storyId]))
    const likedByMe = new Set(myLikes.map((l) => l.storyId))

    const data = stories.map((s) => ({
      id: s.id,
      userId: s.userId,
      authorName: hints.get(s.userId)?.displayName ?? hints.get(s.userId)?.username ?? 'Athlete',
      caption: s.caption,
      imageUrl: s.imageUrl,
      location: s.location,
      expiresAt: s.expiresAt.toISOString(),
      createdAt: s.createdAt.toISOString(),
      likeCount: countByStory.get(s.id) ?? 0,
      likedByMe: likedByMe.has(s.id),
    }))

    return reply.send({ data })
  })

  // POST /v1/stories/:id/like — toggle heart. Returns the new state.
  app.post('/:id/like', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const id = (request.params as { id?: string }).id
    if (!id || !z.string().uuid().safeParse(id).success) {
      return reply.code(400).send({ error: 'VALIDATION_ERROR', message: 'ID invalid', requestId: request.id })
    }
    const story = await prisma.story.findUnique({ where: { id } })
    if (!story || story.expiresAt <= new Date()) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Story negăsit sau expirat', requestId: request.id })
    }
    const existing = await prisma.storyLike.findUnique({
      where: { storyId_userId: { storyId: id, userId: me } },
    })
    if (existing) {
      await prisma.storyLike.delete({
        where: { storyId_userId: { storyId: id, userId: me } },
      })
    } else {
      await prisma.storyLike.create({ data: { storyId: id, userId: me } })
    }
    const likeCount = await prisma.storyLike.count({ where: { storyId: id } })
    return reply.send({
      data: { liked: !existing, likeCount },
      requestId: request.id,
    })
  })

  // DELETE /v1/stories/:id — doar owner-ul
  app.delete('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId: me } = request.user
    const id = (request.params as { id?: string }).id
    if (!id || !z.string().uuid().safeParse(id).success) {
      return reply.code(400).send({ error: 'VALIDATION_ERROR', message: 'ID invalid', requestId: request.id })
    }

    const story = await prisma.story.findUnique({ where: { id } })
    if (!story) return reply.code(404).send({ error: 'NOT_FOUND', message: 'Story negăsit', requestId: request.id })
    if (story.userId !== me) return reply.code(403).send({ error: 'FORBIDDEN', message: 'Nu poți șterge story-ul altcuiva', requestId: request.id })

    await prisma.story.delete({ where: { id } })
    // Best-effort: remove the on-disk photo too so a manual delete doesn't leave
    // an orphaned file for the TTL cron to never reach (the row is already gone).
    if (story.imageUrl) await deleteStoryPhoto(story.imageUrl)
    return reply.code(204).send()
  })
}
