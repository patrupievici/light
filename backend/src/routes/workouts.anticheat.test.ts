import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// ── Mocks ───────────────────────────────────────────────────────────────────
// Only the prisma methods the PATCH /sets handler touches are stubbed. The
// audit write is fire-and-forget (`void prisma.setEditAudit.create(...).catch`)
// so its create() must return a thenable.
const workoutSetFindFirst = vi.fn()
const workoutSetUpdate = vi.fn()
const setEditAuditCreate = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    workoutSet: {
      findFirst: (...a: unknown[]) => workoutSetFindFirst(...a),
      update: (...a: unknown[]) => workoutSetUpdate(...a),
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
