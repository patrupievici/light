import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'
import jwt from '@fastify/jwt'

// ── Mocks ───────────────────────────────────────────────────────────────────
const authIdentityFindFirst = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    authIdentity: { findFirst: (...a: unknown[]) => authIdentityFindFirst(...a) },
    // issueSession persists a hashed refresh token on the login success path.
    refreshToken: { create: vi.fn().mockResolvedValue({}) },
    user: { findUnique: vi.fn().mockResolvedValue({ status: 'active', softDeletedAt: null }) },
  },
}))

// google-auth-library is imported at module top; stub it so the import is cheap
// and never reaches the network.
vi.mock('google-auth-library', () => ({ OAuth2Client: class {} }))

import { authRoutes } from './auth'

async function buildApp() {
  const app = Fastify()
  // The login/signup success paths sign a JWT via app.jwt.sign — register it
  // with a test-only secret so those code paths don't crash.
  await app.register(jwt, { secret: 'test-secret-test-secret-test-secret-32' })
  await app.register(authRoutes, { prefix: '/v1/auth' })
  await app.ready()
  return app
}

beforeEach(() => {
  authIdentityFindFirst.mockReset()
})

describe('POST /v1/auth/signup — password policy', () => {
  it('rejects a short (<8 char) password with 400 VALIDATION_ERROR before any DB write', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/signup',
      payload: { email: 'new@user.dev', password: 'short' },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    // Validation rejects before the email-taken lookup runs.
    expect(authIdentityFindFirst).not.toHaveBeenCalled()
    await app.close()
  })

  it('rejects a malformed email with 400', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/signup',
      payload: { email: 'not-an-email', password: 'longenoughpassword' },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })
})

describe('POST /v1/auth/login — credential check', () => {
  it('returns 401 INVALID_CREDENTIALS when the email has no identity', async () => {
    authIdentityFindFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'ghost@user.dev', password: 'whatever-pass' },
    })

    expect(res.statusCode).toBe(401)
    expect(res.json()).toMatchObject({ error: 'INVALID_CREDENTIALS' })
    await app.close()
  })

  it('returns 401 INVALID_CREDENTIALS when the password does not match the stored hash', async () => {
    const bcrypt = (await import('bcryptjs')).default
    const realHash = await bcrypt.hash('the-correct-password', 4)
    authIdentityFindFirst.mockResolvedValue({
      userId: 'u1',
      passwordHash: realHash,
      user: { status: 'active' },
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'real@user.dev', password: 'the-WRONG-password' },
    })

    expect(res.statusCode).toBe(401)
    expect(res.json()).toMatchObject({ error: 'INVALID_CREDENTIALS' })
    // The same generic error/message is returned for both "no user" and "bad
    // password" — no user-enumeration leak.
    expect(res.json().message).not.toMatch(/not found|no such/i)
    await app.close()
  })

  it('returns 403 ACCOUNT_DELETED for a soft-deleted user (softDeletedAt set)', async () => {
    const bcrypt = (await import('bcryptjs')).default
    const realHash = await bcrypt.hash('the-correct-password', 4)
    authIdentityFindFirst.mockResolvedValue({
      userId: 'u1',
      passwordHash: realHash,
      // status may still read "active" mid-flight; softDeletedAt is authoritative.
      user: { status: 'active', softDeletedAt: new Date() },
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'real@user.dev', password: 'the-correct-password' },
    })

    expect(res.statusCode).toBe(403)
    expect(res.json()).toMatchObject({ error: 'ACCOUNT_DELETED' })
    await app.close()
  })

  it('returns 403 ACCOUNT_DELETED for a user with status="deleted"', async () => {
    const bcrypt = (await import('bcryptjs')).default
    const realHash = await bcrypt.hash('the-correct-password', 4)
    authIdentityFindFirst.mockResolvedValue({
      userId: 'u1',
      passwordHash: realHash,
      user: { status: 'deleted', softDeletedAt: null },
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'real@user.dev', password: 'the-correct-password' },
    })

    expect(res.statusCode).toBe(403)
    expect(res.json()).toMatchObject({ error: 'ACCOUNT_DELETED' })
    await app.close()
  })

  it('still logs in an active account (guard is a no-op when not soft-deleted)', async () => {
    const bcrypt = (await import('bcryptjs')).default
    const realHash = await bcrypt.hash('the-correct-password', 4)
    authIdentityFindFirst.mockResolvedValue({
      userId: 'u1',
      passwordHash: realHash,
      user: { status: 'active', softDeletedAt: null },
    })
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'real@user.dev', password: 'the-correct-password' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ user: { id: 'u1' } })
    await app.close()
  })

  it('rejects a login missing the password field with 400', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'real@user.dev' },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })
})
