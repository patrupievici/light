import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// POST wraps a per-type upsert array in prisma.$transaction([...]). We stub
// `healthConsent.upsert` to return a marker and `$transaction` to resolve the
// array (Promise.all-style), so we can assert one upsert PER consent entry with
// the right composite key.
const healthConsentFindMany = vi.fn()
const healthConsentUpsert = vi.fn()
const healthConsentEventCreate = vi.fn()
const transaction = vi.fn((ops: unknown[]) => Promise.all(ops as Promise<unknown>[]))

vi.mock('../lib/prisma', () => ({
  prisma: {
    healthConsent: {
      findMany: (...a: unknown[]) => healthConsentFindMany(...a),
      upsert: (...a: unknown[]) => healthConsentUpsert(...a),
    },
    healthConsentEvent: {
      create: (...a: unknown[]) => healthConsentEventCreate(...a),
    },
    $transaction: (...a: unknown[]) => transaction(a[0] as unknown[]),
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { healthConsentRoutes } from './health-consent'

async function buildApp() {
  const app = Fastify()
  await app.register(healthConsentRoutes, { prefix: '/v1' })
  await app.ready()
  return app
}

beforeEach(() => {
  healthConsentFindMany.mockReset()
  healthConsentUpsert.mockReset()
  healthConsentEventCreate.mockReset()
  transaction.mockClear()
  // upsert / event-create return markers so the route's $transaction([...]) resolves.
  healthConsentUpsert.mockReturnValue(Promise.resolve({ ok: true }))
  healthConsentEventCreate.mockReturnValue(Promise.resolve({ id: 'evt' }))
})

describe('GET /v1/me/health-consents — ledger', () => {
  it("returns the user's consent ledger with serialized timestamps", async () => {
    healthConsentFindMany.mockResolvedValue([
      {
        consentType: 'sleep',
        granted: true,
        consentVersion: '1',
        source: 'healthkit',
        grantedAt: new Date('2026-06-01T10:00:00Z'),
        revokedAt: null,
      },
      {
        consentType: 'heart_rate',
        granted: false,
        consentVersion: '1',
        source: null,
        grantedAt: new Date('2026-06-02T10:00:00Z'),
        revokedAt: new Date('2026-06-03T10:00:00Z'),
      },
    ])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/me/health-consents' })

    expect(res.statusCode).toBe(200)
    const data = res.json().data
    expect(data).toHaveLength(2)
    // Per-type granularity surfaces: sleep granted, heart_rate revoked.
    expect(data[0]).toMatchObject({ consentType: 'sleep', granted: true, revokedAt: null })
    expect(data[1]).toMatchObject({ consentType: 'heart_rate', granted: false })
    expect(data[1].revokedAt).toBe('2026-06-03T10:00:00.000Z')
    // The ledger is scoped to the authenticated user.
    expect((healthConsentFindMany.mock.calls[0][0] as { where: { userId: string } }).where.userId).toBe('u1')
    await app.close()
  })
})

describe('POST /v1/me/health-consents — record decisions', () => {
  it('upserts one row per consent entry, keyed by (userId, consentType)', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/health-consents',
      payload: {
        consents: [
          { consentType: 'sleep', granted: true, source: 'healthkit' },
          { consentType: 'heart_rate', granted: false },
        ],
      },
    })

    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ ok: true })
    expect(transaction).toHaveBeenCalledOnce()
    expect(healthConsentUpsert).toHaveBeenCalledTimes(2)
    const firstWhere = (healthConsentUpsert.mock.calls[0][0] as {
      where: { userId_consentType: { userId: string; consentType: string } }
    }).where.userId_consentType
    expect(firstWhere).toMatchObject({ userId: 'u1', consentType: 'sleep' })
    await app.close()
  })

  it('appends one immutable ledger event per decision alongside the state upsert', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/health-consents',
      payload: {
        consents: [
          { consentType: 'sleep', granted: true, source: 'healthkit', consentVersion: '2' },
          { consentType: 'heart_rate', granted: false },
        ],
      },
    })

    expect(res.statusCode).toBe(201)
    // One event row per consent decision — the verifiable Art.7 history.
    expect(healthConsentEventCreate).toHaveBeenCalledTimes(2)
    // Both the current-state upsert and the immutable event share the transaction.
    expect(transaction).toHaveBeenCalledOnce()
    const grantData = (healthConsentEventCreate.mock.calls[0][0] as {
      data: { userId: string; consentType: string; granted: boolean; consentVersion: string; source: string | null }
    }).data
    expect(grantData).toMatchObject({
      userId: 'u1',
      consentType: 'sleep',
      granted: true,
      consentVersion: '2',
      source: 'healthkit',
    })
    const revokeData = (healthConsentEventCreate.mock.calls[1][0] as {
      data: { consentType: string; granted: boolean; source: string | null }
    }).data
    // A revoke is recorded as granted=false with a null source when omitted.
    expect(revokeData).toMatchObject({ consentType: 'heart_rate', granted: false, source: null })
    await app.close()
  })

  it('a REVOKED consent (granted=false) sets revokedAt on create', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/health-consents',
      payload: { consents: [{ consentType: 'weight', granted: false }] },
    })

    expect(res.statusCode).toBe(201)
    const arg = healthConsentUpsert.mock.calls[0][0] as {
      create: { granted: boolean; revokedAt: Date | null }
      update: { granted: boolean; revokedAt: Date | null }
    }
    // granted=false → revokedAt timestamped (not null) in both create and update.
    expect(arg.create.granted).toBe(false)
    expect(arg.create.revokedAt).toBeInstanceOf(Date)
    expect(arg.update.revokedAt).toBeInstanceOf(Date)
    await app.close()
  })

  it('a GRANTED consent clears revokedAt (null) and stamps grantedAt', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/health-consents',
      payload: { consents: [{ consentType: 'steps', granted: true }] },
    })

    expect(res.statusCode).toBe(201)
    const arg = healthConsentUpsert.mock.calls[0][0] as {
      create: { granted: boolean; revokedAt: Date | null; grantedAt: Date }
    }
    expect(arg.create.granted).toBe(true)
    expect(arg.create.revokedAt).toBeNull()
    expect(arg.create.grantedAt).toBeInstanceOf(Date)
    await app.close()
  })

  it('400 on an INVALID consentType (not in the allowed enum)', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/health-consents',
      payload: { consents: [{ consentType: 'genome', granted: true }] },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    // No write happens for an invalid payload — neither state nor ledger.
    expect(transaction).not.toHaveBeenCalled()
    expect(healthConsentUpsert).not.toHaveBeenCalled()
    expect(healthConsentEventCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 on an empty consents array (min 1 enforced)', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/me/health-consents',
      payload: { consents: [] },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })
})
