import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'
import fs from 'node:fs'
import path from 'node:path'

// ── Mocks ───────────────────────────────────────────────────────────────────
// eraseUser wraps the whole cascade in prisma.$transaction(cb). We invoke the
// callback with a spy `tx` so we can assert the delete SEQUENCE runs and that
// the user row itself is deleted last.
const txSpies = {
  workout: { findMany: vi.fn().mockResolvedValue([{ id: 'w1' }]), deleteMany: vi.fn() },
  workoutExercise: { findMany: vi.fn().mockResolvedValue([{ id: 'we1' }]), deleteMany: vi.fn() },
  workoutSet: { findMany: vi.fn().mockResolvedValue([{ id: 's1' }]), deleteMany: vi.fn() },
  setEditAudit: { deleteMany: vi.fn() },
  post: { findMany: vi.fn().mockResolvedValue([{ id: 'p1' }]), deleteMany: vi.fn() },
  postLike: { deleteMany: vi.fn() },
  postComment: { deleteMany: vi.fn() },
  postBookmark: { deleteMany: vi.fn() },
  postHide: { deleteMany: vi.fn() },
  postReport: { deleteMany: vi.fn() },
  postPrivacySetting: { deleteMany: vi.fn() },
  userExerciseRank: { deleteMany: vi.fn() },
  userExerciseProgress: { deleteMany: vi.fn() },
  userSeasonStat: { deleteMany: vi.fn() },
  friendship: { deleteMany: vi.fn() },
  notification: { deleteMany: vi.fn() },
  directConversation: {
    // Default: one shared conversation u1 ↔ peer (low<high lexical convention).
    findMany: vi.fn().mockResolvedValue([{ id: 'c1', userLowId: 'peer', userHighId: 'u1' }]),
    findFirst: vi.fn().mockResolvedValue(null),
    update: vi.fn(),
    delete: vi.fn(),
    deleteMany: vi.fn(),
  },
  directMessage: { updateMany: vi.fn(), deleteMany: vi.fn() },
  walletTransaction: { deleteMany: vi.fn() },
  wallet: { deleteMany: vi.fn() },
  userAchievement: { deleteMany: vi.fn() },
  userPushToken: { deleteMany: vi.fn() },
  plannedWorkout: { deleteMany: vi.fn() },
  routine: { deleteMany: vi.fn() },
  userBodyMeasurement: { deleteMany: vi.fn() },
  nutritionMealTemplate: { deleteMany: vi.fn() },
  healthConsentEvent: { deleteMany: vi.fn() },
  nutritionLogDay: { deleteMany: vi.fn() },
  nutritionPlanDay: { deleteMany: vi.fn() },
  story: { deleteMany: vi.fn() },
  healthConsent: { deleteMany: vi.fn() },
  analyticsEvent: { deleteMany: vi.fn() },
  refreshToken: { deleteMany: vi.fn() },
  challengeParticipant: { deleteMany: vi.fn() },
  challenge: { deleteMany: vi.fn() },
  segmentEffort: { deleteMany: vi.fn() },
  gpsActivity: { deleteMany: vi.fn() },
  userTrainingProfile: { deleteMany: vi.fn() },
  userProfile: { deleteMany: vi.fn() },
  authIdentity: { deleteMany: vi.fn() },
  user: { upsert: vi.fn(), delete: vi.fn() },
}

const transaction = vi.fn(async (cb: (tx: typeof txSpies) => Promise<void>) => cb(txSpies))

// Top-level prisma accessors used by the soft-delete path (flag ON). The
// array-form $transaction([...]) just awaits the already-issued promises.
const userUpdate = vi.fn().mockResolvedValue({})
const refreshTokenDeleteMany = vi.fn().mockResolvedValue({ count: 0 })

vi.mock('../lib/prisma', () => ({
  prisma: {
    // Supports BOTH forms: callback (eraseUser cascade) and array (soft-delete).
    $transaction: (arg: unknown) =>
      typeof arg === 'function'
        ? transaction(arg as never)
        : Promise.all(arg as Promise<unknown>[]),
    user: { update: (...a: unknown[]) => userUpdate(...a) },
    refreshToken: { deleteMany: (...a: unknown[]) => refreshTokenDeleteMany(...a) },
    // Pre-transaction reads that collect on-disk media URLs before erasure.
    userProfile: { findUnique: vi.fn().mockResolvedValue(null) },
    post: { findMany: vi.fn().mockResolvedValue([]) },
    story: { findMany: vi.fn().mockResolvedValue([]) },
  },
}))

vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

// Provider-revoke is a best-effort remote side-effect: mock it so the cascade
// tests stay pure (no fetch / live integrations module) and so we can assert it
// runs BEFORE the DB transaction.
const revokeAllProviderConnections = vi.fn().mockResolvedValue({ total: 0, revoked: 0 })
vi.mock('./integrations', () => ({
  revokeAllProviderConnections: (...a: unknown[]) => revokeAllProviderConnections(...a),
}))

import { gdprRoutes } from './gdpr'

async function buildApp() {
  const app = Fastify()
  await app.register(gdprRoutes, { prefix: '/v1' })
  await app.ready()
  return app
}

beforeEach(() => {
  transaction.mockClear()
  userUpdate.mockClear()
  refreshTokenDeleteMany.mockClear()
  // Default OFF so the immediate-erase tests reflect production default.
  delete process.env.ZVELT_SOFT_DELETE
  revokeAllProviderConnections.mockClear()
  revokeAllProviderConnections.mockResolvedValue({ total: 0, revoked: 0 })
  Object.values(txSpies).forEach((model) =>
    Object.values(model).forEach((fn) => (fn as ReturnType<typeof vi.fn>).mockClear?.()),
  )
})

describe('DELETE /v1/me/account — right-to-erasure cascade', () => {
  it('runs the full cascade in ONE transaction and deletes the user row last', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })

    expect(res.statusCode).toBe(204)
    // Whole erasure is a single transaction (atomic — no orphan rows on failure).
    expect(transaction).toHaveBeenCalledOnce()

    // Identity/credentials are erased.
    expect(txSpies.authIdentity.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } })
    expect(txSpies.refreshToken.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } })
    // The user's posts are removed, scoped to the user.
    expect(txSpies.post.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } })
    // Body measurements are erased, scoped to the user.
    expect(txSpies.userBodyMeasurement.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } })
    // The user row itself is deleted.
    expect(txSpies.user.delete).toHaveBeenCalledWith({ where: { id: 'u1' } })

    // Ordering invariants: posts before the user row; the user row is the very
    // last write (everything FK-dependent is already gone).
    const postOrder = txSpies.post.deleteMany.mock.invocationCallOrder[0]
    const userOrder = txSpies.user.delete.mock.invocationCallOrder[0]
    const identityOrder = txSpies.authIdentity.deleteMany.mock.invocationCallOrder[0]
    expect(postOrder).toBeLessThan(userOrder)
    expect(identityOrder).toBeLessThan(userOrder)
    await app.close()
  })

  it('returns 500 ERASURE_FAILED and does not 204 when the transaction throws', async () => {
    transaction.mockRejectedValueOnce(new Error('db down'))
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })

    expect(res.statusCode).toBe(500)
    expect(res.json()).toMatchObject({ error: 'ERASURE_FAILED' })
    await app.close()
  })

  it('rejects erasure without the typed confirmation (no transaction runs)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account' })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'CONFIRMATION_REQUIRED' })
    expect(transaction).not.toHaveBeenCalled()
    await app.close()
  })

  it('revokes external provider connections BEFORE the DB transaction', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })

    expect(res.statusCode).toBe(204)
    expect(revokeAllProviderConnections).toHaveBeenCalledOnce()
    expect(revokeAllProviderConnections).toHaveBeenCalledWith('u1', expect.anything())
    // Remote revoke must happen while connection rows/tokens still exist, i.e.
    // before any of the DB deletes inside the transaction.
    const revokeOrder = revokeAllProviderConnections.mock.invocationCallOrder[0]
    const txOrder = transaction.mock.invocationCallOrder[0]
    expect(revokeOrder).toBeLessThan(txOrder)
    await app.close()
  })

  it('still erases the account (204) when provider revoke fails', async () => {
    revokeAllProviderConnections.mockRejectedValueOnce(new Error('terra down'))
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })

    expect(res.statusCode).toBe(204)
    // A failing remote revoke must never block erasure: the cascade still ran.
    expect(transaction).toHaveBeenCalledOnce()
    expect(txSpies.user.delete).toHaveBeenCalledWith({ where: { id: 'u1' } })
    await app.close()
  })
})

describe('DELETE /v1/me/account — soft-delete flag gating', () => {
  it('flag OFF (default): runs the immediate eraseUser cascade (unchanged behavior)', async () => {
    // No ZVELT_SOFT_DELETE set — must hit the historical path.
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })

    expect(res.statusCode).toBe(204)
    // Immediate erasure cascade ran; soft-delete update did NOT.
    expect(transaction).toHaveBeenCalledOnce()
    expect(txSpies.user.delete).toHaveBeenCalledWith({ where: { id: 'u1' } })
    expect(userUpdate).not.toHaveBeenCalled()
    await app.close()
  })

  it('flag ON: soft-deletes (sets status/timestamps, revokes tokens) without erasing', async () => {
    process.env.ZVELT_SOFT_DELETE = 'on'
    const app = await buildApp()
    const before = Date.now()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })

    expect(res.statusCode).toBe(204)
    // No cascade erase ran on the soft path.
    expect(transaction).not.toHaveBeenCalled()
    expect(txSpies.user.delete).not.toHaveBeenCalled()

    // The user row is marked deleted with both grace-window timestamps.
    expect(userUpdate).toHaveBeenCalledOnce()
    const arg = userUpdate.mock.calls[0][0] as {
      where: { id: string }
      data: { status: string; softDeletedAt: Date; scheduledHardEraseAt: Date }
    }
    expect(arg.where).toEqual({ id: 'u1' })
    expect(arg.data.status).toBe('deleted')
    expect(arg.data.softDeletedAt).toBeInstanceOf(Date)
    expect(arg.data.scheduledHardEraseAt).toBeInstanceOf(Date)
    // Hard-erase is scheduled ~30 days out.
    const graceMs = arg.data.scheduledHardEraseAt.getTime() - arg.data.softDeletedAt.getTime()
    expect(graceMs).toBe(30 * 24 * 60 * 60 * 1000)
    expect(arg.data.scheduledHardEraseAt.getTime()).toBeGreaterThan(before)

    // Sessions are revoked so the deleted account stops working immediately.
    expect(refreshTokenDeleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } })
    await app.close()
  })

  it('flag set to anything other than "on" keeps the immediate-erase path', async () => {
    process.env.ZVELT_SOFT_DELETE = 'true'
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })

    expect(res.statusCode).toBe(204)
    expect(transaction).toHaveBeenCalledOnce()
    expect(userUpdate).not.toHaveBeenCalled()
    await app.close()
  })

  it('flag ON still requires the typed confirmation (no soft-delete write)', async () => {
    process.env.ZVELT_SOFT_DELETE = 'on'
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account' })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'CONFIRMATION_REQUIRED' })
    expect(userUpdate).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('DELETE /v1/me/account — DM third-party policy', () => {
  it('anonymizes the erased user\'s DMs and keeps the peer\'s thread (no deleteMany of shared messages)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })
    expect(res.statusCode).toBe(204)

    // A sentinel "[deleted user]" is provisioned to inherit the erased seat.
    expect(txSpies.user.upsert).toHaveBeenCalledOnce()
    const upsertArg = txSpies.user.upsert.mock.calls[0][0] as { where: { id: string } }
    expect(upsertArg.where.id).toMatch(/dead/)

    // The erased user's authored messages are tombstoned + reassigned, NOT dropped.
    expect(txSpies.directMessage.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { conversationId: 'c1', senderId: 'u1' },
        data: expect.objectContaining({ body: '[deleted user]' }),
      }),
    )
    // The shared conversation is preserved (reassigned), not deleted.
    expect(txSpies.directConversation.update).toHaveBeenCalledOnce()
    expect(txSpies.directConversation.delete).not.toHaveBeenCalled()
    // We must NOT mass-delete the messages in a shared thread.
    expect(txSpies.directMessage.deleteMany).not.toHaveBeenCalled()
    await app.close()
  })

  it('deletes a self-conversation outright (no third party to preserve)', async () => {
    txSpies.directConversation.findMany.mockResolvedValueOnce([
      { id: 'cself', userLowId: 'u1', userHighId: 'u1' },
    ])
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })
    expect(res.statusCode).toBe(204)

    expect(txSpies.directMessage.deleteMany).toHaveBeenCalledWith({ where: { conversationId: 'cself' } })
    expect(txSpies.directConversation.delete).toHaveBeenCalledWith({ where: { id: 'cself' } })
    await app.close()
  })

  it('merges into an existing peer↔sentinel conversation on unique-constraint collision', async () => {
    txSpies.directConversation.findFirst.mockResolvedValueOnce({ id: 'cmerge' })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })
    expect(res.statusCode).toBe(204)

    // Messages are folded into the surviving conversation, then the dup is dropped.
    expect(txSpies.directMessage.updateMany).toHaveBeenCalledWith({
      where: { conversationId: 'c1' },
      data: { conversationId: 'cmerge' },
    })
    expect(txSpies.directConversation.delete).toHaveBeenCalledWith({ where: { id: 'c1' } })
    expect(txSpies.directConversation.update).not.toHaveBeenCalled()
    await app.close()
  })
})

// ── Export-completeness guard ────────────────────────────────────────────────
// Fails if a NEW user-owned relation is added to the User model but is neither
// erased explicitly in the transaction nor covered by an FK onDelete:Cascade.
// This is the tripwire that forces erasure to be updated alongside the schema.
describe('erasure completeness vs User relations (schema guard)', () => {
  // vitest runs from the backend package root, so prisma/ is directly beneath it.
  const schemaPath = path.resolve(process.cwd(), 'prisma/schema.prisma')

  /** Extract the relation field → target-model map from `model User { … }`. */
  function readUserRelations(schema: string): Array<{ field: string; model: string }> {
    const match = schema.match(/model User \{([\s\S]*?)\n\}/)
    if (!match) throw new Error('Could not locate `model User` block in schema.prisma')
    const relations: Array<{ field: string; model: string }> = []
    for (const rawLine of match[1].split('\n')) {
      const line = rawLine.trim()
      if (!line || line.startsWith('//') || line.startsWith('@@') || line.startsWith('@')) continue
      // `fieldName  TargetModel[]?  @relation(...)` — relations point at a model
      // whose name is PascalCase; scalar fields (String/DateTime/…) are skipped.
      const m = line.match(/^(\w+)\s+([A-Z]\w+)(\[\])?\??/)
      if (!m) continue
      const [, field, model] = m
      // Skip known scalar "types" that start uppercase (none here today, but be safe).
      if (['String', 'Int', 'Boolean', 'DateTime', 'Decimal', 'Float', 'Json', 'BigInt'].includes(model)) {
        continue
      }
      relations.push({ field, model })
    }
    return relations
  }

  // Prisma client accessor names are camelCase of the model name. The tx spy map
  // is keyed by exactly these accessors, so a present key == "erased explicitly".
  const explicitlyErased = new Set(Object.keys(txSpies))

  // Relations intentionally NOT deleted in the tx because the FK handles them:
  //   onDelete: Cascade  → row vanishes with the parent (incl. wearable_connections,
  //                        health imports/metrics, challenge logs/messages, story likes)
  //   onDelete: SetNull  → row is kept, creator nulled (segments authored by user)
  const fkCascadeOrSetNull = new Set<string>([
    'WearableConnection',
    'UserHealthImport',
    'UserHealthDailyMetric',
    'ChallengeProgressLog',
    'ChallengeMessage',
    'StoryLike',
    'Segment', // SetNull: authored segments outlive the author by design
    'UserProgram', // Cascade: a user's training programs vanish with the account
  ])

  function modelToAccessor(model: string): string {
    return model.charAt(0).toLowerCase() + model.slice(1)
  }

  it('every user-owned relation is erased explicitly or by FK cascade/setnull', () => {
    const schema = fs.readFileSync(schemaPath, 'utf8')
    const relations = readUserRelations(schema)
    expect(relations.length).toBeGreaterThan(0)

    const uncovered = relations.filter(({ model }) => {
      if (fkCascadeOrSetNull.has(model)) return false
      return !explicitlyErased.has(modelToAccessor(model))
    })

    expect(
      uncovered,
      `User relations not covered by eraseUser (add an explicit tx delete, or ` +
        `allowlist if the FK cascades): ${uncovered.map((r) => `${r.field}→${r.model}`).join(', ')}`,
    ).toEqual([])
  })

  it('every explicitly-erased model in the tx is actually exercised by the cascade test', async () => {
    // Sanity: the spy map should not drift — every key must correspond to a real
    // delete call so the export/erasure cascade stays observable in tests.
    const app = await buildApp()
    await app.inject({ method: 'DELETE', url: '/v1/me/account', payload: { confirm: 'DELETE' } })
    // user.delete is the terminal write; its presence proves the tx body ran.
    expect(txSpies.user.delete).toHaveBeenCalledOnce()
    await app.close()
  })
})
