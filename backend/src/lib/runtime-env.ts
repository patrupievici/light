/**
 * Hosting providers do not always set NODE_ENV. Treat an unknown environment
 * as production-like so security controls and client-safe errors fail closed.
 */
export function isProductionLike(nodeEnv: string | undefined): boolean {
  return nodeEnv !== 'development' && nodeEnv !== 'test'
}
