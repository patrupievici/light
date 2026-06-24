import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
const wearableConnectionFindMany = vi.fn()
const wearableConnectionUpsert = vi.fn()
const wearableConnectionUpdateMany = vi.fn()
const userHealthImportUpsert = vi.fn()
const userHealthImportDeleteMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    wearableConnection: {
      findMany: (...a: unknown[]) => wearableConnectionFindMany(...a),
      upsert: (...a: unknown[]) => wearableConnectionUpsert(...a),
      updateMany: (...a: unknown[]) => wearableConnectionUpdateMany(...a),
    },
    userHealthImport: {
      upsert: (...a: unknown[]) => userHealthImportUpsert(...a),
      deleteMany: (...a: unknown[]) => userHealthImportDeleteMany(...a),
    },
  },
}))

// authenticate is swappable so we can prove auth-gated routes 401 before any
// provider parsing / DB read.
let authImpl: (req: { user?: { userId: string } }, reply: {
  code: (c: number) => { send: (b: unknown) => unknown }
}) => Promise<unknown>
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: never, reply: never) => authImpl(req, reply),
}))

import {
  integrationsRoutes,
  isTransientDbError,
  withDbRetry,
  parseImportInstant,
  buildHealthImportRecord,
  deriveHealthImportExternalId,
} from './integrations'

function authedAs(userId: string) {
  authImpl = async (req) => {
    req.user = { userId }
  }
}
function unauthenticated() {
  authImpl = async (_req, reply) => reply.code(401).send({ error: 'UNAUTHORIZED', message: 'no token' })
}

async function buildApp() {
  const app = Fastify()
  await app.register(integrationsRoutes, { prefix: '/v1/integrations' })
  await app.ready()
  return app
}

// Capture and clear Terra env so aggregatorConfigured() is deterministic.
const TERRA_ENV_KEYS = ['TERRA_DEV_ID', 'TERRA_API_KEY', 'WEARABLE_AGGREGATOR_PROVIDER'] as const
const savedEnv: Record<string, string | undefined> = {}

beforeEach(() => {
  wearableConnectionFindMany.mockReset()
  wearableConnectionUpsert.mockReset()
  wearableConnectionUpdateMany.mockReset()
  userHealthImportUpsert.mockReset()
  userHealthImportDeleteMany.mockReset()
  wearableConnectionUpdateMany.mockResolvedValue({ count: 0 })
  userHealthImportUpsert.mockResolvedValue({})
  userHealthImportDeleteMany.mockResolvedValue({ count: 0 })
  authedAs('u1')
  for (const k of TERRA_ENV_KEYS) {
    savedEnv[k] = process.env[k]
    delete process.env[k]
  }
})

afterEach(() => {
  for (const k of TERRA_ENV_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k]
    else process.env[k] = savedEnv[k]
  }
})

describe('GET /v1/integrations/:provider/auth-url — provider gating + auth', () => {
  it('401 for an unauthenticated request, before any provider parsing', async () => {
    unauthenticated()
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/integrations/garmin/auth-url' })

    expect(res.statusCode).toBe(401)
    await app.close()
  })

  it('404 UNKNOWN_PROVIDER for an unsupported provider', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/integrations/myspace/auth-url' })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'UNKNOWN_PROVIDER' })
    await app.close()
  })

  it('501 AGGREGATOR_NOT_CONFIGURED for a valid provider when Terra creds are absent', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/integrations/garmin/auth-url' })

    expect(res.statusCode).toBe(501)
    expect(res.json()).toMatchObject({
      error: 'AGGREGATOR_NOT_CONFIGURED',
      provider: 'garmin',
      requiredEnv: ['TERRA_DEV_ID', 'TERRA_API_KEY'],
    })
    // No external auth attempt → no connection row written.
    expect(wearableConnectionUpsert).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('POST /v1/integrations/:provider/sync', () => {
  it('404 UNKNOWN_PROVIDER for a bad provider', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/integrations/foobar/sync' })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'UNKNOWN_PROVIDER' })
    await app.close()
  })

  it('501 for a valid provider when the aggregator is not configured', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/integrations/whoop/sync' })

    expect(res.statusCode).toBe(501)
    expect(res.json()).toMatchObject({ error: 'AGGREGATOR_NOT_CONFIGURED', imported: 0 })
    await app.close()
  })
})

describe('GET /v1/integrations — listing', () => {
  it('returns the supported provider catalogue + the user\'s connections (unconfigured aggregator)', async () => {
    wearableConnectionFindMany.mockResolvedValue([
      { provider: 'garmin', updatedAt: new Date('2026-06-01T00:00:00Z'), status: 'synced' },
    ])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/integrations' })

    expect(res.statusCode).toBe(200)
    const body = res.json()
    // Provider catalogue present and all marked unconfigured (no Terra creds).
    expect(Array.isArray(body.providers)).toBe(true)
    expect(body.providers.length).toBeGreaterThan(0)
    expect(body.providers.every((p: { configured: boolean }) => p.configured === false)).toBe(true)
    expect(body.aggregator).toMatchObject({ configured: false })
    // The user's existing connection is surfaced and scoped to them.
    expect(body.integrations).toEqual([{ provider: 'garmin', updatedAt: '2026-06-01T00:00:00.000Z', status: 'synced' }])
    expect((wearableConnectionFindMany.mock.calls[0][0] as { where: { userId: string } }).where.userId).toBe('u1')
    await app.close()
  })

  it('degrades gracefully to empty integrations if the connection query throws (migration not applied)', async () => {
    wearableConnectionFindMany.mockRejectedValue(new Error('relation does not exist'))
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/integrations' })

    expect(res.statusCode).toBe(200)
    expect(res.json().integrations).toEqual([])
    await app.close()
  })
})

describe('strava stub endpoints (require auth)', () => {
  it('GET /strava/status returns connected:false', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/integrations/strava/status' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ connected: false })
    await app.close()
  })

  it('POST /strava/exchange returns 501 (not configured)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/integrations/strava/exchange', payload: {} })
    expect(res.statusCode).toBe(501)
    expect(res.json()).toMatchObject({ error: 'INTEGRATION_NOT_CONFIGURED' })
    await app.close()
  })
})

describe('isTransientDbError — only retry on infra-level failures', () => {
  it('treats known transient Prisma/Postgres codes as transient', () => {
    for (const code of ['P1001', 'P1002', 'P1008', 'P1017', 'P2024', '40001', '40P01', '57014', '08006', '08003']) {
      expect(isTransientDbError({ code })).toBe(true)
    }
  })

  it('treats deterministic / unknown failures as terminal', () => {
    // Unique violation — the upsert already handles idempotency, retrying is pointless.
    expect(isTransientDbError({ code: 'P2002' })).toBe(false)
    // Validation / schema drift.
    expect(isTransientDbError({ code: 'P2021' })).toBe(false)
    expect(isTransientDbError(new Error('boom'))).toBe(false)
    expect(isTransientDbError(null)).toBe(false)
    expect(isTransientDbError(undefined)).toBe(false)
    expect(isTransientDbError('P1001')).toBe(false)
    expect(isTransientDbError({ code: 123 })).toBe(false)
  })
})

describe('withDbRetry — bounded retries with backoff', () => {
  it('returns the result on first success without retrying', async () => {
    const op = vi.fn().mockResolvedValue('ok')
    await expect(withDbRetry(op, { baseDelayMs: 0 })).resolves.toBe('ok')
    expect(op).toHaveBeenCalledTimes(1)
  })

  it('retries transient failures up to the bound then succeeds', async () => {
    const op = vi
      .fn()
      .mockRejectedValueOnce({ code: 'P1001' })
      .mockRejectedValueOnce({ code: '40001' })
      .mockResolvedValue('recovered')
    await expect(withDbRetry(op, { retries: 2, baseDelayMs: 0 })).resolves.toBe('recovered')
    expect(op).toHaveBeenCalledTimes(3)
  })

  it('gives up after the retry bound and rethrows the last transient error', async () => {
    const op = vi.fn().mockRejectedValue({ code: 'P1001' })
    await expect(withDbRetry(op, { retries: 2, baseDelayMs: 0 })).rejects.toMatchObject({ code: 'P1001' })
    // 1 initial + 2 retries
    expect(op).toHaveBeenCalledTimes(3)
  })

  it('does not retry a terminal (non-transient) error', async () => {
    const op = vi.fn().mockRejectedValue({ code: 'P2002' })
    await expect(withDbRetry(op, { retries: 5, baseDelayMs: 0 })).rejects.toMatchObject({ code: 'P2002' })
    expect(op).toHaveBeenCalledTimes(1)
  })
})

describe('parseImportInstant — flexible timestamp parsing', () => {
  it('parses ISO strings, epoch numbers, and numeric strings', () => {
    expect(parseImportInstant('2026-06-01T10:00:00Z')?.toISOString()).toBe('2026-06-01T10:00:00.000Z')
    const ms = Date.UTC(2026, 5, 1, 10)
    expect(parseImportInstant(ms)?.getTime()).toBe(ms)
    expect(parseImportInstant(String(ms))?.getTime()).toBe(ms)
    const d = new Date('2026-06-01T10:00:00Z')
    expect(parseImportInstant(d)).toBe(d)
  })

  it('returns null for non-instants', () => {
    expect(parseImportInstant('not-a-date')).toBeNull()
    expect(parseImportInstant('')).toBeNull()
    expect(parseImportInstant(NaN)).toBeNull()
    expect(parseImportInstant(Infinity)).toBeNull()
    expect(parseImportInstant(null)).toBeNull()
    expect(parseImportInstant(undefined)).toBeNull()
    expect(parseImportInstant({})).toBeNull()
  })
})

describe('deriveHealthImportExternalId — stable, collision-resistant', () => {
  const base = {
    sourcePath: 'health_connect',
    metricType: 'steps',
    startAt: new Date('2026-06-01T00:00:00Z'),
    endAt: new Date('2026-06-02T00:00:00Z'),
    value: 1234 as number | null,
  }

  it('is deterministic for the same identifying tuple', () => {
    expect(deriveHealthImportExternalId(base)).toBe(deriveHealthImportExternalId({ ...base }))
  })

  it('differs when any identifying field changes', () => {
    const id = deriveHealthImportExternalId(base)
    expect(deriveHealthImportExternalId({ ...base, value: 1235 })).not.toBe(id)
    expect(deriveHealthImportExternalId({ ...base, metricType: 'distance' })).not.toBe(id)
    expect(deriveHealthImportExternalId({ ...base, sourcePath: 'file_upload' })).not.toBe(id)
    expect(deriveHealthImportExternalId({ ...base, value: null })).not.toBe(id)
  })
})

describe('buildHealthImportRecord — upsert shape + idempotency', () => {
  it('keys the upsert on the per-source unique index and derives a stable externalId', () => {
    const rec = buildHealthImportRecord('u1', {
      metricType: 'steps',
      value: 8000,
      unit: 'count',
      startAt: '2026-06-01T00:00:00Z',
      endAt: '2026-06-02T00:00:00Z',
      source: 'health_connect',
    })
    expect(rec).not.toBeNull()
    const key = rec!.where.userId_sourcePath_provider_metricType_externalId
    expect(key).toMatchObject({
      userId: 'u1',
      sourcePath: 'health_connect',
      provider: 'device',
      metricType: 'steps',
    })
    // Stable derived id → re-pushing the same sample upserts in place.
    expect(key.externalId).toBe(
      deriveHealthImportExternalId({
        sourcePath: 'health_connect',
        metricType: 'steps',
        startAt: new Date('2026-06-01T00:00:00Z'),
        endAt: new Date('2026-06-02T00:00:00Z'),
        value: 8000,
      }),
    )
    expect(rec!.create.value).toBe(8000)
    expect(rec!.create.unit).toBe('count')
  })

  it('honors a client-supplied externalId and maps huawei_health_kit provider', () => {
    const rec = buildHealthImportRecord('u1', {
      metricType: 'heart_rate',
      startAt: 1717200000000,
      endAt: 1717200000000,
      source: 'huawei_health_kit',
      externalId: 'hw-123',
    })
    expect(rec!.where.userId_sourcePath_provider_metricType_externalId).toMatchObject({
      sourcePath: 'huawei_health_kit',
      provider: 'huawei_health_kit',
      externalId: 'hw-123',
    })
    // endAt defaults to startAt; value defaults to null.
    expect(rec!.create.startAt.getTime()).toBe(rec!.create.endAt.getTime())
    expect(rec!.create.value).toBeNull()
  })

  it('returns null when the start instant is unparseable', () => {
    expect(
      buildHealthImportRecord('u1', {
        metricType: 'steps',
        startAt: 'garbage',
        endAt: '2026-06-02T00:00:00Z',
        source: 'health_connect',
      }),
    ).toBeNull()
  })
})

describe('POST /v1/integrations/me/health/import — on-device sink', () => {
  it('401 before any DB work when unauthenticated', async () => {
    unauthenticated()
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/integrations/me/health/import',
      payload: { items: [{ metricType: 'steps', startAt: 1, endAt: 2, source: 'health_connect' }] },
    })
    expect(res.statusCode).toBe(401)
    expect(userHealthImportUpsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('400 VALIDATION_ERROR on an empty batch', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/integrations/me/health/import',
      payload: { items: [] },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(userHealthImportUpsert).not.toHaveBeenCalled()
    await app.close()
  })

  it('upserts each valid sample (idempotent sink) and counts unparseable ones as skipped', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/integrations/me/health/import',
      payload: {
        items: [
          { metricType: 'steps', value: 8000, startAt: '2026-06-01T00:00:00Z', endAt: '2026-06-02T00:00:00Z', source: 'health_connect' },
          { metricType: 'sleep', startAt: 'bad', endAt: 'bad', source: 'health_connect' },
        ],
      },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ imported: 1, skipped: 1, failed: 0 })
    expect(userHealthImportUpsert).toHaveBeenCalledTimes(1)
    // Scoped to the authenticated user.
    const arg = userHealthImportUpsert.mock.calls[0][0] as {
      where: { userId_sourcePath_provider_metricType_externalId: { userId: string } }
    }
    expect(arg.where.userId_sourcePath_provider_metricType_externalId.userId).toBe('u1')
    await app.close()
  })

  it('isolates a failing record so the rest of the batch still imports', async () => {
    userHealthImportUpsert
      .mockRejectedValueOnce({ code: 'P2003' })
      .mockResolvedValueOnce({})
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/integrations/me/health/import',
      payload: {
        items: [
          { metricType: 'steps', startAt: '2026-06-01T00:00:00Z', endAt: '2026-06-02T00:00:00Z', source: 'health_connect' },
          { metricType: 'distance', startAt: '2026-06-01T00:00:00Z', endAt: '2026-06-02T00:00:00Z', source: 'health_connect' },
        ],
      },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ imported: 1, failed: 1 })
    await app.close()
  })
})

describe('DELETE /v1/integrations/:provider — unlink data-deletion contract', () => {
  it('404 UNKNOWN_PROVIDER for a bad provider', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/integrations/myspace' })
    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'UNKNOWN_PROVIDER' })
    await app.close()
  })

  it('deletes imported data and scrubs the connection on unlink', async () => {
    wearableConnectionFindMany.mockResolvedValue([{ id: 'c1', externalUserId: 'terra-1' }])
    userHealthImportDeleteMany.mockResolvedValue({ count: 7 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/integrations/garmin' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ unlinked: true, provider: 'garmin', deletedImports: 7 })
    // Imported data for this provider is deleted, scoped to the user.
    const delArg = userHealthImportDeleteMany.mock.calls[0][0] as {
      where: { userId: string; provider: { in: string[] } }
    }
    expect(delArg.where.userId).toBe('u1')
    expect(delArg.where.provider.in).toContain('garmin')
    // Connection row scrubbed + marked revoked.
    const updArg = wearableConnectionUpdateMany.mock.calls[0][0] as {
      data: { externalUserId: null; status: string }
    }
    expect(updArg.data).toMatchObject({ externalUserId: null, status: 'revoked' })
    await app.close()
  })

  it('also clears huawei_health_kit imports when unlinking huawei', async () => {
    wearableConnectionFindMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/integrations/huawei' })
    expect(res.statusCode).toBe(200)
    const delArg = userHealthImportDeleteMany.mock.calls[0][0] as {
      where: { provider: { in: string[] } }
    }
    expect(delArg.where.provider.in).toEqual(expect.arrayContaining(['huawei', 'huawei_health_kit']))
    await app.close()
  })

  it('still deletes local data when the connection lookup fails (best-effort)', async () => {
    wearableConnectionFindMany.mockRejectedValue(new Error('relation does not exist'))
    userHealthImportDeleteMany.mockResolvedValue({ count: 3 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/integrations/fitbit' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ unlinked: true, deletedImports: 3 })
    await app.close()
  })
})
