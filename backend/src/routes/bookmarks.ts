import type { FastifyInstance } from 'fastify'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import {
  feedPostInclude,
  likedPostIdsFor,
  bookmarkedPostIdsFor,
  redactHiddenSets,
  canViewerSeePost,
} from './posts'

/**
 * Bookmarks list. Registered at prefix `/v1/me`, so this serves
 * `GET /v1/me/bookmarks`. Without it the client 404'd and showed a false
 * "No saved posts yet" empty state even after saving posts.
 */
export async function bookmarksRoutes(app: FastifyInstance) {
  app.get('/bookmarks', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { page?: string; limit?: string }
    const page = Math.max(1, parseInt(q.page ?? '1', 10) || 1)
    const limit = Math.min(30, Math.max(1, parseInt(q.limit ?? '20', 10) || 20))
    const skip = (page - 1) * limit

    const marks = await prisma.postBookmark.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
      include: {
        post: {
          include: {
            user: {
              select: {
                id: true,
                profile: { select: { displayName: true, username: true } },
              },
            },
            ...feedPostInclude,
          },
        },
      },
    })

    // Re-run the SAME read-time gate the feed / GET /posts/:id apply: drop any
    // bookmarked post the viewer can no longer see (turned private, unfriended,
    // blocked, or author hid their activity feed). Pagination stays as-is — a
    // filtered page may return fewer than `limit` items, same as the feed.
    const allPosts = marks.map((m) => m.post)
    const visible = await Promise.all(
      allPosts.map((p) =>
        canViewerSeePost(userId, { userId: p.userId, visibility: p.visibility }),
      ),
    )
    const posts = allPosts.filter((_, i) => visible[i])
    const ids = posts.map((p) => p.id)
    const liked = await likedPostIdsFor(userId, ids)
    // Everything here is bookmarked by definition.
    const marked = await bookmarkedPostIdsFor(userId, ids)
    const data = posts.map((p) =>
      redactHiddenSets(
        { ...p, likedByMe: liked.has(p.id), bookmarkedByMe: marked.has(p.id) },
        userId,
      ),
    )

    return reply.send({ data, meta: { page, limit } })
  })
}
