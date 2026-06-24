/**
 * CORS origin allowlist.
 *
 * The mobile app talks to the API over native HTTP (no `Origin` header), so the
 * default for production is an EMPTY allowlist — every browser/cross-origin
 * request is rejected unless explicitly allowed via `CORS_ORIGINS`.
 *
 * `CORS_ORIGINS` is a comma-separated list, e.g.
 *   CORS_ORIGINS=https://app.zvelt.com,https://zvelt.app
 *
 * In non-production, if `CORS_ORIGINS` is unset we allow all origins for local
 * developer tooling. Setting `CORS_ORIGINS` always wins, in any environment.
 */

export type CorsOriginOption =
  | boolean
  | ((origin: string | undefined, cb: (err: Error | null, allow: boolean) => void) => void)

/** Parse a comma-separated env value into a clean, de-duplicated allowlist. */
export function parseCorsOrigins(raw: string | undefined | null): string[] {
  if (!raw) return []
  const seen = new Set<string>()
  for (const part of raw.split(',')) {
    const trimmed = part.trim().replace(/\/+$/, '') // strip trailing slashes
    if (trimmed.length > 0) seen.add(trimmed)
  }
  return [...seen]
}

/**
 * Build the `origin` option for @fastify/cors.
 *
 * - allowlist non-empty  → callback that allows requests with no Origin header
 *   (native mobile, server-to-server) and any origin present in the allowlist.
 * - allowlist empty + production → `false` (reject all browser origins).
 * - allowlist empty + non-production → `true` (allow all, dev convenience).
 */
export function buildCorsOrigin(
  rawOrigins: string | undefined | null,
  nodeEnv: string | undefined,
): CorsOriginOption {
  const allowlist = parseCorsOrigins(rawOrigins)

  if (allowlist.length === 0) {
    return nodeEnv === 'production' ? false : true
  }

  return (origin, cb) => {
    // No Origin header → native app / curl / server-to-server. Allow.
    if (!origin) {
      cb(null, true)
      return
    }
    const normalized = origin.replace(/\/+$/, '')
    cb(null, allowlist.includes(normalized))
  }
}
