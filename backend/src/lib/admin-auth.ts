import crypto from 'node:crypto'

/**
 * True when the supplied `X-Admin-Token` header value matches the configured
 * `ADMIN_TOKEN` env var. Constant-time compare to avoid a timing side-channel;
 * `timingSafeEqual` requires equal-length buffers, so guard on length first (an
 * unequal length is not secret and rejects immediately). Returns false when
 * `ADMIN_TOKEN` is unset or too short so missing config never authorizes.
 */
export function isAdminTokenValid(headerValue: unknown): boolean {
  const configured = process.env.ADMIN_TOKEN
  if (!configured || configured.length < 8) return false
  if (typeof headerValue !== 'string') return false
  const a = Buffer.from(headerValue)
  const b = Buffer.from(configured)
  if (a.length !== b.length) return false
  return crypto.timingSafeEqual(a, b)
}
