import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'

// Route-level coverage for /v1/programs. The materialization math + progression
// have their own pure tests (program-materialize / program-progression /
// program.service computeProgramAdvance); here we drive the actual HTTP handlers
// so auth, Zod validation, the error-response shape, 404s, and the simple
// service paths (start / advance / archive / delete / active-empty) are
// observable end-to-end. The materialization-heavy reads (/active with a program,
// /:id/day, /:id/start-day) fan out across the whole Prisma graph and are covered
// by the pure layer instead of brittle full-graph mocks.

const userProgram = {
  findFirst: vi.fn(),
  findMany: vi.fn(),
  create: vi.fn(),
  update: vi.fn(),
  updateMany: vi.fn(),
  delete: vi.fn(),
}
// Catalog lookup for the enriched library cards (equipment + thumbnails). The
// media DB env is unset in tests, so buildMediaByExerciseId returns empty — the
// summaries still render, just without thumbnails.
const exerciseFindMany = vi.fn(async () => [] as unknown[])

vi.mock('../lib/prisma', () => ({
  prisma: {
    userProgram: {
      findFirst: (...a: unknown[]) => userProgram.findFirst(...a),
      findMany: (...a: unknown[]) => userProgram.findMany(...a),
      create: (...a: unknown[]) => userProgram.create(...a),
      update: (...a: unknown[]) => userProgram.update(...a),
      updateMany: (...a: unknown[]) => userProgram.updateMany(...a),
      delete: (...a: unknown[]) => userProgram.delete(...a),
    },
    exercise: { findMany: (...a: unknown[]) => exerciseFindMany(...a) },
  },
}))

let meId = 'u1'
vi.mock('../middleware/auth', () => ({
  authenticate: async (req: { user?: { userId: string; email: string } }) => {
    req.user = { userId: meId, email: `${meId}@t.dev` }
  },
}))

import { programRoutes } from './programs'

async function buildApp() {
  const app = Fastify()
  await app.register(programRoutes, { prefix: '/v1/programs' })
  await app.ready()
  return app
}

function makeProgram(over: Record<string, unknown> = {}) {
  return {
    id: 'p1',
    userId: 'u1',
    templateId: 'stronglifts_5x5',
    title: 'StrongLifts 5×5',
    totalWeeks: 12,
    daysPerWeek: 3,
    progressionScheme: 'linear',
    deloadCadence: 0,
    status: 'active',
    currentWeek: 1,
    stateJson: { sessionIndex: 0, tm: {} },
    structureJson: null,
    equipmentTags: [],
    startedAt: new Date('2026-06-26T10:00:00.000Z'),
    completedAt: null,
    createdAt: new Date('2026-06-26T10:00:00.000Z'),
    updatedAt: new Date('2026-06-26T10:00:00.000Z'),
    ...over,
  }
}

beforeEach(() => {
  meId = 'u1'
  for (const fn of Object.values(userProgram)) fn.mockReset()
})

describe('GET /v1/programs/templates', () => {
  it('returns the 8-program library', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/programs/templates' })
    expect(res.statusCode).toBe(200)
    const data = res.json().data
    expect(data).toHaveLength(8)
    expect(data.map((t: { id: string }) => t.id)).toContain('531_bbb')
    // Card metadata is present (Liftosaur-style library).
    const sl = data.find((t: { id: string }) => t.id === 'stronglifts_5x5')
    expect(sl.exercisesPerDay).toBe('3')
    expect(sl.sessionTime).toMatch(/mins/)
    expect(Array.isArray(sl.equipment)).toBe(true)
    expect(Array.isArray(sl.thumbnails)).toBe(true)
    // exerciseNames is an internal field — must NOT leak to the client.
    expect(sl.exerciseNames).toBeUndefined()
    await app.close()
  })
})

describe('GET /v1/programs/templates/:id', () => {
  it('returns full template detail (days × slots)', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/programs/templates/nsuns_4day' })
    expect(res.statusCode).toBe(200)
    const tpl = res.json().template
    expect(tpl.id).toBe('nsuns_4day')
    expect(tpl.trainingMaxLifts.length).toBeGreaterThan(0)
    expect(tpl.days[0].slots[0].sets.kind).toBe('wave')
    await app.close()
  })

  it('404s for an unknown template', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/programs/templates/nope' })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NOT_FOUND')
    await app.close()
  })
})

describe('POST /v1/programs/start', () => {
  it('archives any active program and creates the new one', async () => {
    userProgram.updateMany.mockResolvedValue({ count: 1 })
    userProgram.create.mockResolvedValue(makeProgram())
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/programs/start',
      payload: { templateId: 'stronglifts_5x5', weeks: 12 },
    })
    expect(res.statusCode).toBe(201)
    expect(userProgram.updateMany).toHaveBeenCalledWith({
      where: { userId: 'u1', status: 'active' },
      data: { status: 'archived' },
    })
    expect(userProgram.create).toHaveBeenCalledOnce()
    expect(res.json().program.templateId).toBe('stronglifts_5x5')
    await app.close()
  })

  it('404s for an unknown template id', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'POST',
      url: '/v1/programs/start',
      payload: { templateId: 'does_not_exist' },
    })
    expect(res.statusCode).toBe(404)
    await app.close()
  })

  it('400s on invalid body', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/programs/start', payload: {} })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
    expect(res.json()).toHaveProperty('requestId')
    await app.close()
  })
})

describe('GET /v1/programs/active', () => {
  it('returns nulls when the user has no active and no completed program', async () => {
    userProgram.findFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/programs/active' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ program: null, today: null, completed: false })
    await app.close()
  })

  it('falls back to the most recent completed program', async () => {
    userProgram.findFirst
      .mockResolvedValueOnce(null) // no active
      .mockResolvedValueOnce(makeProgram({ status: 'completed', completedAt: new Date('2026-06-25T00:00:00.000Z') }))
    const app = await buildApp()
    const res = await app.inject({ method: 'GET', url: '/v1/programs/active' })
    expect(res.statusCode).toBe(200)
    expect(res.json().completed).toBe(true)
    expect(res.json().program.status).toBe('completed')
    expect(res.json().today).toBeNull()
    await app.close()
  })
})

describe('POST /v1/programs/:id/advance', () => {
  it('advances the session and persists the new state', async () => {
    userProgram.findFirst.mockResolvedValue(makeProgram())
    userProgram.update.mockImplementation(async ({ data }: { data: Record<string, unknown> }) =>
      makeProgram({ ...data }),
    )
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/programs/p1/advance' })
    expect(res.statusCode).toBe(200)
    expect(userProgram.update).toHaveBeenCalledOnce()
    await app.close()
  })

  it('404s when the program is not the user\'s', async () => {
    userProgram.findFirst.mockResolvedValue(null)
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/programs/p1/advance' })
    expect(res.statusCode).toBe(404)
    await app.close()
  })

  it('409s when the program is not active', async () => {
    userProgram.findFirst.mockResolvedValue(makeProgram({ status: 'archived' }))
    const app = await buildApp()
    const res = await app.inject({ method: 'POST', url: '/v1/programs/p1/advance' })
    expect(res.statusCode).toBe(409)
    await app.close()
  })
})

describe('PATCH + DELETE /v1/programs/:id', () => {
  it('archives via PATCH', async () => {
    userProgram.findFirst.mockResolvedValue(makeProgram())
    userProgram.update.mockResolvedValue(makeProgram({ status: 'archived' }))
    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/v1/programs/p1',
      payload: { status: 'archived' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().program.status).toBe('archived')
    await app.close()
  })

  it('rejects a PATCH that is not an archive', async () => {
    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/v1/programs/p1',
      payload: { status: 'active' },
    })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('sets training maxes from 1RMs via PATCH (TM = 90% of 1RM)', async () => {
    userProgram.findFirst.mockResolvedValue(
      makeProgram({ templateId: '531_bbb', progressionScheme: 'percentage' }),
    )
    userProgram.update.mockImplementation(async ({ data }: { data: Record<string, unknown> }) =>
      makeProgram({ templateId: '531_bbb', ...data }),
    )
    const app = await buildApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/v1/programs/p1',
      payload: { oneRepMaxes: { Squat: 200 } },
    })
    expect(res.statusCode).toBe(200)
    const call = userProgram.update.mock.calls[0][0] as { data: { stateJson: { tm: Record<string, number> } } }
    expect(call.data.stateJson.tm.Squat).toBe(180)
    await app.close()
  })

  it('400s a PATCH with neither status nor oneRepMaxes', async () => {
    const app = await buildApp()
    const res = await app.inject({ method: 'PATCH', url: '/v1/programs/p1', payload: {} })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('deletes via DELETE', async () => {
    userProgram.findFirst.mockResolvedValue(makeProgram())
    userProgram.delete.mockResolvedValue(makeProgram())
    const app = await buildApp()
    const res = await app.inject({ method: 'DELETE', url: '/v1/programs/p1' })
    expect(res.statusCode).toBe(204)
    expect(userProgram.delete).toHaveBeenCalledWith({ where: { id: 'p1' } })
    await app.close()
  })
})
