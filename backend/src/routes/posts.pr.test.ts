import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
const postFindMany = vi.fn()
const userProfileFindMany = vi.fn()
const friendshipFindMany = vi.fn()
const postHideFindMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    userBlock: { findMany: async () => [], findFirst: async () => null },
    post: { findMany: (...a: unknown[]) => postFindMany(...a) },
    userProfile: { findMany: (...a: unknown[]) => userProfileFindMany(...a) },
    friendship: { findMany: (...a: unknown[]) => friendshipFindMany(...a) },
    postHide: { findMany: (...a: unknown[]) => postHideFindMany(...a) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'viewer', email: 'v@t.dev' }
  },
}))

import { postRoutes } from './posts'

async function buildApp() {
  const app = Fastify()
  await app.register(postRoutes, { prefix: '/v1/posts' })
  await app.ready()
  return app
}

beforeEach(() => {
  postFindMany.mockReset().mockResolvedValue([])
  userProfileFindMany.mockReset().mockResolvedValue([])
  friendshipFindMany.mockReset().mockResolvedValue([]) // no friends
  postHideFindMany.mockReset().mockResolvedValue([]) // nothing hidden
})

describe('GET /v1/posts/feed — PRs filter (kind=pr)', () => {
  it('restricts the query to isPr posts when kind=pr', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/feed?kind=pr' })

    expect(res.statusCode).toBe(200)
    const where = postFindMany.mock.calls[0][0].where
    expect(where.isPr).toBe(true)
    await app.close()
  })

  it('does NOT filter by isPr for the normal feed (no kind)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/posts/feed' })

    expect(res.statusCode).toBe(200)
    const where = postFindMany.mock.calls[0][0].where
    expect(where.isPr).toBeUndefined()
    await app.close()
  })
})
