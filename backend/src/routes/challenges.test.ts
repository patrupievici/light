import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Mock prisma so the REAL visibility gate (loadVisibleChallenge → acceptedFriendIds
// → prisma.friendship) runs end-to-end.
const challengeFindUnique = vi.fn()
const challengeFindMany = vi.fn()
const friendshipFindMany = vi.fn()
const participantFindUnique = vi.fn()
const participantCreate = vi.fn()
const participantUpsert = vi.fn()
const participantUpdate = vi.fn()
const participantUpdateMany = vi.fn()
const participantDeleteMany = vi.fn()
const participantFindMany = vi.fn()
const participantGroupBy = vi.fn()
const workoutFindMany = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    challenge: {
      findUnique: (...a: unknown[]) => challengeFindUnique(...a),
      findMany: (...a: unknown[]) => challengeFindMany(...a),
    },
    friendship: { findMany: (...a: unknown[]) => friendshipFindMany(...a) },
    challengeParticipant: {
      findUnique: (...a: unknown[]) => participantFindUnique(...a),
      create: (...a: unknown[]) => participantCreate(...a),
      createMany: (...a: unknown[]) => participantCreate(...a),
      upsert: (...a: unknown[]) => participantUpsert(...a),
      update: (...a: unknown[]) => participantUpdate(...a),
      updateMany: (...a: unknown[]) => participantUpdateMany(...a),
      deleteMany: (...a: unknown[]) => participantDeleteMany(...a),
      findMany: (...a: unknown[]) => participantFindMany(...a),
      groupBy: (...a: unknown[]) => participantGroupBy(...a),
    },
    workout: { findMany: (...a: unknown[]) => workoutFindMany(...a) },
  },
}))

let meId = 'me'
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: meId, email: `${meId}@t.dev` }
  },
}))

import { challengeRoutes } from './challenges'

async function buildApp() {
  const app = Fastify()
  await app.register(challengeRoutes, { prefix: '/v1/challenges' })
  await app.ready()
  return app
}

const CID = '33333333-3333-3333-3333-333333333333'
const FUTURE = new Date(Date.now() + 7 * 86_400_000)
const PAST = new Date(Date.now() - 86_400_000)

beforeEach(() => {
  meId = 'me'
  challengeFindUnique.mockReset()
  challengeFindMany.mockReset()
  friendshipFindMany.mockReset()
  participantFindUnique.mockReset()
  participantCreate.mockReset()
  participantUpsert.mockReset()
  participantUpdate.mockReset()
  participantUpdateMany.mockReset()
  participantDeleteMany.mockReset()
  participantFindMany.mockReset()
  participantGroupBy.mockReset()
  workoutFindMany.mockReset()
  workoutFindMany.mockResolvedValue([])
  friendshipFindMany.mockResolvedValue([]) // no friends unless a test says so
})

describe('GET /v1/challenges/discover', () => {
  const officialRow = {
    id: '00000000-0000-4000-8000-000000000101',
    creatorId: 'system',
    kind: 'pullUps',
    customTitle: null,
    visibility: 'public',
    isOfficial: true,
    targetHint: 'reps',
    durationDays: 3650,
    endsAt: new Date('2099-12-31T00:00:00.000Z'),
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    creator: { profile: { username: 'zvelt_official', displayName: 'Zvelt' } },
  }
  const userRow = {
    id: CID,
    creatorId: 'other',
    kind: 'custom',
    customTitle: 'Burpee Bonanza',
    visibility: 'public',
    isOfficial: false,
    targetHint: null,
    durationDays: 30,
    endsAt: FUTURE,
    createdAt: new Date(),
    creator: { profile: { username: 'bob', displayName: 'Bob' } },
  }

  it('returns public rooms with isOfficial, participantsCount and joined', async () => {
    challengeFindMany.mockResolvedValue([officialRow, userRow])
    participantGroupBy.mockResolvedValue([
      { challengeId: officialRow.id, _count: { challengeId: 42 } },
    ])
    participantFindMany.mockResolvedValue([{ challengeId: userRow.id }]) // I'm in the user room

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/challenges/discover' })
    expect(res.statusCode).toBe(200)
    const data = res.json().data as Array<Record<string, unknown>>

    const official = data.find((d) => d.id === officialRow.id)!
    expect(official.isOfficial).toBe(true)
    expect(official.title).toBe('Pull-up challenge')
    expect(official.participantsCount).toBe(42)
    expect(official.joined).toBe(false)

    const user = data.find((d) => d.id === userRow.id)!
    expect(user.isOfficial).toBe(false)
    expect(user.title).toBe('Burpee Bonanza')
    expect(user.participantsCount).toBe(0) // no group row → 0
    expect(user.joined).toBe(true)

    // The where-clause restricts to public + active.
    const where = challengeFindMany.mock.calls[0][0].where
    expect(where.visibility).toBe('public')
    expect(where.endsAt.gt).toBeInstanceOf(Date)
    await app.close()
  })

  it('returns an empty page (no participant queries) when there are no public rooms', async () => {
    challengeFindMany.mockResolvedValue([])
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/challenges/discover?page=3&limit=10' })
    expect(res.statusCode).toBe(200)
    expect(res.json().data).toEqual([])
    expect(res.json().meta).toMatchObject({ page: 3, limit: 10 })
    expect(participantGroupBy).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('POST /v1/challenges/:id/join', () => {
  it('joins a public challenge (201) as an accepted participant (upsert)', async () => {
    challengeFindUnique.mockResolvedValue({ id: CID, creatorId: 'other', visibility: 'public', endsAt: FUTURE })
    participantUpsert.mockResolvedValue({ joinedAt: new Date('2026-06-01T00:00:00Z') })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/challenges/${CID}/join` })

    expect(res.statusCode).toBe(201)
    expect(res.json().data).toMatchObject({ challengeId: CID, userId: 'me', status: 'accepted' })
    expect(participantUpsert).toHaveBeenCalledOnce()
    await app.close()
  })

  it('is idempotent — join upserts (accept), no duplicate participant', async () => {
    challengeFindUnique.mockResolvedValue({ id: CID, creatorId: 'other', visibility: 'public', endsAt: FUTURE })
    participantUpsert.mockResolvedValue({ joinedAt: new Date('2026-05-01T00:00:00Z') })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/challenges/${CID}/join` })

    expect(res.statusCode).toBe(201)
    expect(res.json().data).toMatchObject({ status: 'accepted' })
    expect(participantUpsert).toHaveBeenCalledOnce()
    await app.close()
  })

  it('400 CHALLENGE_EXPIRED when the challenge already ended', async () => {
    challengeFindUnique.mockResolvedValue({ id: CID, creatorId: 'other', visibility: 'public', endsAt: PAST })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/challenges/${CID}/join` })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'CHALLENGE_EXPIRED' })
    expect(participantCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('404 when the challenge does not exist', async () => {
    challengeFindUnique.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/challenges/${CID}/join` })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    await app.close()
  })

  it('403 FORBIDDEN — a friends-only challenge from a NON-friend creator is not joinable', async () => {
    challengeFindUnique.mockResolvedValue({ id: CID, creatorId: 'stranger', visibility: 'friends', endsAt: FUTURE })
    friendshipFindMany.mockResolvedValue([]) // viewer is not friends with the creator

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/challenges/${CID}/join` })

    expect(res.statusCode).toBe(403)
    expect(res.json()).toMatchObject({ error: 'FORBIDDEN' })
    expect(participantCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('a friends-only challenge IS joinable when the creator is an accepted friend', async () => {
    challengeFindUnique.mockResolvedValue({ id: CID, creatorId: 'buddy', visibility: 'friends', endsAt: FUTURE })
    // viewer `me` is friends with `buddy`.
    friendshipFindMany.mockResolvedValue([{ userId: 'me', friendUserId: 'buddy', status: 'accepted' }])
    participantUpsert.mockResolvedValue({ joinedAt: new Date('2026-06-01T00:00:00Z') })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: `/v1/challenges/${CID}/join` })

    expect(res.statusCode).toBe(201)
    expect(participantUpsert).toHaveBeenCalledOnce()
    await app.close()
  })

  it('400 on a non-UUID challenge id', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/challenges/not-a-uuid/join' })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(challengeFindUnique).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('DELETE /v1/challenges/:id/leave', () => {
  it('removes the participant and returns 204', async () => {
    participantDeleteMany.mockResolvedValue({ count: 1 })
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: `/v1/challenges/${CID}/leave` })

    expect(res.statusCode).toBe(204)
    expect((participantDeleteMany.mock.calls[0][0] as { where: object }).where).toEqual({ challengeId: CID, userId: 'me' })
    await app.close()
  })

  it('400 on a non-UUID id (no delete attempted)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/challenges/bad/leave' })

    expect(res.statusCode).toBe(400)
    expect(participantDeleteMany).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('GET /v1/challenges/:id/participants', () => {
  it('returns the roster with a correct total, gated by visibility', async () => {
    challengeFindUnique.mockResolvedValue({ id: CID, creatorId: 'me', visibility: 'friends', endsAt: FUTURE })
    participantFindMany.mockResolvedValue([
      { userId: 'me', joinedAt: new Date('2026-06-01T00:00:00Z'), user: { profile: { username: 'me', displayName: 'Me' } } },
      { userId: 'p2', joinedAt: new Date('2026-06-02T00:00:00Z'), user: { profile: { username: 'p2', displayName: 'Pal' } } },
    ])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/v1/challenges/${CID}/participants` })

    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.total).toBe(2)
    expect(body.data).toHaveLength(2)
    expect(body.data[1]).toMatchObject({ userId: 'p2', displayName: 'Pal' })
    await app.close()
  })

  it('403 — cannot view participants of a friends-only challenge from a stranger', async () => {
    challengeFindUnique.mockResolvedValue({ id: CID, creatorId: 'stranger', visibility: 'friends', endsAt: FUTURE })
    friendshipFindMany.mockResolvedValue([])

    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: `/v1/challenges/${CID}/participants` })

    expect(res.statusCode).toBe(403)
    expect(participantFindMany).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('POST /v1/challenges — create', () => {
  it('422-style 400 when kind=custom but no customTitle', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/challenges',
      payload: { kind: 'custom', visibility: 'friends', durationDays: 30 },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })

  it('400 when durationDays is out of range', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/challenges',
      payload: { kind: 'squat', visibility: 'public', durationDays: 9999 },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    await app.close()
  })
})
