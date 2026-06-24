import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'
import { Prisma } from '@prisma/client'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Route-level coverage for the body-measurements flow. The pure schema +
// serializer have their own tests in body-measurements.test.ts; here we drive
// the actual HTTP handlers so the upsert idempotency, per-user scoping, and
// Decimal→number serialization through the response are observable end-to-end.
//
// $transaction is invoked with a callback (interactive tx); we run it against a
// `tx` spy so the create-vs-update decision inside the route is exercised.
const txFindFirst = vi.fn()
const txUpdate = vi.fn()
const txCreate = vi.fn()
const tx = {
  userBodyMeasurement: {
    findFirst: (...a: unknown[]) => txFindFirst(...a),
    update: (...a: unknown[]) => txUpdate(...a),
    create: (...a: unknown[]) => txCreate(...a),
  },
}
const transaction = vi.fn(async (cb: (t: typeof tx) => unknown) => cb(tx))

const findMany = vi.fn()
const deleteMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    $transaction: (...a: unknown[]) => transaction(a[0] as never),
    userBodyMeasurement: {
      findMany: (...a: unknown[]) => findMany(...a),
      deleteMany: (...a: unknown[]) => deleteMany(...a),
    },
  },
}))

let meId = 'u1'
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: meId, email: `${meId}@t.dev` }
  },
}))

import { bodyMeasurementRoutes } from './body-measurements'

async function buildApp() {
  const app = Fastify()
  await app.register(bodyMeasurementRoutes, { prefix: '/v1/me' })
  await app.ready()
  return app
}

const ROW_ID = '11111111-1111-1111-1111-111111111111'

function makeRow(over: Partial<Record<string, unknown>> = {}) {
  return {
    id: ROW_ID,
    type: 'chest',
    valueNum: new Prisma.Decimal('98.500'),
    unit: 'cm',
    measuredAt: new Date('2026-06-13T12:00:00.000Z'),
    source: 'app',
    createdAt: new Date('2026-06-13T12:00:01.000Z'),
    updatedAt: new Date('2026-06-13T12:00:02.000Z'),
    ...over,
  }
}

beforeEach(() => {
  meId = 'u1'
  transaction.mockClear()
  for (const fn of [txFindFirst, txUpdate, txCreate, findMany, deleteMany]) fn.mockReset()
})

// ── POST /measurements — create vs upsert idempotency ────────────────────────
describe('POST /v1/me/measurements — create + upsert idempotency', () => {
  it('creates a new measurement when none exists at (userId, type, measuredAt)', async () => {
    txFindFirst.mockResolvedValue(null)
    txCreate.mockResolvedValue(makeRow())
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/measurements',
      payload: { type: 'chest', valueNum: 98.5, unit: 'cm', measuredAt: '2026-06-13T12:00:00.000Z' },
    })
    expect(res.statusCode).toBe(201)
    expect(txCreate).toHaveBeenCalledOnce()
    expect(txUpdate).not.toHaveBeenCalled()
    // Create is scoped to the authed user.
    expect(txCreate.mock.calls[0][0].data).toMatchObject({ userId: 'u1', type: 'chest' })
    // Decimal is serialized to a plain number in the response.
    const body = res.json()
    expect(body.valueNum).toBe(98.5)
    expect(typeof body.valueNum).toBe('number')
    await app.close()
  })

  it('updates the existing row (idempotent replay) instead of stacking a duplicate', async () => {
    txFindFirst.mockResolvedValue({ id: ROW_ID })
    txUpdate.mockResolvedValue(makeRow({ valueNum: new Prisma.Decimal('99.000') }))
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/measurements',
      payload: { type: 'chest', valueNum: 99, unit: 'cm', measuredAt: '2026-06-13T12:00:00.000Z' },
    })
    expect(res.statusCode).toBe(201)
    // Same (userId, type, measuredAt) → update path, no create.
    expect(txUpdate).toHaveBeenCalledOnce()
    expect(txCreate).not.toHaveBeenCalled()
    expect(txUpdate.mock.calls[0][0]).toMatchObject({ where: { id: ROW_ID }, data: { valueNum: 99 } })
    expect(res.json().valueNum).toBe(99)
    await app.close()
  })

  it('the upsert lookup is scoped to the authed user (no cross-user overwrite)', async () => {
    meId = 'attacker'
    txFindFirst.mockResolvedValue(null)
    txCreate.mockResolvedValue(makeRow())
    const app = await buildApp()
    await app.inject({
      method: 'POST',
      url: '/v1/me/measurements',
      payload: { type: 'chest', valueNum: 98.5, unit: 'cm', measuredAt: '2026-06-13T12:00:00.000Z' },
    })
    expect(txFindFirst.mock.calls[0][0].where).toMatchObject({ userId: 'attacker', type: 'chest' })
    await app.close()
  })

  it('400 VALIDATION_ERROR on an out-of-vocabulary type (controlled set)', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/measurements',
      payload: { type: 'wingspan', valueNum: 5, unit: 'cm' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 VALIDATION_ERROR on an out-of-vocabulary unit', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/measurements',
      payload: { type: 'weight', valueNum: 80, unit: 'stone' },
    })
    expect(res.statusCode).toBe(400)
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 VALIDATION_ERROR on a value outside 0..1000', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/measurements',
      payload: { type: 'weight', valueNum: 1001, unit: 'kg' },
    })
    expect(res.statusCode).toBe(400)
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })
})

// ── GET /measurements — per-user scoping + serialization ─────────────────────
describe('GET /v1/me/measurements — scoping, paging, serialization', () => {
  it('scopes the list to the authed user and serializes Decimal→number', async () => {
    findMany.mockResolvedValue([makeRow()])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/measurements' })
    expect(res.statusCode).toBe(200)
    expect(findMany.mock.calls[0][0].where).toEqual({ userId: 'u1' })
    const body = res.json()
    expect(body.data[0].valueNum).toBe(98.5)
    expect(typeof body.data[0].valueNum).toBe('number')
    expect(body.nextCursor).toBeNull()
    await app.close()
  })

  it('applies the type filter inside the user-scoped where clause', async () => {
    findMany.mockResolvedValue([])
    const app = await buildApp()
    await app.inject({ method: 'GET', url: '/v1/me/measurements?type=waist' })
    expect(findMany.mock.calls[0][0].where).toEqual({ userId: 'u1', type: 'waist' })
    await app.close()
  })

  it('returns nextCursor when an extra row signals more pages (limit+1 keyset)', async () => {
    const a = makeRow({ id: '11111111-1111-1111-1111-111111111111' })
    const b = makeRow({ id: '22222222-2222-2222-2222-222222222222' })
    findMany.mockResolvedValue([a, b]) // limit=1 fetches 2 → hasMore
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/measurements?limit=1' })
    const body = res.json()
    expect(body.data).toHaveLength(1)
    expect(body.nextCursor).toBe('11111111-1111-1111-1111-111111111111')
    expect(findMany.mock.calls[0][0].take).toBe(2)
    await app.close()
  })

  it('400 VALIDATION_ERROR on an invalid type filter', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/measurements?type=bogus' })
    expect(res.statusCode).toBe(400)
    expect(findMany).not.toHaveBeenCalled()
    await app.close()
  })
})

// ── DELETE /measurements/:id — owner-scoped delete ───────────────────────────
describe('DELETE /v1/me/measurements/:id — owner scoping', () => {
  it('204 when the row is deleted, scoped to (id, userId)', async () => {
    deleteMany.mockResolvedValue({ count: 1 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/me/measurements/${ROW_ID}` })
    expect(res.statusCode).toBe(204)
    expect(deleteMany).toHaveBeenCalledWith({ where: { id: ROW_ID, userId: 'u1' } })
    await app.close()
  })

  it("404 NOT_FOUND when deleting another user's row (count 0, no existence leak)", async () => {
    deleteMany.mockResolvedValue({ count: 0 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/me/measurements/${ROW_ID}` })
    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    await app.close()
  })

  it('400 VALIDATION_ERROR on a non-uuid id (no delete attempted)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/measurements/not-a-uuid' })
    expect(res.statusCode).toBe(400)
    expect(deleteMany).not.toHaveBeenCalled()
    await app.close()
  })
})
