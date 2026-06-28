import { describe, it, expect, vi, beforeEach } from 'vitest'

const deleteMany = vi.fn()
vi.mock('../lib/prisma', () => ({
  prisma: {
    notificationSentLog: { deleteMany: (...a: unknown[]) => deleteMany(...a) },
  },
}))

import { runNotificationLogCleanup } from './notification-log-cleanup.service'

const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } as never

beforeEach(() => {
  deleteMany.mockReset()
  deleteMany.mockResolvedValue({ count: 0 })
})

describe('runNotificationLogCleanup', () => {
  it('deletes claims older than the retention window (default 90 days)', async () => {
    deleteMany.mockResolvedValue({ count: 42 })

    const res = await runNotificationLogCleanup(log)

    expect(res).toEqual({ deleted: 42 })
    const where = deleteMany.mock.calls[0][0].where
    expect(where.createdAt).toHaveProperty('lt')
    expect(where.createdAt.lt).toBeInstanceOf(Date)
    // ~90 days back from now (allow a generous slack for test runtime).
    const ageDays = (Date.now() - (where.createdAt.lt as Date).getTime()) / 86_400_000
    expect(ageDays).toBeGreaterThan(89)
    expect(ageDays).toBeLessThan(91)
  })

  it('honours a custom retention window', async () => {
    await runNotificationLogCleanup(log, 30)
    const cutoff = deleteMany.mock.calls[0][0].where.createdAt.lt as Date
    const ageDays = (Date.now() - cutoff.getTime()) / 86_400_000
    expect(ageDays).toBeGreaterThan(29)
    expect(ageDays).toBeLessThan(31)
  })
})
