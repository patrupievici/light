import { beforeEach, describe, expect, it, vi } from 'vitest'
import Fastify from 'fastify'
import jwt from '@fastify/jwt'

const userFindUnique = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    user: { findUnique: (...args: unknown[]) => userFindUnique(...args) },
  },
}))

import { authenticate } from './auth'

async function buildApp() {
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret-test-secret-test-secret-32' })
  app.get('/protected', { preHandler: authenticate }, async () => ({ ok: true }))
  await app.ready()
  return app
}

beforeEach(() => {
  userFindUnique.mockReset()
})

describe('authenticate', () => {
  it('allows a signed token only while its account is active', async () => {
    userFindUnique.mockResolvedValue({ status: 'active' })
    const app = await buildApp()
    const token = app.jwt.sign({ userId: 'user-1', email: 'active@example.com' })

    const response = await app.inject({
      method: 'GET',
      url: '/protected',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(response.statusCode).toBe(200)
    expect(userFindUnique).toHaveBeenCalledWith({
      where: { id: 'user-1' },
      select: { status: true },
    })
    await app.close()
  })

  it.each([
    ['missing', null],
    ['disabled', { status: 'disabled' }],
    ['soft-deleted', { status: 'deleted' }],
  ])('rejects a valid token for a %s account', async (_label, account) => {
    userFindUnique.mockResolvedValue(account)
    const app = await buildApp()
    const token = app.jwt.sign({ userId: 'user-1', email: 'blocked@example.com' })

    const response = await app.inject({
      method: 'GET',
      url: '/protected',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(response.statusCode).toBe(401)
    expect(response.json()).toMatchObject({ error: 'UNAUTHORIZED' })
    await app.close()
  })

  it('rejects an invalid token without querying account state', async () => {
    const app = await buildApp()

    const response = await app.inject({
      method: 'GET',
      url: '/protected',
      headers: { authorization: 'Bearer invalid-token' },
    })

    expect(response.statusCode).toBe(401)
    expect(userFindUnique).not.toHaveBeenCalled()
    await app.close()
  })
})
