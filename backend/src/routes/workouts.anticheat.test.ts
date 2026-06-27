import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Only the prisma methods the PATCH /sets handler touches are stubbed. The
// audit write is fire-and-forget (`void prisma.setEditAudit.create(...).catch`)
// so its create() must return a thenable.
const workoutSetFindFirst = vi.fn()
const workoutSetUpdate = vi.fn()
const workoutSetCreate = vi.fn()
const workoutExerciseFindFirst = vi.fn()
const setEditAuditCreate = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    workoutExercise: {
      findFirst: (...a: unknown[]) => workoutExerciseFindFirst(...a),
    },
    workoutSet: {
      findFirst: (...a: unknown[]) => workoutSetFindFirst(...a),
      update: (...a: unknown[]) => workoutSetUpdate(...a),
      create: (...a: unknown[]) => workoutSetCreate(...a),
    },
    setEditAudit: { create: (...a: unknown[]) => setEditAuditCreate(...a) },
  },
}))

// Async authenticate that injects a fixed user (a sync preHandler would hang).
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: 'u1', email: 'u1@t.dev' }
  },
}))

import { workoutRoutes } from './workouts'

const URL = '/v1/workouts/w1/exercises/we1/sets/s1'

async function buildApp() {
  const app = Fastify()
  await app.register(workoutRoutes, { prefix: '/v1/workouts' })
  await app.ready()
  return app
}

beforeEach(() => {
  workoutSetFindFirst.mockReset()
  workoutSetUpdate.mockReset()
  workoutSetCreate.mockReset()
  workoutExerciseFindFirst.mockReset()
  setEditAuditCreate.mockReset()
  // Default: audit create resolves so the chained .catch() doesn't reject.
  setEditAuditCreate.mockResolvedValue({ id: 'audit1' })
})

describe('PATCH set — anti-cheat audit + >2x weight-jump flag', () => {
  it('writes a set_edit_audit with before/after, flags a >2x jump, and persists the note', async () => {
    workoutSetFindFirst.mockResolvedValue({
      id: 's1', weightKg: 100, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })
    workoutSetUpdate.mockResolvedValue({
      id: 's1', weightKg: 250, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })

    const app = await buildApp()
    // A >2x jump (100 -> 250) is allowed ONLY with a justification note.
    const res = await app.inject({
      method: 'PATCH', url: URL, payload: { weightKg: 250, note: '  finally hit a PR  ' },
    })

    expect(res.statusCode).toBe(200)
    expect(setEditAuditCreate).toHaveBeenCalledOnce()
    const auditArg = setEditAuditCreate.mock.calls[0][0] as {
      data: { before: { weightKg: number }; after: { weightKg: number }; flagged: boolean; setId: string; userId: string; note: string | null }
    }
    // before/after snapshot is persisted.
    expect(auditArg.data.before.weightKg).toBe(100)
    expect(auditArg.data.after.weightKg).toBe(250)
    expect(auditArg.data.setId).toBe('s1')
    expect(auditArg.data.userId).toBe('u1')
    // 250 > 100*2 → flagged as an anomaly.
    expect(auditArg.data.flagged).toBe(true)
    // The user's note is trimmed and persisted into the audit row.
    expect(auditArg.data.note).toBe('finally hit a PR')
    await app.close()
  })

  it('REJECTS a >2x weight jump with 422 when no note is supplied (no DB write)', async () => {
    workoutSetFindFirst.mockResolvedValue({
      id: 's1', weightKg: 100, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })

    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH', url: URL, payload: { weightKg: 250 }, // no note
    })

    expect(res.statusCode).toBe(422)
    expect(res.json()).toMatchObject({ error: 'WEIGHT_JUMP_REQUIRES_NOTE' })
    // The suspicious edit is blocked BEFORE touching the DB or audit.
    expect(workoutSetUpdate).not.toHaveBeenCalled()
    expect(setEditAuditCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('a blank/whitespace-only note does NOT satisfy the >2x jump requirement (422)', async () => {
    workoutSetFindFirst.mockResolvedValue({
      id: 's1', weightKg: 100, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })

    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH', url: URL, payload: { weightKg: 250, note: '   ' },
    })

    expect(res.statusCode).toBe(422)
    expect(res.json()).toMatchObject({ error: 'WEIGHT_JUMP_REQUIRES_NOTE' })
    expect(workoutSetUpdate).not.toHaveBeenCalled()
    await app.close()
  })

  it('a non-weight edit (reps only) on a high set is NOT treated as a weight jump', async () => {
    // Old weight stays at 100 (no weightKg in payload) → proposedW === beforeW,
    // so the >2x guard never fires even though the absolute weight is high.
    workoutSetFindFirst.mockResolvedValue({
      id: 's1', weightKg: 100, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })
    workoutSetUpdate.mockResolvedValue({
      id: 's1', weightKg: 100, reps: 8, rpe: 8, tag: 'WORK', isCompleted: true,
    })

    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH', url: URL, payload: { reps: 8 },
    })

    expect(res.statusCode).toBe(200)
    expect(setEditAuditCreate).toHaveBeenCalledOnce()
    const auditArg = setEditAuditCreate.mock.calls[0][0] as { data: { flagged: boolean; note: string | null } }
    expect(auditArg.data.flagged).toBe(false)
    expect(auditArg.data.note).toBeNull()
    await app.close()
  })

  it('does NOT flag a normal edit within 2x (audit still written)', async () => {
    workoutSetFindFirst.mockResolvedValue({
      id: 's1', weightKg: 100, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })
    workoutSetUpdate.mockResolvedValue({
      id: 's1', weightKg: 110, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })

    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH', url: URL, payload: { weightKg: 110 },
    })

    expect(res.statusCode).toBe(200)
    expect(setEditAuditCreate).toHaveBeenCalledOnce()
    const auditArg = setEditAuditCreate.mock.calls[0][0] as { data: { flagged: boolean } }
    expect(auditArg.data.flagged).toBe(false)
    await app.close()
  })

  it('returns 404 (and writes NO audit) when the set is not the user\'s', async () => {
    workoutSetFindFirst.mockResolvedValue(null) // ownership scope filters it out

    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH', url: URL, payload: { weightKg: 250 },
    })

    expect(res.statusCode).toBe(404)
    expect(res.json()).toMatchObject({ error: 'NOT_FOUND' })
    expect(workoutSetUpdate).not.toHaveBeenCalled()
    expect(setEditAuditCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('rejects an empty edit body with a 400 validation error', async () => {
    workoutSetFindFirst.mockResolvedValue({
      id: 's1', weightKg: 100, reps: 5, rpe: 8, tag: 'WORK', isCompleted: true,
    })

    const app = await buildApp()
    const res = await app.inject({ method: 'PATCH', url: URL, payload: {} })

    expect(res.statusCode).toBe(400)
    expect(res.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(workoutSetUpdate).not.toHaveBeenCalled()
    await app.close()
  })
})

const ADD_URL = '/v1/workouts/w1/exercises/we1/sets'
const DAY_MS = 86_400_000

describe('POST set — anti-cheat >2x personal-max weight jump', () => {
  beforeEach(() => {
    // Ownership check passes for every add test.
    workoutExerciseFindFirst.mockResolvedValue({ id: 'we1', workoutId: 'w1', exerciseId: 'ex1' })
    workoutSetCreate.mockResolvedValue({
      id: 's1', setIndex: 0, weightKg: 250, reps: 3, tag: 'WORK', isCompleted: true, note: null,
    })
  })

  it('REJECTS a >2x jump vs a RECENT (<7d) personal max with 422 when no note (no DB write)', async () => {
    // pmax 100kg set today; logging 250kg (>2x) without a note → blocked.
    workoutSetFindFirst.mockResolvedValueOnce({ weightKg: 100, createdAt: new Date() })

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: ADD_URL, payload: { weightKg: 250, reps: 3 } })

    expect(res.statusCode).toBe(422)
    expect(res.json()).toMatchObject({ error: 'WEIGHT_JUMP_REQUIRES_NOTE' })
    expect(workoutSetCreate).not.toHaveBeenCalled()
    await app.close()
  })

  it('ACCEPTS the same >2x jump when a note is supplied, and persists the trimmed note', async () => {
    workoutSetFindFirst
      .mockResolvedValueOnce({ weightKg: 100, createdAt: new Date() }) // personal max
      .mockResolvedValueOnce(null) // lastSet → setIndex 0

    const app = await buildApp()
    const res = await app.inject({
      method: 'POST', url: ADD_URL, payload: { weightKg: 250, reps: 3, note: '  belt + spotter PR  ' },
    })

    expect(res.statusCode).toBe(201)
    expect(workoutSetCreate).toHaveBeenCalledOnce()
    const createArg = workoutSetCreate.mock.calls[0][0] as { data: { note: string | null } }
    expect(createArg.data.note).toBe('belt + spotter PR')
    await app.close()
  })

  it('ALLOWS a >2x jump (no note) when the personal max is OLD (>7d) — gradual progression', async () => {
    workoutSetFindFirst
      .mockResolvedValueOnce({ weightKg: 100, createdAt: new Date(Date.now() - 8 * DAY_MS) })
      .mockResolvedValueOnce(null)

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: ADD_URL, payload: { weightKg: 250, reps: 3 } })

    expect(res.statusCode).toBe(201)
    expect(workoutSetCreate).toHaveBeenCalledOnce()
    await app.close()
  })

  it('ALLOWS a first-ever heavy set (no personal max on record) without a note', async () => {
    workoutSetFindFirst
      .mockResolvedValueOnce(null) // no personal max
      .mockResolvedValueOnce(null)

    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: ADD_URL, payload: { weightKg: 250, reps: 3 } })

    expect(res.statusCode).toBe(201)
    expect(workoutSetCreate).toHaveBeenCalledOnce()
    await app.close()
  })

  it('does NOT weight-check a WARMUP set, however heavy', async () => {
    // No personal-max query should even run for a warmup; create proceeds.
    workoutSetFindFirst.mockResolvedValueOnce(null) // lastSet only

    const app = await buildApp()
    const res = await app.inject({
      method: 'POST', url: ADD_URL, payload: { weightKg: 250, reps: 3, tag: 'WARMUP' },
    })

    expect(res.statusCode).toBe(201)
    expect(workoutSetCreate).toHaveBeenCalledOnce()
    await app.close()
  })
})
