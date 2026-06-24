import { describe, it, expect, vi, beforeEach } from 'vitest'

// ── Mocks ───────────────────────────────────────────────────────────────────
const inboxFindUnique = vi.fn()
const inboxFindMany = vi.fn()
const inboxUpdate = vi.fn()

vi.mock('../lib/prisma', () => ({
  prisma: {
    webhookInbox: {
      findUnique: (...a: unknown[]) => inboxFindUnique(...a),
      findMany: (...a: unknown[]) => inboxFindMany(...a),
      update: (...a: unknown[]) => inboxUpdate(...a),
    },
  },
}))

// The import layer is exercised elsewhere; here we only care that the inbox
// drives it and records the right outcome.
const persistTerraDataPayload = vi.fn()
vi.mock('../routes/integrations', () => ({
  persistTerraDataPayload: (...a: unknown[]) => persistTerraDataPayload(...a),
}))

import {
  processInboxItem,
  processPending,
  WEBHOOK_INBOX_CONSTANTS,
} from './webhook-inbox.service'

beforeEach(() => {
  inboxFindUnique.mockReset()
  inboxFindMany.mockReset()
  inboxUpdate.mockReset()
  persistTerraDataPayload.mockReset()
  inboxUpdate.mockResolvedValue({})
})

describe('processInboxItem', () => {
  it('processes a received row and marks it processed with processedAt', async () => {
    inboxFindUnique.mockResolvedValue({ id: 'i1', status: 'received', attempts: 0, payload: { type: 'activity' } })
    persistTerraDataPayload.mockResolvedValue(3)

    const res = await processInboxItem('i1')

    expect(res).toEqual({ status: 'processed', imported: 3 })
    expect(persistTerraDataPayload).toHaveBeenCalledWith({ type: 'activity' }, expect.anything())
    const update = inboxUpdate.mock.calls[0][0] as { where: { id: string }; data: Record<string, unknown> }
    expect(update.where.id).toBe('i1')
    expect(update.data.status).toBe('processed')
    expect(update.data.processedAt).toBeInstanceOf(Date)
    expect(update.data.attempts).toEqual({ increment: 1 })
    expect(update.data.error).toBeNull()
  })

  it('retries a previously failed row', async () => {
    inboxFindUnique.mockResolvedValue({ id: 'i2', status: 'failed', attempts: 1, payload: {} })
    persistTerraDataPayload.mockResolvedValue(0)

    const res = await processInboxItem('i2')
    expect(res).toEqual({ status: 'processed', imported: 0 })
  })

  it('marks the row failed and increments attempts when the import throws', async () => {
    inboxFindUnique.mockResolvedValue({ id: 'i3', status: 'received', attempts: 2, payload: {} })
    persistTerraDataPayload.mockRejectedValue(new Error('boom'))

    const res = await processInboxItem('i3')

    expect(res).toEqual({ status: 'failed', error: 'boom' })
    const update = inboxUpdate.mock.calls[0][0] as { data: Record<string, unknown> }
    expect(update.data.status).toBe('failed')
    expect(update.data.attempts).toEqual({ increment: 1 })
    expect(update.data.error).toBe('boom')
  })

  it('skips a missing row without touching the import layer', async () => {
    inboxFindUnique.mockResolvedValue(null)
    const res = await processInboxItem('nope')
    expect(res).toEqual({ status: 'skipped', reason: 'not_found' })
    expect(persistTerraDataPayload).not.toHaveBeenCalled()
    expect(inboxUpdate).not.toHaveBeenCalled()
  })

  it('skips an already-processed row (idempotent re-trigger)', async () => {
    inboxFindUnique.mockResolvedValue({ id: 'i4', status: 'processed', attempts: 1, payload: {} })
    const res = await processInboxItem('i4')
    expect(res).toEqual({ status: 'skipped', reason: 'already_processed' })
    expect(persistTerraDataPayload).not.toHaveBeenCalled()
  })

  it('skips a row that has hit the max-attempts cap', async () => {
    inboxFindUnique.mockResolvedValue({
      id: 'i5',
      status: 'failed',
      attempts: WEBHOOK_INBOX_CONSTANTS.MAX_ATTEMPTS,
      payload: {},
    })
    const res = await processInboxItem('i5')
    expect(res).toEqual({ status: 'skipped', reason: 'max_attempts' })
    expect(persistTerraDataPayload).not.toHaveBeenCalled()
  })

  it('never throws even if the failure bookkeeping write also fails', async () => {
    inboxFindUnique.mockResolvedValue({ id: 'i6', status: 'received', attempts: 0, payload: {} })
    persistTerraDataPayload.mockRejectedValue(new Error('import down'))
    inboxUpdate.mockRejectedValue(new Error('db down'))

    const res = await processInboxItem('i6')
    expect(res).toEqual({ status: 'failed', error: 'import down' })
  })
})

describe('processPending', () => {
  it('drains pending rows oldest-first and tallies outcomes', async () => {
    inboxFindMany.mockResolvedValue([{ id: 'a' }, { id: 'b' }, { id: 'c' }])
    inboxFindUnique
      .mockResolvedValueOnce({ id: 'a', status: 'received', attempts: 0, payload: {} })
      .mockResolvedValueOnce({ id: 'b', status: 'failed', attempts: 1, payload: {} })
      .mockResolvedValueOnce(null)
    persistTerraDataPayload
      .mockResolvedValueOnce(1)
      .mockRejectedValueOnce(new Error('nope'))

    const res = await processPending()

    expect(res).toEqual({ picked: 3, processed: 1, failed: 1, skipped: 1 })
    // Only received/failed rows under the attempt cap, oldest first.
    const where = (inboxFindMany.mock.calls[0][0] as { where: any; orderBy: any }).where
    expect(where.status).toEqual({ in: ['received', 'failed'] })
    expect(where.attempts).toEqual({ lt: WEBHOOK_INBOX_CONSTANTS.MAX_ATTEMPTS })
    expect((inboxFindMany.mock.calls[0][0] as { orderBy: any }).orderBy).toEqual({ receivedAt: 'asc' })
  })

  it('returns a zeroed tally if the scan query fails', async () => {
    inboxFindMany.mockRejectedValue(new Error('relation does not exist'))
    const res = await processPending()
    expect(res).toEqual({ picked: 0, processed: 0, failed: 0, skipped: 0 })
  })

  it('honours a custom batch limit', async () => {
    inboxFindMany.mockResolvedValue([])
    await processPending({ limit: 10 })
    expect((inboxFindMany.mock.calls[0][0] as { take: number }).take).toBe(10)
  })
})
