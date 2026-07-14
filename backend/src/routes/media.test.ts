import { Readable } from 'node:stream'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import Fastify from 'fastify'

const {
  postFindUnique,
  profileFindUnique,
  storyFindUnique,
  storedMediaFindUnique,
  userFindUnique,
  canViewerSeePost,
  areFriends,
  areUsersBlocked,
  stat,
  createReadStream,
} = vi.hoisted(() => ({
  postFindUnique: vi.fn(),
  profileFindUnique: vi.fn(),
  storyFindUnique: vi.fn(),
  storedMediaFindUnique: vi.fn(),
  userFindUnique: vi.fn(),
  canViewerSeePost: vi.fn(),
  areFriends: vi.fn(),
  areUsersBlocked: vi.fn(),
  stat: vi.fn(),
  createReadStream: vi.fn(),
}))

vi.mock('../lib/prisma', () => ({
  prisma: {
    post: { findUnique: (...a: unknown[]) => postFindUnique(...a) },
    userProfile: { findUnique: (...a: unknown[]) => profileFindUnique(...a) },
    story: { findUnique: (...a: unknown[]) => storyFindUnique(...a) },
    storedMedia: { findUnique: (...a: unknown[]) => storedMediaFindUnique(...a) },
    user: { findUnique: (...a: unknown[]) => userFindUnique(...a) },
  },
}))

vi.mock('../lib/post-visibility', () => ({
  canViewerSeePost: (...a: unknown[]) => canViewerSeePost(...a),
}))

vi.mock('../lib/friendships', () => ({
  areFriends: (...a: unknown[]) => areFriends(...a),
  areUsersBlocked: (...a: unknown[]) => areUsersBlocked(...a),
}))

vi.mock('../lib/post-photo', () => ({
  uploadsRoot: () => process.cwd(),
}))

vi.mock('node:fs', () => ({
  default: {
    promises: { stat: (...a: unknown[]) => stat(...a) },
    createReadStream: (...a: unknown[]) => createReadStream(...a),
  },
}))

let authImpl: (request: { user?: { userId: string; email: string } }, reply: {
  code: (status: number) => { send: (body: unknown) => unknown }
}) => Promise<unknown>

vi.mock('../middleware/auth', () => ({
  authenticate: async (request: never, reply: never) => authImpl(request, reply),
}))

import { mediaRoutes } from './media'

const POST_ID = '11111111-1111-1111-1111-111111111111'
const OWNER_ID = '22222222-2222-2222-2222-222222222222'
const STORY_ID = '33333333-3333-3333-3333-333333333333'

function authenticatedAs(userId = 'viewer') {
  authImpl = async (request) => {
    request.user = { userId, email: `${userId}@zvelt.test` }
  }
}

function unauthenticated() {
  authImpl = async (_request, reply) =>
    reply.code(401).send({ error: 'UNAUTHORIZED', message: 'No token' })
}

async function buildApp() {
  const app = Fastify()
  await app.register(mediaRoutes, { prefix: '/uploads' })
  await app.ready()
  return app
}

beforeEach(() => {
  for (const mock of [
    postFindUnique,
    profileFindUnique,
    storyFindUnique,
    storedMediaFindUnique,
    userFindUnique,
    canViewerSeePost,
    areFriends,
    areUsersBlocked,
    stat,
    createReadStream,
  ]) {
    mock.mockReset()
  }
  authenticatedAs()
  userFindUnique.mockResolvedValue({ status: 'active' })
  canViewerSeePost.mockResolvedValue(true)
  areFriends.mockResolvedValue(true)
  areUsersBlocked.mockResolvedValue(false)
  storedMediaFindUnique.mockResolvedValue(null)
  stat.mockResolvedValue({ isFile: () => true })
  createReadStream.mockReturnValue(Readable.from(Buffer.from('image-bytes')))
})

describe('authenticated media delivery', () => {
  it('rejects an unauthenticated direct image URL before any database read', async () => {
    unauthenticated()
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/uploads/posts/${POST_ID}.jpg` })

    expect(res.statusCode).toBe(401)
    expect(postFindUnique).not.toHaveBeenCalled()
    await app.close()
  })

  it('returns the same 404 for a private post a viewer cannot see', async () => {
    postFindUnique.mockResolvedValue({
      userId: OWNER_ID,
      visibility: 'private',
      imageUrl: `/uploads/posts/${POST_ID}.jpg`,
    })
    canViewerSeePost.mockResolvedValue(false)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/uploads/posts/${POST_ID}.jpg` })

    expect(res.statusCode).toBe(404)
    expect(res.payload).not.toContain('image-bytes')
    await app.close()
  })

  it('does not disclose a deleted account image even while an orphaned file exists', async () => {
    postFindUnique.mockResolvedValue({
      userId: OWNER_ID,
      visibility: 'public',
      imageUrl: `/uploads/posts/${POST_ID}.jpg`,
    })
    userFindUnique.mockResolvedValue({ status: 'deleted' })
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/uploads/posts/${POST_ID}.jpg` })

    expect(res.statusCode).toBe(404)
    expect(createReadStream).not.toHaveBeenCalled()
    await app.close()
  })

  it('blocks a blocked viewer from a private avatar URL', async () => {
    profileFindUnique.mockResolvedValue({
      userId: OWNER_ID,
      privacyDefault: 'friends',
      photoUrl: `/uploads/avatars/${OWNER_ID}.png`,
    })
    areUsersBlocked.mockResolvedValue(true)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/uploads/avatars/${OWNER_ID}.png` })

    expect(res.statusCode).toBe(404)
    expect(areFriends).not.toHaveBeenCalled()
    await app.close()
  })

  it('rejects a guessed filename or extension without serving the real file', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/uploads/posts/${POST_ID}.gif` })

    expect(res.statusCode).toBe(404)
    expect(postFindUnique).not.toHaveBeenCalled()
    expect(createReadStream).not.toHaveBeenCalled()
    await app.close()
  })

  it('serves an authorized active story with no-store authorization-aware cache headers', async () => {
    storyFindUnique.mockResolvedValue({
      userId: OWNER_ID,
      imageUrl: `/uploads/stories/${STORY_ID}.webp`,
      expiresAt: new Date(Date.now() + 60_000),
    })
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/uploads/stories/${STORY_ID}.webp` })

    expect(res.statusCode).toBe(200)
    expect(res.headers['cache-control']).toContain('no-store')
    expect(res.headers.vary).toBe('Authorization')
    expect(res.headers['x-content-type-options']).toBe('nosniff')
    expect(res.payload).toBe('image-bytes')
    await app.close()
  })

  it('serves durable database bytes without touching the ephemeral filesystem', async () => {
    storyFindUnique.mockResolvedValue({
      userId: OWNER_ID,
      imageUrl: `/uploads/stories/${STORY_ID}.webp`,
      expiresAt: new Date(Date.now() + 60_000),
    })
    storedMediaFindUnique.mockResolvedValue({
      ownerUserId: OWNER_ID,
      kind: 'stories',
      contentType: 'image/webp',
      data: Buffer.from('durable-image-bytes'),
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: `/uploads/stories/${STORY_ID}.webp`,
    })

    expect(res.statusCode).toBe(200)
    expect(res.payload).toBe('durable-image-bytes')
    expect(stat).not.toHaveBeenCalled()
    expect(createReadStream).not.toHaveBeenCalled()
    await app.close()
  })

  it('rejects a durable row whose owner metadata does not match the story', async () => {
    storyFindUnique.mockResolvedValue({
      userId: OWNER_ID,
      imageUrl: `/uploads/stories/${STORY_ID}.webp`,
      expiresAt: new Date(Date.now() + 60_000),
    })
    storedMediaFindUnique.mockResolvedValue({
      ownerUserId: '44444444-4444-4444-4444-444444444444',
      kind: 'stories',
      contentType: 'image/webp',
      data: Buffer.from('wrong-owner-bytes'),
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: `/uploads/stories/${STORY_ID}.webp`,
    })

    expect(res.statusCode).toBe(404)
    expect(res.payload).not.toContain('wrong-owner-bytes')
    expect(stat).not.toHaveBeenCalled()
    await app.close()
  })
})
