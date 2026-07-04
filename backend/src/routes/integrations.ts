import type { FastifyBaseLogger, FastifyInstance } from 'fastify'
import crypto from 'node:crypto'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import {
  dedupeHealthSamples,
  type HealthSampleCandidate,
} from '../lib/health-dedup'
import { authenticate } from '../middleware/auth'
import { processInboxItem } from '../services/webhook-inbox.service'

const WearableProviderSchema = z.enum([
  'garmin',
  'fitbit',
  'oura',
  'polar',
  'coros',
  'whoop',
  'suunto',
  'withings',
  'amazfit',
  'huawei',
  'wahoo',
])

const providerMetadata: Record<z.infer<typeof WearableProviderSchema>, {
  label: string
  preferredPath: 'health_connect' | 'aggregator' | 'huawei_health_kit'
}> = {
  garmin: { label: 'Garmin Connect', preferredPath: 'aggregator' },
  fitbit: { label: 'Fitbit', preferredPath: 'aggregator' },
  oura: { label: 'Oura', preferredPath: 'aggregator' },
  polar: { label: 'Polar Flow', preferredPath: 'aggregator' },
  coros: { label: 'COROS', preferredPath: 'aggregator' },
  whoop: { label: 'WHOOP', preferredPath: 'aggregator' },
  suunto: { label: 'Suunto', preferredPath: 'aggregator' },
  withings: { label: 'Withings', preferredPath: 'aggregator' },
  amazfit: { label: 'Amazfit / Zepp', preferredPath: 'aggregator' },
  huawei: { label: 'Huawei Health', preferredPath: 'aggregator' },
  wahoo: { label: 'Wahoo ELEMNT', preferredPath: 'aggregator' },
}

const terraResourceByProvider: Record<z.infer<typeof WearableProviderSchema>, string> = {
  garmin: 'GARMIN',
  fitbit: 'FITBIT',
  oura: 'OURA',
  polar: 'POLAR',
  coros: 'COROS',
  whoop: 'WHOOP',
  suunto: 'SUUNTO',
  withings: 'WITHINGS',
  // Amazfit devices sync through Zepp in Terra.
  amazfit: 'ZEPP',
  huawei: 'HUAWEI',
  wahoo: 'WAHOO',
}

function selectedAggregator() {
  return (process.env.WEARABLE_AGGREGATOR_PROVIDER ?? 'terra').toLowerCase()
}

function terraConfigured() {
  return Boolean(process.env.TERRA_DEV_ID && process.env.TERRA_API_KEY)
}

function aggregatorConfigured() {
  return selectedAggregator() === 'terra' && terraConfigured()
}

function terraApiBase() {
  return process.env.TERRA_API_BASE_URL ?? 'https://api.tryterra.co/v2'
}

async function createTerraAuthUrl({
  provider,
  userId,
}: {
  provider: z.infer<typeof WearableProviderSchema>
  userId: string
}) {
  const resource = terraResourceByProvider[provider]
  const endpoint = new URL(`${terraApiBase()}/auth/authenticateUser`)
  endpoint.searchParams.set('resource', resource)

  const body: Record<string, string> = {
    language: 'en',
    reference_id: userId,
    resource,
  }
  if (process.env.TERRA_AUTH_SUCCESS_REDIRECT_URL) {
    body.auth_success_redirect_url = process.env.TERRA_AUTH_SUCCESS_REDIRECT_URL
  }
  if (process.env.TERRA_AUTH_FAILURE_REDIRECT_URL) {
    body.auth_failure_redirect_url = process.env.TERRA_AUTH_FAILURE_REDIRECT_URL
  }

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'dev-id': process.env.TERRA_DEV_ID!,
      'x-api-key': process.env.TERRA_API_KEY!,
    },
    body: JSON.stringify(body),
  })
  const payload = (await res.json().catch(() => ({}))) as Record<string, unknown>
  if (!res.ok) {
    throw new Error(
      typeof payload.message === 'string'
        ? payload.message
        : `Terra auth failed (${res.status})`,
    )
  }

  const url = payload.auth_url ?? payload.url
  if (typeof url !== 'string' || url.length === 0) {
    throw new Error('Terra did not return an auth URL')
  }
  return {
    url,
    terraUserId: typeof payload.user_id === 'string' ? payload.user_id : null,
  }
}

function terraProviderToZvelt(provider: unknown) {
  const normalized = String(provider ?? '').toLowerCase()
  if (normalized === 'zepp') return 'amazfit'
  if (normalized === 'huawei') return 'huawei'
  if (normalized in providerMetadata) return normalized
  return normalized || 'unknown'
}

/** Replay-window tolerance for a signed Terra webhook timestamp (±5 minutes). */
const TERRA_SIGNATURE_TOLERANCE_MS = 5 * 60 * 1000

function verifyTerraSignature({
  signatureHeader,
  rawBody,
  secret,
}: {
  signatureHeader: unknown
  rawBody: unknown
  secret: string
}) {
  if (typeof signatureHeader !== 'string' || typeof rawBody !== 'string') {
    return false
  }
  const parts = Object.fromEntries(
    signatureHeader.split(',').map((part) => {
      const [key, ...rest] = part.split('=')
      return [key, rest.join('=')]
    }),
  )
  const timestamp = parts.t
  const signature = parts.v1
  if (!timestamp || !signature) return false

  // Replay guard: reject a signed request whose timestamp is outside a ±5-minute
  // window. Terra sends `t` as Unix seconds; tolerate a millisecond value too
  // (>= 1e12) so either format is handled.
  const tNum = Number(timestamp)
  if (!Number.isFinite(tNum)) return false
  const tMs = tNum >= 1e12 ? tNum : tNum * 1000
  if (Math.abs(Date.now() - tMs) > TERRA_SIGNATURE_TOLERANCE_MS) return false

  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex')
  const a = Buffer.from(signature, 'hex')
  const b = Buffer.from(expected, 'hex')
  return a.length === b.length && crypto.timingSafeEqual(a, b)
}

function parseTerraTime(value: unknown, fallback: Date) {
  if (typeof value !== 'string' || value.length === 0) return fallback
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? fallback : parsed
}

/**
 * Parse a flexible client-supplied timestamp (ISO string OR epoch millis as a
 * number/numeric string) into a Date, or null when it isn't a real instant.
 * Pure — used both by the on-device health-import endpoint and its tests.
 */
export function parseImportInstant(value: unknown): Date | null {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) return null
    const d = new Date(value)
    return Number.isNaN(d.getTime()) ? null : d
  }
  if (typeof value === 'string' && value.length > 0) {
    // All-digit strings are treated as epoch millis; everything else as ISO.
    const asEpoch = /^-?\d+$/.test(value) ? new Date(Number(value)) : new Date(value)
    return Number.isNaN(asEpoch.getTime()) ? null : asEpoch
  }
  return null
}

/** Schema for one on-device health sample pushed to the import endpoint. */
const HealthImportItemSchema = z.object({
  metricType: z.string().min(1).max(48),
  value: z.number().finite().nullable().optional(),
  unit: z.string().min(1).max(32).nullable().optional(),
  startAt: z.union([z.string().min(1), z.number()]),
  endAt: z.union([z.string().min(1), z.number()]),
  source: z.enum(['health_connect', 'huawei_health_kit', 'file_upload']),
  externalId: z.string().min(1).max(240).optional(),
  sourceApp: z.string().min(1).max(120).nullable().optional(),
  sourceDevice: z.string().min(1).max(120).nullable().optional(),
})

const HealthImportBatchSchema = z.object({
  items: z.array(HealthImportItemSchema).min(1).max(500),
})

export type HealthImportItem = z.infer<typeof HealthImportItemSchema>

/**
 * Normalize one validated on-device health sample into the exact upsert shape
 * `UserHealthImport` expects, reusing the per-source unique index
 * (userId, sourcePath, provider, metricType, externalId) for idempotency.
 *
 * Pure: no Prisma, no clock except the supplied `now` fallback. Returns null
 * when the sample carries no usable time window (so the caller can skip it
 * without aborting the rest of the batch). When the client omits `externalId`
 * we derive a stable one from the sample's identifying fields so re-pushing the
 * same sample upserts in place instead of inserting a duplicate.
 */
export function buildHealthImportRecord(
  userId: string,
  item: HealthImportItem,
): {
  where: {
    userId_sourcePath_provider_metricType_externalId: {
      userId: string
      sourcePath: string
      provider: string
      metricType: string
      externalId: string
    }
  }
  update: {
    startAt: Date
    endAt: Date
    value: number | null
    unit: string | null
    sourceApp: string | null
    sourceDevice: string | null
  }
  create: {
    userId: string
    metricType: string
    sourcePath: string
    provider: string
    sourceApp: string | null
    sourceDevice: string | null
    externalId: string
    startAt: Date
    endAt: Date
    value: number | null
    unit: string | null
    payload: Record<string, never>
  }
} | null {
  const startAt = parseImportInstant(item.startAt)
  if (!startAt) return null
  const endAt = parseImportInstant(item.endAt) ?? startAt

  const sourcePath = item.source
  // On-device pushes carry their own platform label as the provider; the row's
  // sourcePath already records the pipe (health_connect / huawei_health_kit).
  const provider = sourcePath === 'huawei_health_kit' ? 'huawei_health_kit' : 'device'
  const value = item.value == null ? null : item.value
  const unit = item.unit ?? null
  const sourceApp = item.sourceApp ?? null
  const sourceDevice = item.sourceDevice ?? null

  const externalId = (
    item.externalId ??
    deriveHealthImportExternalId({
      sourcePath,
      metricType: item.metricType,
      startAt,
      endAt,
      value,
    })
  ).slice(0, 240)

  return {
    where: {
      userId_sourcePath_provider_metricType_externalId: {
        userId,
        sourcePath,
        provider,
        metricType: item.metricType,
        externalId,
      },
    },
    update: { startAt, endAt, value, unit, sourceApp, sourceDevice },
    create: {
      userId,
      metricType: item.metricType,
      sourcePath,
      provider,
      sourceApp,
      sourceDevice,
      externalId,
      startAt,
      endAt,
      value,
      unit,
      payload: {},
    },
  }
}

/**
 * Deterministic externalId for an on-device sample with no client-supplied id.
 * Hashes the identifying tuple (source, metric, window, value) so the SAME
 * sample re-pushed by the device collapses onto the same row via the unique
 * index, while genuinely distinct samples stay separate.
 */
export function deriveHealthImportExternalId(input: {
  sourcePath: string
  metricType: string
  startAt: Date
  endAt: Date
  value: number | null
}): string {
  const hash = crypto
    .createHash('sha256')
    .update(
      [
        input.sourcePath,
        input.metricType,
        input.startAt.getTime(),
        input.endAt.getTime(),
        input.value == null ? '' : input.value,
      ].join('|'),
    )
    .digest('hex')
  return `device:${input.sourcePath}:${input.metricType}:${hash}`
}

/**
 * Best-effort scalar for cross-source dedup. We only need a representative
 * magnitude for the sample (steps walked, kcal burned, distance) so the dedup
 * layer can tell "the same run reported twice" from "two different runs in
 * adjacent windows". Returns null when the payload carries no obvious scalar —
 * dedup then falls back to a time-only match for that record.
 */
function terraSampleValue(item: any): number | null {
  const metadata = item?.metadata ?? {}
  const candidates = [
    item?.distance_data?.summary?.distance_meters,
    item?.distance_data?.summary?.steps,
    item?.calories_data?.total_burned_calories,
    item?.calories_data?.net_activity_calories,
    item?.steps,
    item?.value,
    metadata.value,
  ]
  for (const c of candidates) {
    const n = typeof c === 'string' ? Number(c) : c
    if (typeof n === 'number' && Number.isFinite(n)) return n
  }
  return null
}

function terraImportExternalId({
  terraUserId,
  type,
  item,
}: {
  terraUserId: string
  type: string
  item: any
}) {
  const metadata = item?.metadata ?? {}
  const candidate =
    metadata.upload_id ??
    metadata.summary_id ??
    metadata.id ??
    item?.id ??
    item?.summary_id ??
    item?.metadata?.start_time ??
    item?.start_time ??
    item?.date
  if (candidate) return `terra:${terraUserId}:${type}:${String(candidate)}`.slice(0, 240)
  const hash = crypto
    .createHash('sha256')
    .update(JSON.stringify(item ?? {}))
    .digest('hex')
  return `terra:${terraUserId}:${type}:${hash}`.slice(0, 240)
}

/**
 * Postgres / Prisma transient error codes worth a quick in-handler retry.
 * P1001/P1002 = can't reach DB; P1008 = operation timeout; P2024 = pool
 * timeout; 40001 = serialization failure; 40P01 = deadlock. Everything else
 * (validation, unique violations the upsert already handles, schema drift) is
 * treated as terminal so we don't burn retries on a deterministic failure.
 */
const TRANSIENT_DB_CODES = new Set([
  'P1001',
  'P1002',
  'P1008',
  'P1017',
  'P2024',
  '40001',
  '40P01',
  '57014',
  '08006',
  '08003',
])

export function isTransientDbError(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false
  const code = (err as { code?: unknown }).code
  return typeof code === 'string' && TRANSIENT_DB_CODES.has(code)
}

/**
 * Run `op` with bounded retries on transient DB errors only. Non-transient
 * errors throw immediately. Backoff is small and synchronous-friendly so the
 * webhook handler stays well under the provider's timeout budget.
 */
export async function withDbRetry<T>(
  op: () => Promise<T>,
  opts: { retries?: number; baseDelayMs?: number } = {},
): Promise<T> {
  const retries = opts.retries ?? 2
  const baseDelayMs = opts.baseDelayMs ?? 50
  let attempt = 0
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      return await op()
    } catch (err) {
      if (attempt >= retries || !isTransientDbError(err)) throw err
      const delay = baseDelayMs * 2 ** attempt
      attempt++
      await new Promise((resolve) => setTimeout(resolve, delay))
    }
  }
}

/**
 * Best-effort remote deauthorization of a single Terra-aggregated connection.
 * Calls Terra's user-deauth endpoint so the provider stops streaming data and
 * the external grant is revoked on their side. Returns true on a confirmed
 * remote revoke, false otherwise (missing creds / no external id / provider
 * error). NEVER throws — the caller treats every connection independently.
 */
async function revokeTerraConnection(
  externalUserId: string | null | undefined,
  log: FastifyBaseLogger,
): Promise<boolean> {
  if (!terraConfigured()) return false
  if (!externalUserId) return false
  try {
    const endpoint = new URL(`${terraApiBase()}/auth/deauthenticateUser`)
    endpoint.searchParams.set('user_id', externalUserId)
    const res = await fetch(endpoint, {
      method: 'DELETE',
      headers: {
        'dev-id': process.env.TERRA_DEV_ID!,
        'x-api-key': process.env.TERRA_API_KEY!,
      },
    })
    if (!res.ok) {
      // 404 = Terra already forgot this user (treat as effectively revoked);
      // anything else is a soft failure we just log and move on from.
      log.warn(
        { status: res.status, externalUserId },
        'integrations: Terra deauth returned non-OK status',
      )
      return res.status === 404
    }
    return true
  } catch (err) {
    log.warn({ err, externalUserId }, 'integrations: Terra deauth call failed')
    return false
  }
}

/**
 * Best-effort teardown of ALL external wearable connections for a user, used by
 * GDPR erasure. For each stored connection we (1) attempt the provider-side
 * deauth/unlink so data stops flowing and the remote grant is revoked, then
 * (2) clear locally-stored tokens / external identifiers / metadata so nothing
 * sensitive survives even momentarily before the cascade delete.
 *
 * The `wearable_connections` rows themselves are removed by the FK cascade when
 * the user row is deleted — this helper exists for the REMOTE revoke + token
 * scrub, which a DB cascade cannot do. It is tolerant of every failure mode
 * (no creds, provider down, DB unavailable): it logs and never throws, so a
 * stuck provider can never block the user's right to erasure.
 */
export async function revokeAllProviderConnections(
  userId: string,
  log: FastifyBaseLogger,
): Promise<{ total: number; revoked: number }> {
  let connections: Array<{
    id: string
    provider: string
    sourcePath: string
    externalUserId: string | null
  }> = []
  try {
    connections = await prisma.wearableConnection.findMany({
      where: { userId },
      select: { id: true, provider: true, sourcePath: true, externalUserId: true },
    })
  } catch (err) {
    // DB unreachable / table missing locally: nothing we can do remotely, and
    // erasure must still proceed. Report zero and bail.
    log.warn({ err, userId }, 'integrations: could not load connections for revoke')
    return { total: 0, revoked: 0 }
  }

  let revoked = 0
  for (const conn of connections) {
    // Only the Terra aggregator path has a remote grant to revoke today; other
    // sourcePaths (health_connect / huawei_health_kit) are device-local and
    // have nothing to deauth remotely — we still scrub their stored metadata.
    let remoteOk = false
    if (conn.sourcePath === 'aggregator' && selectedAggregator() === 'terra') {
      remoteOk = await revokeTerraConnection(conn.externalUserId, log)
    }
    if (remoteOk) revoked++

    // Scrub stored tokens / external ids / metadata regardless of remote result.
    // The row is about to be cascade-deleted, but clearing first guarantees no
    // credential lingers if the cascade is delayed or the delete later fails.
    try {
      await prisma.wearableConnection.update({
        where: { id: conn.id },
        data: {
          externalUserId: null,
          scopes: [],
          metadata: {},
          status: 'revoked',
        },
      })
    } catch (err) {
      log.warn(
        { err, connectionId: conn.id, provider: conn.provider },
        'integrations: could not scrub connection tokens before erasure',
      )
    }
  }

  return { total: connections.length, revoked }
}

export async function persistTerraDataPayload(body: any, log: FastifyBaseLogger) {
  const userId = body?.user?.reference_id
  if (!userId || body?.type === 'auth') return 0

  const terraUserId = String(body?.user?.user_id ?? 'unknown')
  const provider = terraProviderToZvelt(body?.user?.provider)
  const metricType = String(body?.type ?? 'unknown')
  const rows = Array.isArray(body?.data) ? body.data : [body]
  const now = new Date()
  let imported = 0
  let failed = 0
  let suppressed = 0

  // Parse every record up front so we can (a) compute the batch time span and
  // (b) hand the whole set to the cross-source dedup along with what's already
  // stored from OTHER sources.
  type ParsedRecord = {
    item: any
    metadata: any
    startAt: Date
    endAt: Date
    value: number | null
    externalId: string
  }
  const parsed: ParsedRecord[] = rows.map((item: any): ParsedRecord => {
    const metadata = item?.metadata ?? {}
    const startAt = parseTerraTime(
      metadata.start_time ?? item?.start_time ?? item?.date,
      now,
    )
    const endAt = parseTerraTime(
      metadata.end_time ?? item?.end_time ?? item?.date,
      startAt,
    )
    return {
      item,
      metadata,
      startAt,
      endAt,
      value: terraSampleValue(item),
      externalId: terraImportExternalId({ terraUserId, type: metricType, item }),
    }
  })

  // Cross-source dedup: the per-source unique index already collapses re-delivered
  // aggregator webhooks, but it can't see the SAME run/day that already arrived
  // via a device-native path (Health Connect / Huawei) or a manual file upload.
  // Load existing same-metric imports from *other* sources overlapping this
  // batch's window, run the pure dedup, and skip any incoming aggregator record
  // that a higher-priority existing sample already represents (so it isn't
  // double-counted downstream). Best-effort: if the lookup fails we simply
  // import everything, preserving the prior behavior.
  let suppress = new Set<string>()
  if (parsed.length > 0) {
    try {
      const batchStart = new Date(
        Math.min(...parsed.map((p) => p.startAt.getTime())),
      )
      const batchEnd = new Date(Math.max(...parsed.map((p) => p.endAt.getTime())))
      const existing = await withDbRetry(() =>
        prisma.userHealthImport.findMany({
          where: {
            userId,
            metricType,
            sourcePath: { not: 'aggregator' },
            startAt: { lte: batchEnd },
            endAt: { gte: batchStart },
          },
          select: {
            id: true,
            sourcePath: true,
            provider: true,
            startAt: true,
            endAt: true,
            value: true,
          },
        }),
      )

      if (existing.length > 0) {
        const incomingCandidates: HealthSampleCandidate[] = parsed.map((p) => ({
          key: `incoming:${p.externalId}`,
          metricType,
          sourcePath: 'aggregator',
          provider,
          startAt: p.startAt,
          endAt: p.endAt,
          value: p.value,
        }))
        const existingCandidates: HealthSampleCandidate[] = existing.map((e) => ({
          key: `existing:${e.id}`,
          metricType,
          sourcePath: e.sourcePath,
          provider: e.provider,
          startAt: e.startAt,
          endAt: e.endAt,
          value: e.value == null ? null : Number(e.value),
        }))

        const { dropped } = dedupeHealthSamples([
          ...existingCandidates,
          ...incomingCandidates,
        ])
        // Only incoming records can be skipped here; existing rows stay put.
        suppress = new Set(
          dropped
            .filter((d) => d.key.startsWith('incoming:'))
            .map((d) => d.key.slice('incoming:'.length)),
        )
      }
    } catch (err) {
      log.warn(
        { err, provider, metricType, userId },
        'wearable webhook: cross-source dedup lookup failed, importing all',
      )
      suppress = new Set()
    }
  }

  for (const p of parsed) {
    const { item, metadata, startAt, endAt, externalId, value } = p
    if (suppress.has(externalId)) {
      // A higher-priority native/upload sample already covers this window; skip
      // so the same activity/metric isn't counted from two sources.
      suppressed++
      continue
    }
    // Per-record isolation: a single bad/duplicate record must never abort the
    // rest of the batch. Idempotency comes from the existing unique index
    // (userId, sourcePath, provider, metricType, externalId) — re-delivered
    // webhooks upsert instead of inserting duplicates.
    try {
      await withDbRetry(() =>
        prisma.userHealthImport.upsert({
          where: {
            userId_sourcePath_provider_metricType_externalId: {
              userId,
              sourcePath: 'aggregator',
              provider,
              metricType,
              externalId,
            },
          },
          update: {
            startAt,
            endAt,
            value,
            payload: item ?? {},
          },
          create: {
            userId,
            metricType,
            sourcePath: 'aggregator',
            provider,
            sourceApp: 'terra',
            sourceDevice: typeof metadata.device_name === 'string' ? metadata.device_name : null,
            externalId,
            startAt,
            endAt,
            value,
            payload: item ?? {},
          },
        }),
      )
      imported++
    } catch (err) {
      failed++
      log.error(
        {
          err,
          provider,
          metricType,
          externalId,
          terraUserId,
          userId,
        },
        'wearable webhook: health import upsert failed',
      )
    }
  }

  if (failed > 0 || suppressed > 0) {
    log.warn(
      { provider, metricType, userId, imported, failed, suppressed, total: rows.length },
      'wearable webhook: batch completed with record failures or dedup',
    )
  }

  try {
    await withDbRetry(() =>
      prisma.wearableConnection.updateMany({
        where: { userId, provider, sourcePath: 'aggregator' },
        data: { lastSyncAt: now, status: 'synced' },
      }),
    )
  } catch (err) {
    log.error(
      { err, provider, userId },
      'wearable webhook: connection lastSync update failed',
    )
  }
  return imported
}

export async function integrationsRoutes(app: FastifyInstance) {
  app.get('/', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const configured = aggregatorConfigured()
    const providers = Object.entries(providerMetadata).map(([provider, meta]) => ({
      provider,
      label: meta.label,
      preferredPath: meta.preferredPath,
      configured,
    }))

    let integrations: Array<{ provider: string; updatedAt: string; status: string }> = []
    try {
      const rows = await prisma.wearableConnection.findMany({
        where: { userId },
        orderBy: { updatedAt: 'desc' },
      })
      integrations = rows.map((row) => ({
        provider: row.provider,
        updatedAt: row.updatedAt.toISOString(),
        status: row.status,
      }))
    } catch {
      // Local/dev DB may not have the new migration applied yet.
      integrations = []
    }

    return reply.send({
      integrations,
      providers,
      aggregator: {
        configured,
        provider: selectedAggregator(),
      },
    })
  })

  app.get('/strava/status', { preHandler: authenticate }, async (_request, reply) => {
    return reply.send({ connected: false })
  })

  app.post('/strava/exchange', { preHandler: authenticate }, async (_request, reply) => {
    return reply.code(501).send({
      error: 'INTEGRATION_NOT_CONFIGURED',
      message: 'Strava OAuth is not configured on this backend yet.',
    })
  })

  app.delete('/strava', { preHandler: authenticate }, async (_request, reply) => {
    return reply.code(204).send()
  })

  app.get<{ Params: { provider: string } }>('/:provider/auth-url', { preHandler: authenticate }, async (request, reply) => {
    const parsed = WearableProviderSchema.safeParse(request.params.provider)
    if (!parsed.success) {
      return reply.code(404).send({
        error: 'UNKNOWN_PROVIDER',
        message: 'Unsupported wearable provider.',
      })
    }

    if (!aggregatorConfigured()) {
      return reply.code(501).send({
        error: 'AGGREGATOR_NOT_CONFIGURED',
        message: 'Wearable cloud linking needs Terra credentials.',
        provider: parsed.data,
        requiredEnv: ['TERRA_DEV_ID', 'TERRA_API_KEY'],
      })
    }

    const { userId } = request.user
    try {
      const auth = await createTerraAuthUrl({ provider: parsed.data, userId })
      await prisma.wearableConnection.upsert({
        where: {
          userId_provider_sourcePath: {
            userId,
            provider: parsed.data,
            sourcePath: 'aggregator',
          },
        },
        update: {
          status: 'link_started',
          externalUserId: auth.terraUserId,
          metadata: { aggregator: 'terra', terraResource: terraResourceByProvider[parsed.data] },
        },
        create: {
          userId,
          provider: parsed.data,
          sourcePath: 'aggregator',
          externalUserId: auth.terraUserId,
          status: 'link_started',
          metadata: { aggregator: 'terra', terraResource: terraResourceByProvider[parsed.data] },
        },
      }).catch(() => {})

      return reply.send({
        url: auth.url,
        provider: parsed.data,
        aggregator: 'terra',
      })
    } catch (err: any) {
      return reply.code(502).send({
        error: 'AGGREGATOR_AUTH_FAILED',
        message: err?.message ?? 'Could not create Terra auth URL.',
        provider: parsed.data,
      })
    }
  })

  app.post<{ Params: { provider: string } }>('/:provider/sync', { preHandler: authenticate }, async (request, reply) => {
    const parsed = WearableProviderSchema.safeParse(request.params.provider)
    if (!parsed.success) {
      return reply.code(404).send({
        error: 'UNKNOWN_PROVIDER',
        message: 'Unsupported wearable provider.',
      })
    }

    if (!aggregatorConfigured()) {
      return reply.code(501).send({
        error: 'AGGREGATOR_NOT_CONFIGURED',
        message: 'Wearable sync needs Terra credentials.',
        imported: 0,
      })
    }

    return reply.send({
      imported: 0,
      status: 'webhook_driven',
      provider: parsed.data,
      message: 'Terra sends new and historical data through webhooks after the user connects.',
    })
  })

  // Unlink a provider AND honor the data-deletion contract: revoke the remote
  // grant (so data stops flowing) and delete the imported samples for that
  // provider's source, so unlinking truly removes the provider's data rather
  // than just hiding the connection. Best-effort + tolerant: a stuck provider
  // must never block the local data deletion.
  app.delete<{ Params: { provider: string } }>('/:provider', { preHandler: authenticate }, async (request, reply) => {
    const parsed = WearableProviderSchema.safeParse(request.params.provider)
    if (!parsed.success) {
      return reply.code(404).send({
        error: 'UNKNOWN_PROVIDER',
        message: 'Unsupported wearable provider.',
      })
    }
    const provider = parsed.data
    const { userId } = request.user

    // 1) Remote revoke for the aggregator-linked connection(s), if any.
    let revokedRemotely = false
    let connections: Array<{ id: string; externalUserId: string | null }> = []
    try {
      connections = await prisma.wearableConnection.findMany({
        where: { userId, provider, sourcePath: 'aggregator' },
        select: { id: true, externalUserId: true },
      })
    } catch (err) {
      request.log.warn({ err, provider, userId }, 'integrations: could not load connection for unlink')
    }
    if (selectedAggregator() === 'terra') {
      for (const conn of connections) {
        if (await revokeTerraConnection(conn.externalUserId, request.log)) {
          revokedRemotely = true
        }
      }
    }

    // 2) Delete the imported data for this provider. Aggregator imports are
    // stored under provider=<zvelt provider>; on-device huawei pushes under the
    // huawei_health_kit provider. Remove both so the contract is fully honored.
    let deletedImports = 0
    try {
      const importProviders =
        provider === 'huawei' ? [provider, 'huawei_health_kit'] : [provider]
      const res = await prisma.userHealthImport.deleteMany({
        where: { userId, provider: { in: importProviders } },
      })
      deletedImports = res.count
    } catch (err) {
      request.log.warn({ err, provider, userId }, 'integrations: could not delete imported data on unlink')
    }

    // 3) Scrub + mark the connection row(s) so no external id/token lingers and
    // the unlink is observable. Removing the row entirely would also be valid,
    // but keeping a `revoked` marker preserves an auditable trail.
    try {
      await prisma.wearableConnection.updateMany({
        where: { userId, provider, sourcePath: 'aggregator' },
        data: { externalUserId: null, scopes: [], metadata: {}, status: 'revoked', lastSyncAt: new Date() },
      })
    } catch (err) {
      request.log.warn({ err, provider, userId }, 'integrations: could not scrub connection on unlink')
    }

    return reply.send({ unlinked: true, provider, revokedRemotely, deletedImports })
  })

  // POST /v1/integrations/me/health/import — sink for on-device Health Connect /
  // HealthKit pushes. Accepts a batch of samples and upserts each into
  // user_health_imports, reusing the per-source unique index for idempotency:
  // re-pushing the same batch upserts in place rather than inserting duplicates.
  app.post('/me/health/import', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = HealthImportBatchSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    let imported = 0
    let skipped = 0
    let failed = 0
    for (const item of parsed.data.items) {
      const record = buildHealthImportRecord(userId, item)
      if (!record) {
        // No usable time window — skip this record, keep processing the batch.
        skipped++
        continue
      }
      try {
        await withDbRetry(() => prisma.userHealthImport.upsert(record))
        imported++
      } catch (err) {
        failed++
        request.log.error(
          { err, userId, metricType: item.metricType, source: item.source },
          'health import: upsert failed',
        )
      }
    }

    return reply.code(201).send({ imported, skipped, failed })
  })

  app.post('/aggregator/webhook', { config: { rawBody: true } }, async (request, reply) => {
    const terraSecret = process.env.TERRA_WEBHOOK_SECRET
    if (terraSecret) {
      const valid = verifyTerraSignature({
        signatureHeader: request.headers['terra-signature'],
        rawBody: request.rawBody,
        secret: terraSecret,
      })
      if (!valid) {
        return reply.code(401).send({
          error: 'UNAUTHORIZED',
          message: 'Invalid Terra webhook signature.',
        })
      }
    } else if (process.env.WEARABLE_AGGREGATOR_WEBHOOK_SECRET) {
      const headerSecret = request.headers['x-zvelt-webhook-secret']
      if (headerSecret !== process.env.WEARABLE_AGGREGATOR_WEBHOOK_SECRET) {
        return reply.code(401).send({
          error: 'UNAUTHORIZED',
          message: 'Invalid wearable webhook secret.',
        })
      }
    } else {
      // Fail closed: with NO webhook secret configured we cannot authenticate
      // the caller. Accepting the body would let anyone import health data or
      // flip wearableConnection.status for arbitrary reference_id users.
      return reply.code(401).send({
        error: 'UNAUTHORIZED',
        message: 'Webhook authentication is not configured.',
      })
    }

    const body = (request.body ?? {}) as any
    let imported = 0
    let inboxId: string | null = null
    // Process defensively: any unexpected failure is logged and swallowed so we
    // still ack the provider with a fast 200 (re-delivery would just re-fail
    // here).
    try {
      if (body?.type === 'auth' && body?.user?.reference_id) {
        const userId = String(body.user.reference_id)
        const provider = terraProviderToZvelt(body.user.provider)
        const status = body.status === 'success' ? 'synced' : 'error'
        try {
          await withDbRetry(() =>
            prisma.wearableConnection.upsert({
              where: {
                userId_provider_sourcePath: {
                  userId,
                  provider,
                  sourcePath: 'aggregator',
                },
              },
              update: {
                externalUserId: String(body.user.user_id ?? ''),
                status,
                scopes: typeof body.user.scopes === 'string' ? body.user.scopes.split(',') : [],
                connectedAt: status === 'synced' ? new Date() : undefined,
                lastSyncAt: new Date(),
                metadata: { aggregator: 'terra', rawStatus: body.status, message: body.message ?? null },
              },
              create: {
                userId,
                provider,
                sourcePath: 'aggregator',
                externalUserId: String(body.user.user_id ?? ''),
                status,
                scopes: typeof body.user.scopes === 'string' ? body.user.scopes.split(',') : [],
                connectedAt: status === 'synced' ? new Date() : undefined,
                lastSyncAt: new Date(),
                metadata: { aggregator: 'terra', rawStatus: body.status, message: body.message ?? null },
              },
            }),
          )
        } catch (err) {
          app.log.error(
            { err, provider, userId, terraUserId: body?.user?.user_id ?? null },
            'wearable webhook: auth-event connection upsert failed',
          )
        }
      } else {
        // Durable inbox: persist the verified raw envelope FIRST so the data is
        // safe even if the import below fails — then ack the provider fast and
        // let the (fire-and-forget) inbox processor do the heavy lifting. Anything
        // not processed inline is drained later by processPending() (cron/worker).
        try {
          const row = await withDbRetry(() =>
            prisma.webhookInbox.create({
              data: {
                provider: terraProviderToZvelt(body?.user?.provider),
                sourcePath: 'aggregator',
                eventType: typeof body?.type === 'string' ? body.type.slice(0, 64) : null,
                externalId:
                  typeof body?.user?.user_id === 'string'
                    ? body.user.user_id.slice(0, 240)
                    : null,
                payload: body ?? {},
                status: 'received',
              },
              select: { id: true },
            }),
          )
          inboxId = row.id
        } catch (err) {
          // Couldn't durably store the envelope. Fall back to inline processing
          // so we don't silently drop the payload, then still ack 200.
          app.log.error(
            { err, type: body?.type ?? null },
            'wearable webhook: inbox persist failed, processing inline',
          )
          imported = await persistTerraDataPayload(body, app.log)
        }
      }
    } catch (err) {
      app.log.error(
        { err, provider: terraProviderToZvelt(body?.user?.provider), type: body?.type ?? null },
        'wearable webhook: unhandled processing error',
      )
    }

    // Fire-and-forget inline processing of the stored envelope. Never block the
    // ack on it: if it fails the row stays in the inbox for retry via cron.
    if (inboxId) {
      const id = inboxId
      void processInboxItem(id, app.log).catch((err) => {
        app.log.error({ err, inboxId: id }, 'wearable webhook: inline inbox processing crashed')
      })
    }

    return reply.send({
      received: true,
      status: aggregatorConfigured() ? 'accepted_terra_stub' : 'ignored_unconfigured',
      imported,
    })
  })
}
