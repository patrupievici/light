import { FastifyRequest, FastifyReply } from 'fastify'
import { prisma } from '../lib/prisma'

export async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  try {
    await request.jwtVerify()
  } catch {
    return reply.code(401).send({
      error: 'UNAUTHORIZED',
      message: 'Token invalid sau expirat',
      requestId: request.id,
    })
  }

  // A valid JWT is not enough: the account may have been disabled, soft
  // deleted, or hard-erased after the token was issued. Gate every protected
  // request on the current account state so account deletion and administrative
  // suspension revoke access immediately instead of waiting for JWT expiry.
  const account = await prisma.user.findUnique({
    where: { id: request.user.userId },
    select: { status: true },
  })
  if (!account || account.status !== 'active') {
    return reply.code(401).send({
      error: 'UNAUTHORIZED',
      message: 'Token invalid sau expirat',
      requestId: request.id,
    })
  }
}
