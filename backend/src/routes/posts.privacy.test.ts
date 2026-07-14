import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Mock the prisma client. The route's privacy gate (`canViewerSeePost`) and the
// friendship lib both read through this, so mocking prisma alone exercises the
// REAL gate logic end-to-end (no friendship-lib stub needed).
const postFindUnique = vi.fn()
const postFindMany = vi.fn()
const userProfileFindUnique = vi.fn()
const userProfileFindMany = vi.fn()
const friendshipFindFirst = vi.fn()
const friendshipFindMany = vi.fn()
const postHideFindMany = vi.fn()
const postLikeFindUnique = vi.fn()
const postLikeFindMany = vi.fn()
const postLikeCount = vi.fn()
const postLikeCreate = vi.fn()
const postLikeDelete = vi.fn()
const postCommentCreate = vi.fn()
const postCommentFindMany = vi.fn()
const postCommentCount = vi.fn()
const analyticsEventCreate = vi.fn()
const postBookmarkFindUnique = vi.fn()
const postBookmarkCreate = vi.fn()
const postBookmarkDelete = vi.fn()
const postHideUpsert = vi.fn()
const postReportUpsert = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    post: {
      findUnique: (...a: unknown[]) => postFindUnique(...a),
      findMany: (...a: unknown[]) => postFindMany(...a),
    },
    userProfile: {
      findUnique: (...a: unknown[]) => userProfileFindUnique(...a),
      findMany: (...a: unknown[]) => userProfileFindMany(...a),
    },
    friendship: {
      findFirst: (...a: unknown[]) => friendshipFindFirst(...a),
      findMany: (...a: unknown[]) => friendshipFindMany(...a),
    },
    postHide: {
      findMany: (...a: unknown[]) => postHideFindMany(...a),
      upsert: (...a: unknown[]) => postHideUpsert(...a),
    },
    postLike: {
      findUnique: (...a: unknown[]) => postLikeFindUnique(...a),
      findMany: (...a: unknown[]) => postLikeFindMany(...a),
      count: (...a: unknown[]) => postLikeCount(...a),
      create: (...a: unknown[]) => postLikeCreate(...a),
      delete: (...a: unknown[]) => postLikeDelete(...a),
    },
    postComment: {
      create: (...a: unknown[]) => postCommentCreate(...a),
      findMany: (...a: unknown[]) => postCommentFindMany(...a),
      count: (...a: unknown[]) => postCommentCount(...a),
    },
    postBookmark: {
      findUnique: (...a: unknown[]) => postBookmarkFindUnique(...a),
      create: (...a: unknown[]) => postBookmarkCreate(...a),
      delete: (...a: unknown[]) => postBookmarkDelete(...a),
    },
    postReport: { upsert: (...a: unknown[]) => postReportUpsert(...a) },
    analyticsEvent: { create: (...a: unknown[]) => analyticsEventCreate(...a) },
  },
}))

// authenticate is replaced per-test via a module-level holder so we can flip
// between "authed as viewer" and "unauthenticated → 401". MUST be async — a
// Fastify preHandler that is neither async nor calls `done` hangs the request.
let authImpl: (req: { user?: { userId: string; email: string } }, reply: {
  code: (c: number) => { send: (b: unknown) => unknown }
}) => Promise<unknown>
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: never, reply: never) => authImpl(req, reply),
}))

import { postRoutes } from './posts'

const FRIENDS_ONLY_POST = {
  id: 'p1',
  userId: 'owner',
  visibility: 'friends',
  caption: 'private gainz',
  privacySettings: null,
  workout: null,
  _count: { likes: 0, comments: 0 },
}

function authedAs(userId: string) {
  authImpl = async (req) => {
    req.user = { userId, email: `${userId}@t.dev` }
  }
}
function unauthenticated() {
  authImpl = async (_req, reply) => reply.code(401).send({ error: 'UNAUTHORIZED', message: 'no token' })
}

async function buildApp() {
  const app = Fastify()
  await app.register(postRoutes, { prefix: '/v1/posts' })
  await app.ready()
  return app
}

beforeEach(() => {
  postFindUnique.mockReset()
  postFindMany.mockReset()
  userProfileFindUnique.mockReset()
  userProfileFindMany.mockReset()
  friendshipFindFirst.mockReset()
  friendshipFindMany.mockReset()
  postHideFindMany.mockReset()
  postLikeFindUnique.mockReset()
  postLikeFindMany.mockReset().mockResolvedValue([]) // default: viewer liked nothing
  postLikeCount.mockReset().mockResolvedValue(0)
  postLikeCreate.mockReset()
  postLikeDelete.mockReset()
  postCommentCreate.mockReset()
  postCommentFindMany.mockReset()
  postCommentCount.mockReset()
  analyticsEventCreate.mockReset()
  postBookmarkFindUnique.mockReset()
  postBookmarkCreate.mockReset()
  postBookmarkDelete.mockReset()
  postHideUpsert.mockReset()
  postReportUpsert.mockReset()
  // Owner has activity feed shared (the gate's first lookup).
  userProfileFindUnique.mockResolvedValue({ showActivityFeed: true })
})

describe('GET /v1/posts/:id — privacy gate on a FRIENDS-ONLY post', () => {
  it('a NON-friend viewer gets 404 (existence not leaked), not shown the post', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null) // not friends
    authedAs('stranger')

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1' })

    // 404 (not 403): a forbidden post must be indistinguishable from a missing
    // one so a stranger can't infer the post exists by probing IDs.
    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    // The post body must NOT leak through the gate.
    expect(res.payload).not.toContain('private gainz')
    // The gate checks a bilateral block first, then accepted friendship. This
    // prevents a stale accepted row from bypassing a newer block.
    expect(friendshipFindFirst).toHaveBeenCalledTimes(2)
    await app.close()
  })

  it('the 404 body for a forbidden post is byte-identical to a truly-missing post (no enumeration)', async () => {
    // Forbidden case: post exists but the stranger can't see it.
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null)
    authedAs('stranger')
    const app1 = await buildApp()
    const forbidden = await app1.inject({ method: 'GET', url: '/v1/posts/p1' })
    await app1.close()

    // Missing case: post does not exist at all.
    postFindUnique.mockResolvedValue(null)
    authedAs('stranger')
    const app2 = await buildApp()
    const missing = await app2.inject({ method: 'GET', url: '/v1/posts/p1' })
    await app2.close()

    expect(forbidden.statusCode).toBe(missing.statusCode)
    // Same error code + message → the two cases are indistinguishable to a probe.
    expect(forbidden.json().error).toBe(missing.json().error)
    expect(forbidden.json().message).toBe(missing.json().message)
  })

  it('an accepted FRIEND can see the FRIENDS-ONLY post (200 + body)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue({ id: 'f1', status: 'accepted' }) // friends
    authedAs('buddy')

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1' })

    expect(res.statusCode).toBe(200)
    expect(res.json().data).toMatchObject({ id: 'p1', caption: 'private gainz' })
    await app.close()
  })

  it('the OWNER always sees their own post without a friendship check', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    authedAs('owner')

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1' })

    expect(res.statusCode).toBe(200)
    // Self-view short-circuits before any friendship/profile lookup.
    expect(friendshipFindFirst).not.toHaveBeenCalled()
    await app.close()
  })

  it('a post from an owner who DISABLED activity-feed sharing is hidden even from friends', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    userProfileFindUnique.mockResolvedValue({ showActivityFeed: false })
    friendshipFindFirst.mockResolvedValue({ id: 'f1', status: 'accepted' })
    authedAs('buddy')

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1' })

    expect(res.statusCode).toBe(404)
    // showActivityFeed=false short-circuits before the friendship check.
    expect(friendshipFindFirst).not.toHaveBeenCalled()
    await app.close()
  })

  it('an unauthenticated request is rejected with 401 before any DB read', async () => {
    unauthenticated()

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1' })

    expect(res.statusCode).toBe(401)
    expect(postFindUnique).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('interaction routes are gated by the same visibility rule', () => {
  it('POST /:id/likes — a non-friend cannot like a friends-only post (404, no like written)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null) // not friends
    authedAs('stranger')

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/posts/p1/likes' })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    expect(postLikeCreate).not.toHaveBeenCalled()
    expect(postLikeFindUnique).not.toHaveBeenCalled()
    await app.close()
  })

  it('POST /:id/comments — a non-friend cannot comment on a friends-only post (404, no comment written)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null)
    authedAs('stranger')

    const app = await buildApp()
    const res = await app.inject({
      method: 'POST', url: '/v1/posts/p1/comments', payload: { body: 'sneaky' },
    })

    expect(res.statusCode).toBe(404)
    expect(postCommentCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('GET /:id/comments — a non-friend cannot read a friends-only post\'s comments (404, none read)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null)
    authedAs('stranger')

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1/comments' })

    expect(res.statusCode).toBe(404)
    expect(postCommentFindMany).not.toHaveBeenCalled()
    await app.close()
  })

  it('GET /:id/comments — an accepted friend CAN read the comments (200, not over-blocked)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue({ id: 'f1', status: 'accepted' })
    postCommentFindMany.mockResolvedValue([])
    postCommentCount.mockResolvedValue(0)
    authedAs('buddy')

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1/comments' })

    expect(res.statusCode).toBe(200)
    expect(postCommentFindMany).toHaveBeenCalledOnce()
    await app.close()
  })

  it('POST /:id/bookmark — a non-friend cannot bookmark a friends-only post (404, no write)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null)
    authedAs('stranger')

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/posts/p1/bookmark' })

    expect(res.statusCode).toBe(404)
    expect(postBookmarkCreate).not.toHaveBeenCalled()
    expect(postBookmarkFindUnique).not.toHaveBeenCalled()
    await app.close()
  })

  it('POST /:id/hide — a non-friend cannot hide a friends-only post (404, no write)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null)
    authedAs('stranger')

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/posts/p1/hide' })

    expect(res.statusCode).toBe(404)
    expect(postHideUpsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('POST /:id/report — a non-friend cannot report a friends-only post (404, no write)', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    friendshipFindFirst.mockResolvedValue(null)
    authedAs('stranger')

    const app = await buildApp()
    const res = await app.inject({
      method: 'POST', url: '/v1/posts/p1/report', payload: { reason: 'spam' },
    })

    expect(res.statusCode).toBe(404)
    expect(postReportUpsert).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('GET /v1/posts/feed — friend-scoped, no private/stranger leakage', () => {
  it('scopes the feed query to the viewer + accepted-friend IDs and excludes private posts', async () => {
    // Viewer `me` is friends with `friendA` only; `stranger` is NOT a friend.
    friendshipFindMany.mockResolvedValue([
      { userId: 'me', friendUserId: 'friendA', status: 'accepted' },
    ])
    postHideFindMany.mockResolvedValue([]) // nothing hidden
    userProfileFindMany.mockResolvedValue([]) // no friend has activity-feed disabled
    postFindMany.mockResolvedValue([])

    authedAs('me')
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/feed' })

    expect(res.statusCode).toBe(200)
    expect(postFindMany).toHaveBeenCalledOnce()
    const where = (postFindMany.mock.calls[0][0] as {
      where: { OR: Array<{ userId?: unknown; visibility?: { in: string[] } }> }
    }).where

    // The friend-scoped branch only admits accepted friends...
    const friendBranch = where.OR.find((c) => c.visibility !== undefined)!
    expect(friendBranch.userId).toEqual({ in: ['friendA'] })
    // ...and a stranger never appears in the allowed id set.
    expect(JSON.stringify(friendBranch.userId)).not.toContain('stranger')
    // ...and only non-private visibilities are surfaced.
    expect(friendBranch.visibility).toEqual({ in: ['friends', 'public'] })
    expect(friendBranch.visibility!.in).not.toContain('private')

    // The viewer's own posts are always included (separate OR branch).
    expect(where.OR.some((c) => c.userId === 'me')).toBe(true)
    await app.close()
  })

  it('drops a friend who disabled activity-feed sharing from the feed scope', async () => {
    friendshipFindMany.mockResolvedValue([
      { userId: 'me', friendUserId: 'friendA', status: 'accepted' },
      { userId: 'me', friendUserId: 'friendB', status: 'accepted' },
    ])
    postHideFindMany.mockResolvedValue([])
    // friendB hid their activity feed → must be removed from the visible set.
    userProfileFindMany.mockResolvedValue([{ userId: 'friendB' }])
    postFindMany.mockResolvedValue([])

    authedAs('me')
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/feed' })

    expect(res.statusCode).toBe(200)
    const where = (postFindMany.mock.calls[0][0] as {
      where: { OR: Array<{ userId?: { in: string[] }; visibility?: unknown }> }
    }).where
    const friendBranch = where.OR.find((c) => c.visibility !== undefined)!
    expect(friendBranch.userId).toEqual({ in: ['friendA'] })
    expect(friendBranch.userId!.in).not.toContain('friendB')
    await app.close()
  })
})

describe('likedByMe — every post response reports whether the VIEWER liked it', () => {
  it('GET /:id — likedByMe=true when the viewer has liked the post', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    authedAs('owner') // owner short-circuits the privacy gate
    postLikeFindMany.mockResolvedValue([{ postId: 'p1' }])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1' })

    expect(res.statusCode).toBe(200)
    expect(res.json().data.likedByMe).toBe(true)
    // The like lookup MUST be scoped to the viewer — that's what stops other
    // users' likes from leaking into likedByMe.
    const where = (postLikeFindMany.mock.calls[0][0] as { where: { userId: string } }).where
    expect(where.userId).toBe('owner')
    await app.close()
  })

  it('GET /:id — likedByMe=false when only OTHER users liked it (no leak)', async () => {
    // 3 likes from other people (_count.likes=3), none from the viewer.
    postFindUnique.mockResolvedValue({ ...FRIENDS_ONLY_POST, _count: { likes: 3, comments: 0 } })
    authedAs('owner')
    postLikeFindMany.mockResolvedValue([]) // viewer-scoped query finds nothing

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/p1' })

    expect(res.statusCode).toBe(200)
    expect(res.json().data.likedByMe).toBe(false)
    expect(res.json().data._count.likes).toBe(3) // count untouched
    await app.close()
  })

  it('GET /feed — seeds likedByMe per post from ONE viewer-scoped query (no N+1)', async () => {
    friendshipFindMany.mockResolvedValue([])
    postHideFindMany.mockResolvedValue([])
    userProfileFindMany.mockResolvedValue([])
    postFindMany.mockResolvedValue([
      { ...FRIENDS_ONLY_POST, id: 'p1', userId: 'me' },
      { ...FRIENDS_ONLY_POST, id: 'p2', userId: 'me' },
    ])
    postLikeFindMany.mockResolvedValue([{ postId: 'p2' }]) // viewer liked only p2

    authedAs('me')
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/feed' })

    expect(res.statusCode).toBe(200)
    const data = res.json().data as Array<{ id: string; likedByMe: boolean }>
    expect(data.find((p) => p.id === 'p1')!.likedByMe).toBe(false)
    expect(data.find((p) => p.id === 'p2')!.likedByMe).toBe(true)
    // Exactly ONE like query for the whole page, scoped to the viewer.
    expect(postLikeFindMany).toHaveBeenCalledOnce()
    const where = (postLikeFindMany.mock.calls[0][0] as {
      where: { userId: string; postId: { in: string[] } }
    }).where
    expect(where.userId).toBe('me')
    expect(where.postId.in).toEqual(['p1', 'p2'])
    await app.close()
  })

  it('GET / (gallery) — seeds likedByMe the same way', async () => {
    friendshipFindMany.mockResolvedValue([])
    postHideFindMany.mockResolvedValue([])
    postFindMany.mockResolvedValue([
      { ...FRIENDS_ONLY_POST, id: 'p1', userId: 'me', visibility: 'public' },
    ])
    postLikeFindMany.mockResolvedValue([{ postId: 'p1' }])

    authedAs('me')
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts' })

    expect(res.statusCode).toBe(200)
    expect(res.json().data[0].likedByMe).toBe(true)
    await app.close()
  })

  it('POST /:id/likes — returns the new liked state AND the fresh likeCount', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    authedAs('owner') // liking own post → no notification path
    postLikeFindUnique.mockResolvedValue(null) // not yet liked → toggle ON
    postLikeCreate.mockResolvedValue({ postId: 'p1', userId: 'owner' })
    postLikeCount.mockResolvedValue(4)

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/posts/p1/likes' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ liked: true, likeCount: 4 })
    await app.close()
  })

  it('POST /:id/likes — unlike returns liked=false with the decremented count', async () => {
    postFindUnique.mockResolvedValue(FRIENDS_ONLY_POST)
    authedAs('owner')
    postLikeFindUnique.mockResolvedValue({ postId: 'p1', userId: 'owner' }) // already liked → toggle OFF
    postLikeDelete.mockResolvedValue({})
    postLikeCount.mockResolvedValue(0)

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/posts/p1/likes' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ liked: false, likeCount: 0 })
    await app.close()
  })
})
