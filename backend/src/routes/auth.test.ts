import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'
import jwt from '@fastify/jwt'

// ── Mocks ───────────────────────────────────────────────────────────────────
const authIdentityFindFirst = vi.fn()
const authIdentityUpdate = vi.fn()
const refreshTokenDeleteMany = vi.fn()
const prismaTransaction = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    authIdentity: {
      findFirst: (...a: unknown[]) => authIdentityFindFirst(...a),
      update: (...a: unknown[]) => authIdentityUpdate(...a),
    },
    // issueSession persists a hashed refresh token on the login success path.
    refreshToken: {
      create: vi.fn().mockResolvedValue({}),
      deleteMany: (...a: unknown[]) => refreshTokenDeleteMany(...a),
    },
    user: { findUnique: vi.fn().mockResolvedValue({ status: 'active', softDeletedAt: null }) },
    $transaction: (...a: unknown[]) => prismaTransaction(...a),
  },
}))

// google-auth-library is imported at module top; stub it so the import is cheap
// and never reaches the network.
vi.mock('google-auth-library', () => ({ OAuth2Client: class {} }))

// The forgot-password route sends mail; stub it so tests never log codes or
// touch the network, and so we can assert on when it fires.
const sendPasswordResetEmail = vi.fn().mockResolvedValue(undefined)
vi.mock('../services/mail.service', () => ({
  sendPasswordResetEmail: (...a: unknown[]) => sendPasswordResetEmail(...a),
}))

// The reset-code HMAC is keyed with JWT_SECRET (read at call time); pin it so
// resetCodeForWindow() in tests derives the same codes as the route handlers.
process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-32'

import { authRoutes, resetCodeForWindow, resetCodeWindow } from './auth'

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
  authIdentityUpdate.mockReset().mockResolvedValue({})
  refreshTokenDeleteMany.mockReset().mockResolvedValue({ count: 0 })
  prismaTransaction.mockReset().mockResolvedValue([])
  sendPasswordResetEmail.mockClear()
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

describe('POST /v1/auth/attach-email — secure an instant account', () => {
  function token(app: Awaited<ReturnType<typeof buildApp>>, userId = 'u1') {
    return app.jwt.sign({ userId, email: `guest_${userId}@guest.zvelt.app` })
  }

  it('401 without a bearer token', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/attach-email',
      payload: { email: 'real@user.dev', password: 'longenoughpassword' },
    })
    expect(res.statusCode).toBe(401)
    await app.close()
  })

  it('400 on a short password before any DB read', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/attach-email',
      headers: { authorization: `Bearer ${token(app)}` },
      payload: { email: 'real@user.dev', password: 'short' },
    })
    expect(res.statusCode).toBe(400)
    expect(authIdentityFindFirst).not.toHaveBeenCalled()
    await app.close()
  })

  it('409 when the email belongs to a DIFFERENT user', async () => {
    const app = await buildApp()
    authIdentityFindFirst.mockResolvedValueOnce({ userId: 'someone-else', email: 'real@user.dev' })
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/attach-email',
      headers: { authorization: `Bearer ${token(app)}` },
      payload: { email: 'real@user.dev', password: 'longenoughpassword' },
    })
    expect(res.statusCode).toBe(409)
    expect(res.json()).toMatchObject({ error: 'EMAIL_TAKEN' })
    await app.close()
  })

  it('200 replaces the placeholder identity with real credentials', async () => {
    const app = await buildApp()
    // free email (findFirst for "taken"), then the account's existing identity.
    authIdentityFindFirst
      .mockResolvedValueOnce(null) // email not taken
      .mockResolvedValueOnce({ id: 'id1', userId: 'u1', provider: 'email' }) // existing
    const txUpdate = vi.fn().mockResolvedValue({})
    prismaTransaction.mockImplementationOnce(async (fn: unknown) =>
      typeof fn === 'function'
        ? (fn as (tx: unknown) => unknown)({
            authIdentity: { update: txUpdate, create: vi.fn() },
            userProfile: { findUnique: vi.fn().mockResolvedValue(null), update: vi.fn() },
          })
        : [],
    )
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/attach-email',
      headers: { authorization: `Bearer ${token(app)}` },
      payload: { email: 'real@user.dev', password: 'longenoughpassword' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ ok: true, email: 'real@user.dev' })
    expect(txUpdate).toHaveBeenCalledTimes(1)
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

// ── Password reset (stateless HMAC codes) ───────────────────────────────────

const RESET_HASH = '$2a$04$fixedfakehashforresetcodesxxxxxxxxxxxxxxxxxxxxxxxxxxx'

function activeEmailIdentity() {
  return {
    id: 'ai1',
    userId: 'u1',
    provider: 'email',
    email: 'real@user.dev',
    passwordHash: RESET_HASH,
    user: { status: 'active', softDeletedAt: null },
  }
}

describe('POST /v1/auth/password/forgot — anti-enumeration', () => {
  it('returns the same generic 200 for an unknown email and sends no mail', async () => {
    authIdentityFindFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/forgot',
      payload: { email: 'ghost@user.dev' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ ok: true, message: 'If that email exists, we sent a code.' })
    expect(sendPasswordResetEmail).not.toHaveBeenCalled()
    await app.close()
  })

  it('returns the identical generic 200 for a known email — and emails a 6-digit code', async () => {
    authIdentityFindFirst.mockResolvedValue(activeEmailIdentity())
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/forgot',
      payload: { email: 'real@user.dev' },
    })

    expect(res.statusCode).toBe(200)
    // Byte-identical body to the unknown-email case — no enumeration signal.
    expect(res.json()).toMatchObject({ ok: true, message: 'If that email exists, we sent a code.' })
    expect(sendPasswordResetEmail).toHaveBeenCalledTimes(1)
    const [to, code] = sendPasswordResetEmail.mock.calls[0] as [string, string]
    expect(to).toBe('real@user.dev')
    expect(code).toMatch(/^\d{6}$/)
    expect(code).toBe(resetCodeForWindow('u1', RESET_HASH, resetCodeWindow()))
    await app.close()
  })
})

describe('POST /v1/auth/password/reset — code verification', () => {
  it('resets the password with a valid current-window code and revokes refresh tokens', async () => {
    authIdentityFindFirst.mockResolvedValue(activeEmailIdentity())
    const app = await buildApp()
    const code = resetCodeForWindow('u1', RESET_HASH, resetCodeWindow())
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/reset',
      payload: { email: 'real@user.dev', code, new_password: 'brand-new-password' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ ok: true })
    // New hash stored via the same bcrypt path as signup...
    expect(authIdentityUpdate).toHaveBeenCalledTimes(1)
    const updateArg = authIdentityUpdate.mock.calls[0][0] as {
      where: { id: string }
      data: { passwordHash: string }
    }
    expect(updateArg.where).toEqual({ id: 'ai1' })
    const bcrypt = (await import('bcryptjs')).default
    expect(await bcrypt.compare('brand-new-password', updateArg.data.passwordHash)).toBe(true)
    // ...and every session is revoked, atomically with the hash swap.
    expect(refreshTokenDeleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } })
    expect(prismaTransaction).toHaveBeenCalledTimes(1)
    await app.close()
  })

  it('accepts a previous-window code (grace so codes live 15-30 min)', async () => {
    authIdentityFindFirst.mockResolvedValue(activeEmailIdentity())
    const app = await buildApp()
    const code = resetCodeForWindow('u1', RESET_HASH, resetCodeWindow() - 1)
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/reset',
      payload: { email: 'real@user.dev', code, new_password: 'brand-new-password' },
    })

    expect(res.statusCode).toBe(200)
    await app.close()
  })

  it('rejects a wrong code with 400 INVALID_CODE and writes nothing', async () => {
    authIdentityFindFirst.mockResolvedValue(activeEmailIdentity())
    const app = await buildApp()
    const valid = resetCodeForWindow('u1', RESET_HASH, resetCodeWindow())
    // Guaranteed-wrong 6-digit code: flip the last digit of the valid one.
    const wrong = valid.slice(0, 5) + String((Number(valid[5]) + 1) % 10)
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/reset',
      payload: { email: 'real@user.dev', code: wrong, new_password: 'brand-new-password' },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'INVALID_CODE' })
    expect(prismaTransaction).not.toHaveBeenCalled()
    expect(authIdentityUpdate).not.toHaveBeenCalled()
    await app.close()
  })

  it('rejects an expired code (two windows old) with 400 INVALID_CODE', async () => {
    authIdentityFindFirst.mockResolvedValue(activeEmailIdentity())
    const app = await buildApp()
    const expired = resetCodeForWindow('u1', RESET_HASH, resetCodeWindow() - 2)
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/reset',
      payload: { email: 'real@user.dev', code: expired, new_password: 'brand-new-password' },
    })

    // NOTE: in the astronomically rare case the w-2 code collides with the
    // w/w-1 code this could flake; the HMAC input differs per window so a
    // collision chance is ~2 in 10^6 per run — acceptable for a unit test.
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'INVALID_CODE' })
    await app.close()
  })

  it('rejects a short (<8 char) new password with 400 VALIDATION_ERROR before any lookup', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/reset',
      payload: { email: 'real@user.dev', code: '123456', new_password: 'short' },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(authIdentityFindFirst).not.toHaveBeenCalled()
    await app.close()
  })

  it('returns INVALID_CODE (not a distinct error) for an unknown email with any code', async () => {
    authIdentityFindFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/password/reset',
      payload: { email: 'ghost@user.dev', code: '123456', new_password: 'brand-new-password' },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'INVALID_CODE' })
    await app.close()
  })
})
