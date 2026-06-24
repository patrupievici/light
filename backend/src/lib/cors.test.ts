import { describe, it, expect } from 'vitest'
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
  it('empty allowlist + production → false (reject all browser origins)', () => {
    expect(buildCorsOrigin(undefined, 'production')).toBe(false)
  })

  it('empty allowlist + non-production → true (dev convenience)', () => {
    expect(buildCorsOrigin(undefined, 'development')).toBe(true)
  })

  it('non-empty allowlist → callback that allows listed origins only', () => {
    const fn = buildCorsOrigin('https://app.zvelt.com', 'production')
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
})
