import '@fastify/jwt'

/**
 * Type the JWT payload so `request.user` is `{ userId, email }` instead of `any`.
 * Lets routes use `request.user.userId` without `(request as any)` casts.
 */
declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: { userId: string; email: string }
    user: { userId: string; email: string }
  }
}
