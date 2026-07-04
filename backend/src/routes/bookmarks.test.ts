import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Mock prisma so the REAL visibility gate (isBlockedEitherWay + areFriends +
// showActivityFeed + canViewerSeePostPure) runs end-to-end against fixture rows.
const bookmarkFindMany = vi.fn()
const profileFindUnique = vi.fn(async (..._a: unknown[]) => ({ showActivityFeed: true }))
const friendshipFindFirst = vi.fn(async (..._a: unknown[]) => null as unknown)
const blockFindFirst = vi.fn(async (..._a: unknown[]) => null as unknown)
const likeFindMany = vi.fn(async (..._a: unknown[]) => [] as unknown[])

vi.mock('../lib/prisma', () => ({
  prisma: {
    postBookmark: { findMany: (...a: unknown[]) => bookmarkFindMany(...a) },
    userProfile: { findUnique: (...a: unknown[]) => profileFindUnique(...a) },
    friendship: { findFirst: (...a: unknown[]) => friendshipFindFirst(...a) },
    userBlock: { findFirst: (...a: unknown[]) => blockFindFirst(...a) },
    postLike: { findMany: (...a: unknown[]) => likeFindMany(...a) },
  },
}))

// posts.ts (imported by bookmarks.ts) transitively pulls the notification
// service → fcm. Stub fcm so no firebase-admin is loaded in the test.
vi.mock('../services/fcm.service', () => ({
  sendPushForInAppNotification: vi.fn().mockResolvedValue(undefined),
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'me', email: 'me@t.dev' }
  },
}))

import { bookmarksRoutes } from './bookmarks'

async function buildApp() {
  const app = Fastify()
  await app.register(bookmarksRoutes, { prefix: '/v1/me' })
  await app.ready()
  return app
}

function post(id: string, userId: string, visibility: string) {
  return {
    id,
    userId,
    visibility,
    privacySettings: null,
    workout: null,
    _count: { likes: 0, comments: 0 },
    user: { id: userId, profile: { displayName: userId, username: userId } },
  }
}

beforeEach(() => {
  bookmarkFindMany.mockReset()
  profileFindUnique.mockReset()
  profileFindUnique.mockResolvedValue({ showActivityFeed: true })
  friendshipFindFirst.mockReset()
  friendshipFindFirst.mockResolvedValue(null)
  blockFindFirst.mockReset()
  blockFindFirst.mockResolvedValue(null)
  likeFindMany.mockReset()
  likeFindMany.mockResolvedValue([])
})

describe('GET /v1/me/bookmarks — re-applies the read-time visibility gate', () => {
  it('drops bookmarked posts the viewer can no longer see (private / non-friend)', async () => {
    bookmarkFindMany.mockImplementation((args: { include?: unknown }) => {
      // First call = list-with-include; second = bookmarkedPostIdsFor (select).
      if (args.include) {
        return Promise.resolve([
          { post: post('own', 'me', 'private') }, // owner → always visible
          { post: post('pub', 'friendX', 'public') }, // public + shares feed → visible
          { post: post('secret', 'strangerY', 'friends') }, // not friends → dropped
        ])
      }
      return Promise.resolve([{ postId: 'own' }, { postId: 'pub' }])
    })

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/bookmarks' })

    expect(res.statusCode).toBe(200)
    const ids = (res.json().data as Array<{ id: string }>).map((p) => p.id)
    expect(ids).toEqual(['own', 'pub'])
    expect(ids).not.toContain('secret')
    await app.close()
  })

  it('drops a bookmarked post whose author blocked the viewer', async () => {
    bookmarkFindMany.mockImplementation((args: { include?: unknown }) => {
      if (args.include) return Promise.resolve([{ post: post('pub', 'friendX', 'public') }])
      return Promise.resolve([])
    })
    blockFindFirst.mockResolvedValue({ id: 'b1' }) // a block exists either-way

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/bookmarks' })

    expect(res.statusCode).toBe(200)
    expect(res.json().data).toEqual([])
    await app.close()
  })
})
