import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
const userFindUnique = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: { user: { findUnique: (...a: unknown[]) => userFindUnique(...a) } },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

// profile.ts pulls in a few services at import; stub the ones that could read
// env / do work so the import stays pure for this route-focused test.
vi.mock('../services/streak.service', () => ({ getStreakStatus: vi.fn() }))
vi.mock('../services/gym-xp.service', () => ({ gameXpPayload: vi.fn() }))
vi.mock('../services/global-daily-quote', () => ({ loadDailyQuoteForApi: vi.fn() }))
vi.mock('../lib/post-photo', () => ({
  decodePostPhotoBase64: vi.fn(),
  saveAvatarPhoto: vi.fn(),
}))

import { profileRoutes } from './profile'

async function buildApp() {
  const app = Fastify()
  await app.register(profileRoutes, { prefix: '/v1' })
  await app.ready()
  return app
}

beforeEach(() => {
  userFindUnique.mockReset()
})

describe('GET /v1/me/export-data — GDPR portability without credentials', () => {
  it('never SELECTs authIdentities, refreshTokens, or password fields', async () => {
    userFindUnique.mockResolvedValue({ id: 'u1', profile: { displayName: 'Ana' } })
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/export-data' })

    expect(res.statusCode).toBe(200)
    expect(userFindUnique).toHaveBeenCalledOnce()
    const select = (userFindUnique.mock.calls[0][0] as { select: Record<string, unknown> }).select
    // Credentials must be absent from the projection entirely.
    expect(select).not.toHaveProperty('authIdentities')
    expect(select).not.toHaveProperty('refreshTokens')
    expect(select).not.toHaveProperty('password')
    expect(select).not.toHaveProperty('passwordHash')
    // Sanity: it DOES export the user's own content.
    expect(select).toHaveProperty('workouts')
    expect(select).toHaveProperty('profile')
    await app.close()
  })

  it('the serialized response body contains no password hash / token material', async () => {
    // Even if a hash were accidentally hung off a relation, the body must not
    // carry it. We feed a payload WITHOUT secrets and assert the contract holds.
    userFindUnique.mockResolvedValue({
      id: 'u1',
      status: 'active',
      profile: { displayName: 'Ana', username: 'ana' },
      workouts: [],
    })
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/export-data' })

    expect(res.statusCode).toBe(200)
    const lower = res.payload.toLowerCase()
    expect(lower).not.toContain('passwordhash')
    expect(lower).not.toContain('password_hash')
    expect(lower).not.toContain('tokenhash')
    expect(lower).not.toContain('refreshtoken')
    // Download headers are set so the client treats it as a file.
    expect(res.headers['content-disposition']).toContain('attachment')
    expect(res.headers['cache-control']).toContain('no-store')
    await app.close()
  })

  it('returns 404 when the account no longer exists', async () => {
    userFindUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/export-data' })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'USER_NOT_FOUND' })
    await app.close()
  })
})
