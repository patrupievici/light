import { describe, it, expect, vi, beforeEach } from 'vitest'

// ── Mocks ───────────────────────────────────────────────────────────────────
const userFindMany = vi.fn()
vi.mock('../lib/prisma', () => ({
  prisma: {
    user: { findMany: (...a: unknown[]) => userFindMany(...a) },
  },
}))

const eraseUser = vi.fn()
vi.mock('../routes/gdpr', () => ({
  eraseUser: (...a: unknown[]) => eraseUser(...a),
}))

import { processScheduledErasures, runSoftDeleteSweep } from './soft-delete-cron.service'

const logSpies = {
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
}
const log = logSpies as never

beforeEach(() => {
  userFindMany.mockReset()
  eraseUser.mockReset()
  Object.values(logSpies).forEach((fn) => fn.mockReset())
})

describe('processScheduledErasures — due soft-deleted accounts', () => {
  it('erases every due user via eraseUser', async () => {
    userFindMany.mockResolvedValue([{ id: 'a' }, { id: 'b' }])
    eraseUser.mockResolvedValue(undefined)

    const summary = await processScheduledErasures(log)

    expect(summary).toMatchObject({ scanned: 2, erased: 2, failed: 0 })
    expect(eraseUser).toHaveBeenCalledTimes(2)
    expect(eraseUser).toHaveBeenCalledWith('a', log)
    expect(eraseUser).toHaveBeenCalledWith('b', log)
  })

  it('only selects soft-deleted users whose hard-erase time is due', async () => {
    userFindMany.mockResolvedValue([])
    await processScheduledErasures(log)

    const where = userFindMany.mock.calls[0][0].where
    expect(where.softDeletedAt).toEqual({ not: null })
    expect(where.scheduledHardEraseAt).toHaveProperty('lte')
    expect(where.scheduledHardEraseAt.lte).toBeInstanceOf(Date)
  })

  it('does nothing (no eraseUser) when no accounts are due', async () => {
    userFindMany.mockResolvedValue([])
    const summary = await processScheduledErasures(log)

    expect(summary).toMatchObject({ scanned: 0, erased: 0, failed: 0 })
    expect(eraseUser).not.toHaveBeenCalled()
  })

  it('is best-effort: a single erase failure does not abort the batch', async () => {
    userFindMany.mockResolvedValue([{ id: 'a' }, { id: 'b' }, { id: 'c' }])
    eraseUser
      .mockResolvedValueOnce(undefined)
      .mockRejectedValueOnce(new Error('db down'))
      .mockResolvedValueOnce(undefined)

    const summary = await processScheduledErasures(log)

    expect(summary).toMatchObject({ scanned: 3, erased: 2, failed: 1 })
    // All three were attempted despite the middle failure.
    expect(eraseUser).toHaveBeenCalledTimes(3)
    expect(logSpies.error).toHaveBeenCalled()
  })
})

describe('runSoftDeleteSweep — overlap guard', () => {
  it('skips a concurrent sweep while one is already running', async () => {
    let resolveErase: () => void = () => {}
    userFindMany.mockResolvedValue([{ id: 'a' }])
    eraseUser.mockImplementation(
      () => new Promise<void>((res) => { resolveErase = res }),
    )

    const first = runSoftDeleteSweep(log)
    // Second call while the first is mid-flight must short-circuit.
    const second = await runSoftDeleteSweep(log)
    expect(second).toMatchObject({ skipped: true })

    resolveErase()
    await first
    // After the first finishes, the guard is released and a new sweep runs.
    userFindMany.mockResolvedValue([])
    const third = await runSoftDeleteSweep(log)
    expect(third.skipped).toBe(false)
  })
})
