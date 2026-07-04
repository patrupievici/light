import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Prisma + collaborator mocks ───────────────────────────────────────────────
const story = {
  create: vi.fn(),
  update: vi.fn(),
  findMany: vi.fn(),
  findUnique: vi.fn(),
  delete: vi.fn(),
}
const storyLike = {
  groupBy: vi.fn(),
  findMany: vi.fn(),
  findUnique: vi.fn(),
  create: vi.fn(),
  delete: vi.fn(),
  count: vi.fn(),
}

vi.mock('../lib/prisma', () => ({
  prisma: {
    userBlock: { findMany: async () => [], findFirst: async () => null },
    story: {
      create: (...a: unknown[]) => story.create(...a),
      update: (...a: unknown[]) => story.update(...a),
      findMany: (...a: unknown[]) => story.findMany(...a),
      findUnique: (...a: unknown[]) => story.findUnique(...a),
      delete: (...a: unknown[]) => story.delete(...a),
    },
    storyLike: {
      groupBy: (...a: unknown[]) => storyLike.groupBy(...a),
      findMany: (...a: unknown[]) => storyLike.findMany(...a),
      findUnique: (...a: unknown[]) => storyLike.findUnique(...a),
      create: (...a: unknown[]) => storyLike.create(...a),
      delete: (...a: unknown[]) => storyLike.delete(...a),
      count: (...a: unknown[]) => storyLike.count(...a),
    },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

const photo = {
  decodePostPhotoBase64: vi.fn(),
  saveStoryPhoto: vi.fn(),
  deleteStoryPhoto: vi.fn(),
}
vi.mock('../lib/post-photo', () => ({
  decodePostPhotoBase64: (...a: unknown[]) => photo.decodePostPhotoBase64(...a),
  saveStoryPhoto: (...a: unknown[]) => photo.saveStoryPhoto(...a),
  deleteStoryPhoto: (...a: unknown[]) => photo.deleteStoryPhoto(...a),
}))

const friendships = {
  areFriends: vi.fn(async () => true),
  isBlockedEitherWay: vi.fn(async () => false),
}
vi.mock('../lib/friendships', () => ({
  acceptedFriendIds: vi.fn(async () => ['friendA']),
  blockedUserIds: vi.fn(async () => []),
  areFriends: (...a: unknown[]) => friendships.areFriends(...(a as [])),
  isBlockedEitherWay: (...a: unknown[]) => friendships.isBlockedEitherWay(...(a as [])),
}))
vi.mock('../lib/user-display', () => ({
  getUserDisplayHints: vi.fn(async () => new Map([['u1', { displayName: 'Me', username: 'me' }]])),
}))

import { storyRoutes } from './stories'

async function buildApp() {
  const app = Fastify()
  await app.register(storyRoutes, { prefix: '/v1/stories' })
  await app.ready()
  return app
}

const UUID = '11111111-1111-1111-1111-111111111111'

beforeEach(() => {
  for (const m of [...Object.values(story), ...Object.values(storyLike), ...Object.values(photo)]) {
    ;(m as ReturnType<typeof vi.fn>).mockReset()
  }
  // Default: viewer is an accepted, non-blocked friend so the visibility gate
  // passes; the enumeration test overrides areFriends to false.
  friendships.areFriends.mockReset()
  friendships.areFriends.mockResolvedValue(true)
  friendships.isBlockedEitherWay.mockReset()
  friendships.isBlockedEitherWay.mockResolvedValue(false)
})

describe('POST /v1/stories', () => {
  it('creates a text-only story (no photo lib touched)', async () => {
    story.create.mockResolvedValue({ id: 'st1', userId: 'u1', caption: 'hi', location: null, imageUrl: null })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/stories', payload: { caption: 'hi' } })
    expect(res.statusCode).toBe(201)
    expect(res.json().data.id).toBe('st1')
    expect(photo.saveStoryPhoto).not.toHaveBeenCalled()
    await app.close()
  })

  it('saves an attached photo via saveStoryPhoto (the /uploads/stories path, NOT posts)', async () => {
    story.create.mockResolvedValue({ id: 'st2', userId: 'u1', caption: null, location: null, imageUrl: null })
    story.update.mockResolvedValue({})
    photo.decodePostPhotoBase64.mockReturnValue(Buffer.from('x'))
    photo.saveStoryPhoto.mockResolvedValue('/uploads/stories/st2.jpg')

    const app = await buildApp()
    const res = await app.inject({
      method: 'POST', url: '/v1/stories', payload: { imageBase64: 'ZGF0YQ==' },
    })

    expect(res.statusCode).toBe(201)
    expect(photo.saveStoryPhoto).toHaveBeenCalledWith('st2', expect.any(Buffer))
    expect(res.json().data.imageUrl).toBe('/uploads/stories/st2.jpg')
    await app.close()
  })
})

describe('GET /v1/stories/feed', () => {
  it('returns enriched stories with likeCount + likedByMe', async () => {
    story.findMany.mockResolvedValue([
      { id: 'st1', userId: 'u1', caption: 'c', imageUrl: '/uploads/stories/st1.jpg', location: null, expiresAt: new Date(Date.now() + 3600_000), createdAt: new Date() },
    ])
    storyLike.groupBy.mockResolvedValue([{ storyId: 'st1', _count: { storyId: 3 } }])
    storyLike.findMany.mockResolvedValue([{ storyId: 'st1' }])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/stories/feed' })
    expect(res.statusCode).toBe(200)
    const item = res.json().data[0]
    expect(item.id).toBe('st1')
    expect(item.authorName).toBe('Me')
    expect(item.likeCount).toBe(3)
    expect(item.likedByMe).toBe(true)
    await app.close()
  })

  it('returns an empty list when there are no active stories', async () => {
    story.findMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/stories/feed' })
    expect(res.json().data).toEqual([])
    await app.close()
  })
})

describe('POST /v1/stories/:id/like', () => {
  it('likes a story that is not yet liked', async () => {
    story.findUnique.mockResolvedValue({ id: UUID, expiresAt: new Date(Date.now() + 3600_000) })
    storyLike.findUnique.mockResolvedValue(null)
    storyLike.create.mockResolvedValue({})
    storyLike.count.mockResolvedValue(1)

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/stories/${UUID}/like` })
    expect(res.statusCode).toBe(200)
    expect(res.json().data).toMatchObject({ liked: true, likeCount: 1 })
    expect(storyLike.create).toHaveBeenCalledOnce()
    await app.close()
  })

  it('404s on an expired story', async () => {
    story.findUnique.mockResolvedValue({ id: UUID, expiresAt: new Date(Date.now() - 1000) })
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/stories/${UUID}/like` })
    expect(res.statusCode).toBe(404)
    await app.close()
  })

  it('#83 — a non-friend gets the SAME 404 as a missing story (no enumeration, no like)', async () => {
    story.findUnique.mockResolvedValue({
      id: UUID, userId: 'stranger', expiresAt: new Date(Date.now() + 3600_000),
    })
    friendships.areFriends.mockResolvedValue(false)

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/stories/${UUID}/like` })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    // The like is never created and no existence signal leaks beyond the 404.
    expect(storyLike.create).not.toHaveBeenCalled()
    expect(storyLike.findUnique).not.toHaveBeenCalled()
    await app.close()
  })

  it('owner can like their own story (gate skipped)', async () => {
    story.findUnique.mockResolvedValue({
      id: UUID, userId: 'u1', expiresAt: new Date(Date.now() + 3600_000),
    })
    storyLike.findUnique.mockResolvedValue(null)
    storyLike.create.mockResolvedValue({})
    storyLike.count.mockResolvedValue(1)

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/stories/${UUID}/like` })
    expect(res.statusCode).toBe(200)
    expect(friendships.areFriends).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('DELETE /v1/stories/:id', () => {
  it('owner deletes the story AND its on-disk photo', async () => {
    story.findUnique.mockResolvedValue({ id: UUID, userId: 'u1', imageUrl: '/uploads/stories/x.jpg' })
    story.delete.mockResolvedValue({})

    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/stories/${UUID}` })
    expect(res.statusCode).toBe(204)
    expect(story.delete).toHaveBeenCalledOnce()
    expect(photo.deleteStoryPhoto).toHaveBeenCalledWith('/uploads/stories/x.jpg')
    await app.close()
  })

  it('does not call deleteStoryPhoto when the story had no image', async () => {
    story.findUnique.mockResolvedValue({ id: UUID, userId: 'u1', imageUrl: null })
    story.delete.mockResolvedValue({})
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/stories/${UUID}` })
    expect(res.statusCode).toBe(204)
    expect(photo.deleteStoryPhoto).not.toHaveBeenCalled()
    await app.close()
  })

  it("403s when deleting someone else's story", async () => {
    story.findUnique.mockResolvedValue({ id: UUID, userId: 'someoneElse', imageUrl: null })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/stories/${UUID}` })
    expect(res.statusCode).toBe(403)
    expect(story.delete).not.toHaveBeenCalled()
    await app.close()
  })
})
