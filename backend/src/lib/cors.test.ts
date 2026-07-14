import { describe, it, expect } from 'vitest'
import Fastify from 'fastify'
import cors from '@fastify/cors'
import { parseCorsOrigins, buildCorsOrigin } from './cors'

describe('parseCorsOrigins', () => {
  it('returns [] for empty / nullish input', () => {
    expect(parseCorsOrigins(undefined)).toEqual([])
    expect(parseCorsOrigins(null)).toEqual([])
    expect(parseCorsOrigins('')).toEqual([])
    expect(parseCorsOrigins('  ,  ,')).toEqual([])
  })

  it('splits, trims, and strips trailing slashes', () => {
    expect(parseCorsOrigins(' https://app.zvelt.com , https://zvelt.app/ ')).toEqual([
      'https://app.zvelt.com',
      'https://zvelt.app',
    ])
  })

  it('de-duplicates', () => {
    expect(parseCorsOrigins('https://a.com,https://a.com/')).toEqual(['https://a.com'])
  })
})

describe('buildCorsOrigin', () => {
  it('empty allowlist always fails closed', () => {
    expect(buildCorsOrigin(undefined)).toBe(false)
    expect(buildCorsOrigin('')).toBe(false)
  })

  it('non-empty allowlist → callback that allows listed origins only', () => {
    const fn = buildCorsOrigin('https://app.zvelt.com')
    expect(typeof fn).toBe('function')
    const origin = fn as (o: string | undefined, cb: (e: Error | null, allow: boolean) => void) => void

    const allow = (o: string | undefined) => {
      let result = false
      origin(o, (_e, a) => {
        result = a
      })
      return result
    }

    expect(allow('https://app.zvelt.com')).toBe(true)
    expect(allow('https://app.zvelt.com/')).toBe(true) // trailing slash normalized
    expect(allow('https://evil.com')).toBe(false)
    // No Origin header (native mobile / server-to-server) → allowed.
    expect(allow(undefined)).toBe(true)
  })

  it('does not emit an allow-origin header for an untrusted browser origin', async () => {
    const app = Fastify()
    await app.register(cors, { origin: buildCorsOrigin(undefined) })
    app.get('/health', async () => ({ status: 'ok' }))

    const response = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: 'https://evil.example' },
    })

    expect(response.statusCode).toBe(200)
    expect(response.headers['access-control-allow-origin']).toBeUndefined()
    await app.close()
  })
})
