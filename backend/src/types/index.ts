import { FastifyRequest } from 'fastify'

export interface JwtPayload {
  userId: string
  email: string
}

export interface AuthenticatedRequest extends FastifyRequest {
  user: JwtPayload
}

export interface ApiError {
  error: string
  message: string
  requestId: string
  details?: unknown
}

export type SetTag = 'WORK' | 'WARMUP' | 'DROP'
export type Visibility = 'private' | 'friends' | 'public'
export type UnitSystem = 'metric' | 'imperial'
