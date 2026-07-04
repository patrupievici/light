import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import * as crypto from 'crypto'
import { OAuth2Client } from 'google-auth-library'
import bcrypt from 'bcryptjs'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { sendPasswordResetEmail } from '../services/mail.service'

const SignupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
  displayName: z.string().min(1).max(50).optional(),
})

const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
})

const GoogleAuthSchema = z.object({
  idToken: z.string().min(1),
})

const RefreshSchema = z.object({
  refreshToken: z.string(),
})

const ChangePasswordSchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: z.string().min(8).max(128),
})

const AttachEmailSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
  displayName: z.string().max(80).optional(),
})

const ForgotPasswordSchema = z.object({
  email: z.string().email(),
})

const ResetPasswordSchema = z.object({
  email: z.string().email(),
  code: z.string().regex(/^\d{6}$/),
  new_password: z.string().min(8).max(128),
})

const SALT_ROUNDS = 12

// ── Stateless password-reset codes ───────────────────────────────────────────
// No DB table: the 6-digit code is an HMAC over (userId, current passwordHash,
// time window), keyed with JWT_SECRET. Properties:
//   • time-boxed  — window = floor(now / 15min); verify accepts the current and
//     previous window, so a code lives 15–30 minutes;
//   • single-use  — the CURRENT password hash is part of the HMAC input, so the
//     moment the password changes every outstanding code is invalidated;
//   • unforgeable — deriving a code requires JWT_SECRET (server-only).

const RESET_WINDOW_MS = 15 * 60 * 1000

export function resetCodeWindow(nowMs: number = Date.now()): number {
  return Math.floor(nowMs / RESET_WINDOW_MS)
}

/** Derive the 6-digit reset code for a given time window (HOTP-style truncation). */
export function resetCodeForWindow(
  userId: string,
  passwordHash: string,
  window: number,
): string {
  const secret = process.env.JWT_SECRET ?? ''
  const digest = crypto
    .createHmac('sha256', secret)
    .update(`pwreset:${userId}:${passwordHash}:${window}`)
    .digest()
  // Dynamic truncation (RFC 4226 style): 31-bit slice → 6 decimal digits.
  const offset = digest[digest.length - 1] & 0x0f
  const bin =
    ((digest[offset] & 0x7f) << 24) |
    (digest[offset + 1] << 16) |
    (digest[offset + 2] << 8) |
    digest[offset + 3]
  return (bin % 1_000_000).toString().padStart(6, '0')
}

/** Timing-safe check of a submitted code against the current AND previous window. */
function verifyResetCode(userId: string, passwordHash: string, code: string): boolean {
  const now = resetCodeWindow()
  let valid = false
  for (const window of [now, now - 1]) {
    const expected = resetCodeForWindow(userId, passwordHash, window)
    // Both buffers are always 6 bytes (zod enforces /^\d{6}$/ on the input).
    if (crypto.timingSafeEqual(Buffer.from(code), Buffer.from(expected))) {
      valid = true // no early exit — keep comparisons constant-count
    }
  }
  return valid
}

/**
 * Reject sign-in for an account in the soft-delete grace window. Returns true
 * (and sends a 403 ACCOUNT_DELETED) when the user is soft-deleted, so callers
 * just `if (rejectIfSoftDeleted(...)) return`.
 *
 * This guard runs ALWAYS (not flag-gated): it is a behavior-preserving no-op
 * for active accounts because softDeletedAt is null and status="active" for
 * everyone until the opt-in soft-delete flag is turned on. We key off BOTH
 * status="deleted" and softDeletedAt being set so a partially-applied state
 * still blocks login. (status "disabled" keeps its existing ACCOUNT_DISABLED
 * handling elsewhere.)
 */
function rejectIfSoftDeleted(
  user: { status: string; softDeletedAt: Date | null } | null | undefined,
  reply: { code: (n: number) => { send: (b: unknown) => unknown } },
  requestId: string,
): boolean {
  if (!user) return false
  if (user.status === 'deleted' || user.softDeletedAt != null) {
    reply.code(403).send({
      error: 'ACCOUNT_DELETED',
      message: 'Contul a fost șters.',
      requestId,
    })
    return true
  }
  return false
}

async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS)
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash)
}

function generateRefreshToken(): string {
  return crypto.randomBytes(64).toString('hex')
}

// Per-route rate limiting for auth endpoints (CLAUDE.md: "rate limiting pe
// auth endpoints (per IP + per email)"). The global limiter (100/min per IP)
// is too loose for credential endpoints, so these get a tight 8/min bucket
// keyed on email+IP to throttle credential-stuffing without letting one IP
// lock out unrelated emails (and vice versa). Falls back to IP-only when the
// email is absent or the body is unparsable.
const AUTH_RATE_LIMIT = { max: 8, timeWindow: '1 minute' } as const

function emailIpKeyGenerator(request: { ip: string; body?: unknown }): string {
  const body = request.body
  let email: string | null = null
  if (body && typeof body === 'object' && 'email' in body) {
    const value = (body as { email?: unknown }).email
    if (typeof value === 'string' && value.length > 0) {
      email = value.toLowerCase()
    }
  }
  return email ? `${request.ip}:${email}` : request.ip
}

async function issueSession(
  app: FastifyInstance,
  userId: string,
  email: string,
): Promise<{ accessToken: string; refreshToken: string }> {
  const accessToken = app.jwt.sign(
    { userId, email },
    { expiresIn: process.env.JWT_EXPIRES_IN ?? '15m' },
  )

  const rawRefreshToken = generateRefreshToken()
  const tokenHash = crypto.createHash('sha256').update(rawRefreshToken).digest('hex')
  const expiresAt = new Date()
  expiresAt.setDate(expiresAt.getDate() + Number(process.env.REFRESH_TOKEN_EXPIRES_DAYS ?? 30))

  await prisma.refreshToken.create({
    data: { userId, tokenHash, expiresAt },
  })

  return { accessToken, refreshToken: rawRefreshToken }
}

export async function authRoutes(app: FastifyInstance) {
  // POST /v1/auth/change-password - email/password accounts only.
  app.post(
    '/change-password',
    {
      preHandler: authenticate,
      config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
    },
    async (request, reply) => {
      const parsed = ChangePasswordSchema.safeParse(request.body)
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'The new password must contain 8-128 characters.',
          requestId: request.id,
        })
      }
      const { userId } = request.user
      const identity = await prisma.authIdentity.findFirst({
        where: { userId, provider: 'email' },
      })
      if (!identity?.passwordHash) {
        return reply.code(409).send({
          error: 'PASSWORD_NOT_AVAILABLE',
          message: 'This account signs in through an external provider.',
          requestId: request.id,
        })
      }
      const valid = await verifyPassword(parsed.data.currentPassword, identity.passwordHash)
      if (!valid) {
        return reply.code(403).send({
          error: 'CURRENT_PASSWORD_INVALID',
          message: 'The current password is incorrect.',
          requestId: request.id,
        })
      }
      await prisma.$transaction([
        prisma.authIdentity.update({
          where: { id: identity.id },
          data: { passwordHash: await hashPassword(parsed.data.newPassword) },
        }),
        prisma.refreshToken.deleteMany({ where: { userId } }),
      ])
      return reply.send({ ok: true })
    },
  )

  // POST /v1/auth/attach-email — give an instant (unsecured) account a real,
  // recoverable email + password. New users enter the app on an auto-created
  // account (guest_…@guest.zvelt.app); this replaces that placeholder identity
  // with real credentials so the account can be recovered on another device.
  // Without it, signing out an unsecured account orphaned all its data.
  app.post(
    '/attach-email',
    {
      preHandler: authenticate,
      config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
    },
    async (request, reply) => {
      const parsed = AttachEmailSchema.safeParse(request.body)
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'Enter a valid email and a password of 8-128 characters.',
          requestId: request.id,
        })
      }
      const { userId } = request.user
      const { email, password, displayName } = parsed.data

      // The email must be free (or already belong to THIS account — idempotent).
      const taken = await prisma.authIdentity.findFirst({
        where: { provider: 'email', email },
      })
      if (taken && taken.userId !== userId) {
        return reply.code(409).send({
          error: 'EMAIL_TAKEN',
          message: 'This email is already in use.',
          requestId: request.id,
        })
      }

      const passwordHash = await hashPassword(password)
      const existing = await prisma.authIdentity.findFirst({
        where: { userId, provider: 'email' },
      })

      await prisma.$transaction(async (tx) => {
        if (existing) {
          // Replace the placeholder guest identity with real credentials.
          await tx.authIdentity.update({
            where: { id: existing.id },
            data: { email, providerSubject: email, passwordHash },
          })
        } else {
          await tx.authIdentity.create({
            data: { userId, provider: 'email', providerSubject: email, email, passwordHash },
          })
        }
        if (displayName) {
          const profile = await tx.userProfile.findUnique({ where: { userId } })
          if (profile && (profile.displayName == null || profile.displayName === '')) {
            await tx.userProfile.update({ where: { userId }, data: { displayName } })
          }
        }
      })

      return reply.send({ ok: true, email })
    },
  )

  // POST /v1/auth/signup
  app.post(
    '/signup',
    { config: { rateLimit: { ...AUTH_RATE_LIMIT, keyGenerator: emailIpKeyGenerator } } },
    async (request, reply) => {
    const parsed = SignupSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const { email, password, displayName } = parsed.data

    const existing = await prisma.authIdentity.findFirst({
      where: { provider: 'email', email },
    })
    if (existing) {
      return reply.code(409).send({
        error: 'EMAIL_TAKEN',
        message: 'Acest email este deja folosit',
        requestId: request.id,
      })
    }

    const passwordHash = await hashPassword(password)

    const user = await prisma.$transaction(async (tx) => {
      const newUser = await tx.user.create({ data: {} })

      await tx.authIdentity.create({
        data: {
          userId: newUser.id,
          provider: 'email',
          providerSubject: email,
          email,
          passwordHash,
        },
      })

      await tx.userProfile.create({
        data: {
          userId: newUser.id,
          displayName: displayName ?? null,
        },
      })

      await tx.wallet.create({ data: { userId: newUser.id } })

      return newUser
    })

    const { accessToken, refreshToken } = await issueSession(app, user.id, email)

    await prisma.analyticsEvent.create({
      data: { userId: user.id, eventName: 'onboarding_started' },
    })

    return reply.code(201).send({
      accessToken,
      refreshToken,
      user: { id: user.id, email },
    })
    },
  )

  // POST /v1/auth/login
  app.post(
    '/login',
    { config: { rateLimit: { ...AUTH_RATE_LIMIT, keyGenerator: emailIpKeyGenerator } } },
    async (request, reply) => {
    const parsed = LoginSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
      })
    }

    const { email, password } = parsed.data

    const identity = await prisma.authIdentity.findFirst({
      where: { provider: 'email', email },
      include: { user: true },
    })

    if (!identity || !identity.passwordHash) {
      return reply.code(401).send({
        error: 'INVALID_CREDENTIALS',
        message: 'Email sau parola incorecta',
        requestId: request.id,
      })
    }

    const passwordOk = await verifyPassword(password, identity.passwordHash)
    if (!passwordOk) {
      return reply.code(401).send({
        error: 'INVALID_CREDENTIALS',
        message: 'Email sau parola incorecta',
        requestId: request.id,
      })
    }

    // Soft-deleted accounts (grace window) get a stable ACCOUNT_DELETED code so
    // the client can distinguish them from a plain disabled account.
    if (rejectIfSoftDeleted(identity.user, reply, request.id)) return

    if (identity.user.status !== 'active') {
      return reply.code(403).send({
        error: 'ACCOUNT_DISABLED',
        message: 'Contul este dezactivat',
        requestId: request.id,
      })
    }

    const { accessToken, refreshToken } = await issueSession(app, identity.userId, email)

    return reply.send({
      accessToken,
      refreshToken,
      user: { id: identity.userId, email },
    })
    },
  )

  // POST /v1/auth/password/forgot — request a reset code by email.
  // ALWAYS answers 200 with the same generic message so account existence is
  // never leaked. Tight limit (3 / 15 min, keyed IP+email like login/signup)
  // because each request can trigger an outbound email.
  app.post(
    '/password/forgot',
    {
      config: {
        rateLimit: {
          max: 3,
          timeWindow: '15 minutes',
          keyGenerator: emailIpKeyGenerator,
        },
      },
    },
    async (request, reply) => {
      const parsed = ForgotPasswordSchema.safeParse(request.body)
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'Date invalide',
          requestId: request.id,
        })
      }

      const { email } = parsed.data

      const identity = await prisma.authIdentity.findFirst({
        where: { provider: 'email', email },
        include: { user: true },
      })

      // Only email+password accounts in good standing get a code; every other
      // case still falls through to the same generic 200 below.
      const eligible =
        identity?.passwordHash &&
        identity.user.status === 'active' &&
        identity.user.softDeletedAt == null

      if (eligible) {
        const code = resetCodeForWindow(
          identity.userId,
          identity.passwordHash!,
          resetCodeWindow(),
        )
        // Best-effort by design: the mail service never throws, and even if it
        // did we must not turn it into a signal about account existence.
        await sendPasswordResetEmail(email, code).catch(() => {})
      }

      return reply.send({
        ok: true,
        message: 'If that email exists, we sent a code.',
      })
    },
  )

  // POST /v1/auth/password/reset — set a new password using the emailed code.
  // 5 attempts / 15 min per IP+email keeps brute force of a 6-digit code far
  // below feasibility (codes also rotate every 15 minutes).
  app.post(
    '/password/reset',
    {
      config: {
        rateLimit: {
          max: 5,
          timeWindow: '15 minutes',
          keyGenerator: emailIpKeyGenerator,
        },
      },
    },
    async (request, reply) => {
      const parsed = ResetPasswordSchema.safeParse(request.body)
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'VALIDATION_ERROR',
          message: 'The new password must contain 8-128 characters.',
          requestId: request.id,
          details: parsed.error.flatten(),
        })
      }

      const { email, code, new_password } = parsed.data

      const identity = await prisma.authIdentity.findFirst({
        where: { provider: 'email', email },
        include: { user: true },
      })

      // Unknown email, provider-only account, or deleted/disabled user all
      // collapse into the same INVALID_CODE as a wrong code — no enumeration.
      const eligible =
        identity?.passwordHash &&
        identity.user.status === 'active' &&
        identity.user.softDeletedAt == null

      if (!eligible || !verifyResetCode(identity!.userId, identity!.passwordHash!, code)) {
        return reply.code(400).send({
          error: 'INVALID_CODE',
          message: 'The code is incorrect or has expired.',
          requestId: request.id,
        })
      }

      // Same pattern as change-password: swap the hash and revoke every
      // refresh token so stolen sessions die with the old password. Changing
      // the hash also invalidates all outstanding reset codes (see HMAC input).
      await prisma.$transaction([
        prisma.authIdentity.update({
          where: { id: identity!.id },
          data: { passwordHash: await hashPassword(new_password) },
        }),
        prisma.refreshToken.deleteMany({ where: { userId: identity!.userId } }),
      ])

      return reply.send({ ok: true })
    },
  )

  // POST /v1/auth/google — login/signup with Google ID token.
  // No email in the request body (just an idToken), so this one is keyed
  // per-IP only via the default key generator.
  app.post(
    '/google',
    { config: { rateLimit: { ...AUTH_RATE_LIMIT } } },
    async (request, reply) => {
    const parsed = GoogleAuthSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'idToken lipsa',
        requestId: request.id,
      })
    }

    const clientId = process.env.GOOGLE_CLIENT_ID
    if (!clientId) {
      return reply.code(500).send({
        error: 'CONFIG_ERROR',
        message: 'Google Sign-In nu este configurat (GOOGLE_CLIENT_ID)',
        requestId: request.id,
      })
    }

    const client = new OAuth2Client(clientId)
    let payload: { sub: string; email?: string; name?: string; picture?: string }
    try {
      const ticket = await client.verifyIdToken({
        idToken: parsed.data.idToken,
        audience: clientId,
      })
      payload = ticket.getPayload()!
      if (!payload?.sub) throw new Error('Invalid payload')
    } catch {
      return reply.code(401).send({
        error: 'INVALID_GOOGLE_TOKEN',
        message: 'Token Google invalid sau expirat',
        requestId: request.id,
      })
    }

    const googleSub = payload.sub
    const email = payload.email ?? null
    const displayName = payload.name ?? null
    // `picture` is Google's profile photo URL (stable across logins for the
    // same Google account). Used by the app's avatar widget so users don't
    // have to upload anything manually.
    const photoUrl = payload.picture ?? null

    let identity = await prisma.authIdentity.findFirst({
      where: { provider: 'google', providerSubject: googleSub },
      include: { user: true },
    })

    if (!identity) {
      await prisma.$transaction(async (tx) => {
        const newUser = await tx.user.create({ data: {} })
        await tx.authIdentity.create({
          data: {
            userId: newUser.id,
            provider: 'google',
            providerSubject: googleSub,
            email,
          },
        })
        await tx.userProfile.create({
          data: {
            userId: newUser.id,
            displayName,
            photoUrl,
          },
        })
        await tx.wallet.create({ data: { userId: newUser.id } })
      })
      identity = await prisma.authIdentity.findUnique({
        where: {
          provider_providerSubject: {
            provider: 'google',
            providerSubject: googleSub,
          },
        },
        include: { user: true },
      })
    }

    if (!identity) {
      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Identitatea Google nu a putut fi încărcată',
        requestId: request.id,
      })
    }

    if (rejectIfSoftDeleted(identity.user, reply, request.id)) return

    if (identity.user.status !== 'active') {
      return reply.code(403).send({
        error: 'ACCOUNT_DISABLED',
        message: 'Contul este dezactivat',
        requestId: request.id,
      })
    }

    // Refresh the cached Google photo URL on every login so users who change
    // their Google profile picture see it update in the app at next sign-in.
    // Only overwrite when Google gave us a non-null URL.
    if (photoUrl) {
      await prisma.userProfile
        .update({
          where: { userId: identity.userId },
          data: { photoUrl },
        })
        .catch(() => {})
    }

    const { accessToken, refreshToken } = await issueSession(
      app,
      identity.userId,
      identity.email ?? '',
    )

    return reply.send({
      accessToken,
      refreshToken,
      user: { id: identity.userId, email: identity.email },
    })
    },
  )

  // POST /v1/auth/refresh.
  // No email in the request body (just a refreshToken), so keyed per-IP only.
  app.post(
    '/refresh',
    { config: { rateLimit: { ...AUTH_RATE_LIMIT } } },
    async (request, reply) => {
    const parsed = RefreshSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'refreshToken lipsa',
        requestId: request.id,
      })
    }

    const tokenHash = crypto
      .createHash('sha256')
      .update(parsed.data.refreshToken)
      .digest('hex')

    const stored = await prisma.refreshToken.findUnique({ where: { tokenHash } })

    if (!stored || stored.expiresAt < new Date()) {
      return reply.code(401).send({
        error: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh token invalid sau expirat',
        requestId: request.id,
      })
    }

    if (stored.usedAt) {
      // Grace window: a benign client race or a lost-response retry can re-send
      // a token whose rotation already succeeded server-side. Only treat reuse
      // OLDER than the grace window as a genuine compromise (nuke all sessions);
      // within the window, fall through and re-issue so we don't log out a
      // legitimate user. The client also single-flights refreshes, so this is
      // defense-in-depth.
      const GRACE_MS = 10_000
      if (Date.now() - stored.usedAt.getTime() > GRACE_MS) {
        await prisma.refreshToken.deleteMany({ where: { userId: stored.userId } })
        return reply.code(401).send({
          error: 'TOKEN_REUSE_DETECTED',
          message: 'Sesiune compromisa. Autentifica-te din nou.',
          requestId: request.id,
        })
      }
    }

    // Block refresh for soft-deleted accounts (grace window). A soft-delete
    // revokes refresh tokens, but a token issued elsewhere / a race could still
    // arrive — this is the authoritative gate. No-op for active accounts.
    const refreshUser = await prisma.user.findUnique({
      where: { id: stored.userId },
      select: { status: true, softDeletedAt: true },
    })
    if (rejectIfSoftDeleted(refreshUser, reply, request.id)) return

    await prisma.refreshToken.update({
      where: { tokenHash },
      data: { usedAt: new Date() },
    })

    const identity = await prisma.authIdentity.findFirst({
      where: { userId: stored.userId },
    })

    const { accessToken, refreshToken } = await issueSession(
      app,
      stored.userId,
      identity?.email ?? '',
    )

    return reply.send({ accessToken, refreshToken })
    },
  )

  // POST /v1/auth/logout
  app.post('/logout', { preHandler: authenticate }, async (request, reply) => {
    const user = request.user
    await prisma.refreshToken.deleteMany({ where: { userId: user.userId } })
    return reply.code(204).send()
  })

  // DELETE /v1/auth/delete-account — anonimizare completă GDPR
  app.delete('/delete-account', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    await prisma.$transaction(async (tx) => {
      await tx.refreshToken.deleteMany({ where: { userId } })

      await tx.postLike.deleteMany({ where: { userId } })
      await tx.postComment.deleteMany({ where: { userId } })
      await tx.post.deleteMany({ where: { userId } })

      const workouts = await tx.workout.findMany({ where: { userId }, select: { id: true } })
      const workoutIds = workouts.map((w) => w.id)
      if (workoutIds.length > 0) {
        await tx.workoutSet.deleteMany({ where: { workoutExercise: { workoutId: { in: workoutIds } } } })
        await tx.workoutExercise.deleteMany({ where: { workoutId: { in: workoutIds } } })
        await tx.workout.deleteMany({ where: { userId } })
      }

      await tx.nutritionLogDay.deleteMany({ where: { userId } }).catch(() => {})
      await tx.nutritionPlanDay.deleteMany({ where: { userId } }).catch(() => {})

      await tx.friendship.deleteMany({ where: { OR: [{ userId }, { friendUserId: userId }] } }).catch(() => {})
      await tx.userExerciseRank.deleteMany({ where: { userId } }).catch(() => {})
      // UserAchievement + UserSeasonStat have NO onDelete: Cascade, so leaving
      // them blocks user.delete() with P2003 (FK violation). Every real user
      // unlocks at least `first_workout`, so erasure was failing for everyone.
      await tx.userAchievement.deleteMany({ where: { userId } }).catch(() => {})
      await tx.userSeasonStat.deleteMany({ where: { userId } }).catch(() => {})
      await tx.walletTransaction.deleteMany({ where: { wallet: { userId } } }).catch(() => {})
      await tx.wallet.deleteMany({ where: { userId } }).catch(() => {})
      await tx.analyticsEvent.deleteMany({ where: { userId } }).catch(() => {})

      await tx.authIdentity.deleteMany({ where: { userId } })
      await tx.userProfile.deleteMany({ where: { userId } })
      await tx.user.delete({ where: { id: userId } })
    })

    return reply.code(204).send()
  })
}
