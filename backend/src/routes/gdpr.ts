import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import * as crypto from 'crypto'
import bcrypt from 'bcryptjs'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { deleteUploadByUrl } from '../lib/post-photo'
import { revokeAllProviderConnections } from './integrations'
import type { FastifyBaseLogger } from 'fastify'

/** Minimal logger shape eraseUser needs for best-effort side-effects. */
type ErasureLogger = Pick<FastifyBaseLogger, 'warn' | 'error'>

/** Fallback logger so eraseUser works when called without a Fastify log. */
const noopLogger: ErasureLogger = {
  warn: () => {},
  error: () => {},
}

/**
 * GDPR / account-management routes mounted under /v1/me.
 *
 *   DELETE /v1/me/account          → right to erasure (hard delete + cascade)
 *   POST   /v1/me/change-password  → change password (requires current)
 *   GET    /v1/me/export-data      → data portability (Art. 20), credentials redacted
 *
 * The mobile client calls DELETE /v1/me/account; this is the canonical route.
 */

const ChangePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8).max(128),
})

const SALT_ROUNDS = 12

/**
 * Soft-delete grace window is OPT-IN and FLAG-GATED. When ZVELT_SOFT_DELETE is
 * exactly "on", DELETE /v1/me/account marks the account deleted + schedules a
 * hard erase 30 days out (recoverable window) instead of erasing immediately.
 * Any other value (incl. unset) keeps the historical immediate-erase behavior
 * EXACTLY, so live behavior is unchanged by default.
 */
function softDeleteEnabled(): boolean {
  return process.env.ZVELT_SOFT_DELETE === 'on'
}

/** Grace window length before a soft-deleted account is hard-erased. */
const SOFT_DELETE_GRACE_DAYS = 30

/**
 * Stable sentinel ("tombstone") user that inherits the erased user's side of any
 * shared DM thread. Fixed UUID so it is created at most once and re-used across
 * every erasure. It owns no profile, no auth identity and no other data — it
 * exists purely so the REMAINING participant's conversation history stays
 * coherent (sender shown as "[deleted user]") instead of vanishing when the
 * real user row is hard-deleted (DM FKs are onDelete: Cascade).
 */
const DELETED_USER_SENTINEL_ID = '00000000-0000-0000-0000-0000000dead00'

/** Body shown in place of an erased user's DM text after anonymization. */
const DELETED_USER_TOMBSTONE = '[deleted user]'

/** Event-name allowlist for export: anything else is reported as a redacted count. */
const EXPORTABLE_EVENT_NAMES = new Set([
  'onboarding_started',
  'workout_started',
  'workout_completed',
  'post_created',
  'rank_calculated',
  'bodyweight_set',
])

/**
 * Hard-delete a user and ALL dependent rows, children-before-parents. Most FK
 * relations are not `onDelete: Cascade`, so we delete explicitly inside one
 * transaction — if any step fails the whole erasure rolls back (no orphans).
 */
async function eraseUser(userId: string, log: ErasureLogger = noopLogger): Promise<void> {
  // Revoke external integrations + scrub remote tokens BEFORE the DB transaction,
  // while the wearable_connections rows (and their external ids) still exist.
  // Best-effort: a stuck/unreachable provider must NEVER block erasure, so this
  // never throws — failures are logged inside the helper and we proceed.
  try {
    await revokeAllProviderConnections(userId, log as FastifyBaseLogger)
  } catch (err) {
    log.warn({ err, userId }, 'eraseUser: provider revoke failed (continuing erasure)')
  }

  // Collect on-disk media URLs BEFORE their rows are deleted (avatars, post
  // photos, story images live under /uploads/* on the server filesystem).
  const [profile, postRows, storyRows] = await Promise.all([
    prisma.userProfile.findUnique({ where: { userId }, select: { photoUrl: true } }),
    prisma.post.findMany({ where: { userId }, select: { imageUrl: true } }),
    prisma.story.findMany({ where: { userId }, select: { imageUrl: true } }),
  ])
  const fileUrls = [
    profile?.photoUrl,
    ...postRows.map((p) => p.imageUrl),
    ...storyRows.map((s) => s.imageUrl),
  ].filter((u): u is string => !!u)

  await prisma.$transaction(async (tx) => {
    // Resolve the user's workout + post ids up front (needed for grandchildren).
    const workouts = await tx.workout.findMany({ where: { userId }, select: { id: true } })
    const workoutIds = workouts.map((w) => w.id)
    const weRows = workoutIds.length
      ? await tx.workoutExercise.findMany({
          where: { workoutId: { in: workoutIds } },
          select: { id: true },
        })
      : []
    const weIds = weRows.map((w) => w.id)
    const posts = await tx.post.findMany({ where: { userId }, select: { id: true } })
    const postIds = posts.map((p) => p.id)

    // ── Set-level children ──
    if (weIds.length) {
      const sets = await tx.workoutSet.findMany({
        where: { workoutExerciseId: { in: weIds } },
        select: { id: true },
      })
      const setIds = sets.map((s) => s.id)
      if (setIds.length) {
        await tx.setEditAudit.deleteMany({ where: { setId: { in: setIds } } })
        await tx.workoutSet.deleteMany({ where: { workoutExerciseId: { in: weIds } } })
      }
    }
    // Audits authored by this user on any set (defensive).
    await tx.setEditAudit.deleteMany({ where: { userId } })

    // ── Post-level children (likes/comments/etc. on the user's posts AND by the user) ──
    if (postIds.length) {
      await tx.postLike.deleteMany({ where: { postId: { in: postIds } } })
      await tx.postComment.deleteMany({ where: { postId: { in: postIds } } })
      await tx.postBookmark.deleteMany({ where: { postId: { in: postIds } } })
      await tx.postHide.deleteMany({ where: { postId: { in: postIds } } })
      await tx.postReport.deleteMany({ where: { postId: { in: postIds } } })
      await tx.postPrivacySetting.deleteMany({ where: { postId: { in: postIds } } })
    }
    // Interactions BY the user on OTHER people's posts.
    await tx.postLike.deleteMany({ where: { userId } })
    await tx.postComment.deleteMany({ where: { userId } })
    await tx.postBookmark.deleteMany({ where: { userId } })
    await tx.postHide.deleteMany({ where: { userId } })
    await tx.postReport.deleteMany({ where: { userId } })

    // Posts must go before workouts (Post.workoutId FK) and before user.
    await tx.post.deleteMany({ where: { userId } })

    // ── Workout tree ──
    if (weIds.length) await tx.workoutExercise.deleteMany({ where: { workoutId: { in: workoutIds } } })
    await tx.workout.deleteMany({ where: { userId } })

    // ── Ranks / seasons ──
    await tx.userExerciseRank.deleteMany({ where: { userId } })
    await tx.userSeasonStat.deleteMany({ where: { userId } })

    // ── Social graph ──
    await tx.friendship.deleteMany({
      where: { OR: [{ userId }, { friendUserId: userId }] },
    })
    await tx.notification.deleteMany({ where: { OR: [{ userId }, { actorId: userId }] } })

    // ── DMs (third-party policy: anonymize, don't destroy the peer's thread) ──
    // We do NOT silently drop the other participant's view. Instead the erased
    // user's authored messages are tombstoned ("[deleted user]") and BOTH the
    // conversation slot and the sent-message authorship are reassigned to a
    // shared sentinel user, so the remaining participant keeps a coherent,
    // readable history. (DM FKs are onDelete: Cascade, so without this reassign
    // the whole conversation + every message would vanish with the user row.)
    const convs = await tx.directConversation.findMany({
      where: { OR: [{ userLowId: userId }, { userHighId: userId }] },
      select: { id: true, userLowId: true, userHighId: true },
    })
    if (convs.length) {
      // Lazily ensure the sentinel exists (idempotent; owns no other data).
      await tx.user.upsert({
        where: { id: DELETED_USER_SENTINEL_ID },
        create: { id: DELETED_USER_SENTINEL_ID, status: 'deleted' },
        update: {},
      })

      for (const conv of convs) {
        const peerId = conv.userLowId === userId ? conv.userHighId : conv.userLowId
        // Self-conversation (both sides the erased user) leaves no third party
        // to preserve — delete it outright.
        if (peerId === userId) {
          await tx.directMessage.deleteMany({ where: { conversationId: conv.id } })
          await tx.directConversation.delete({ where: { id: conv.id } })
          continue
        }

        // Tombstone the erased user's messages, then hand their authorship to
        // the sentinel so the rows survive the user-row cascade.
        await tx.directMessage.updateMany({
          where: { conversationId: conv.id, senderId: userId },
          data: { senderId: DELETED_USER_SENTINEL_ID, body: DELETED_USER_TOMBSTONE },
        })

        // Recompute the (low, high) slot with the sentinel in the erased seat,
        // honouring the lexical low<high invariant the rest of the code relies on.
        const newLow = peerId < DELETED_USER_SENTINEL_ID ? peerId : DELETED_USER_SENTINEL_ID
        const newHigh = peerId < DELETED_USER_SENTINEL_ID ? DELETED_USER_SENTINEL_ID : peerId

        // Guard the @@unique([userLowId, userHighId]) constraint: if a
        // peer↔sentinel conversation somehow already exists, merge messages into
        // it and drop this one rather than violating the constraint.
        const existing = await tx.directConversation.findFirst({
          where: { userLowId: newLow, userHighId: newHigh, NOT: { id: conv.id } },
          select: { id: true },
        })
        if (existing) {
          await tx.directMessage.updateMany({
            where: { conversationId: conv.id },
            data: { conversationId: existing.id },
          })
          await tx.directConversation.delete({ where: { id: conv.id } })
        } else {
          await tx.directConversation.update({
            where: { id: conv.id },
            data: { userLowId: newLow, userHighId: newHigh },
          })
        }
      }
    }

    // ── Wallet / economy ──
    await tx.walletTransaction.deleteMany({ where: { userId } })
    await tx.wallet.deleteMany({ where: { userId } })

    // ── Misc per-user data ──
    await tx.userAchievement.deleteMany({ where: { userId } })
    await tx.userPushToken.deleteMany({ where: { userId } })
    await tx.plannedWorkout.deleteMany({ where: { userId } })
    await tx.routine.deleteMany({ where: { userId } })
    await tx.userBodyMeasurement.deleteMany({ where: { userId } })
    await tx.userExerciseProgress.deleteMany({ where: { userId } })
    await tx.nutritionMealTemplate.deleteMany({ where: { userId } })
    await tx.healthConsentEvent.deleteMany({ where: { userId } })
    await tx.nutritionLogDay.deleteMany({ where: { userId } })
    await tx.nutritionPlanDay.deleteMany({ where: { userId } })
    await tx.story.deleteMany({ where: { userId } })
    await tx.healthConsent.deleteMany({ where: { userId } })
    await tx.analyticsEvent.deleteMany({ where: { userId } })
    await tx.refreshToken.deleteMany({ where: { userId } })

    // ── Challenges ──
    await tx.challengeParticipant.deleteMany({ where: { userId } })
    await tx.challenge.deleteMany({ where: { creatorId: userId } })

    // Scheduled-notification dedupe ledger (FK-less) — clean the user's claims.
    await tx.notificationSentLog.deleteMany({ where: { userId } })

    // ── GPS / segments ──
    await tx.segmentEffort.deleteMany({ where: { userId } })
    await tx.gpsActivity.deleteMany({ where: { userId } })

    // ── Identity / profile ──
    await tx.userTrainingProfile.deleteMany({ where: { userId } })
    await tx.userProfile.deleteMany({ where: { userId } })
    await tx.authIdentity.deleteMany({ where: { userId } })

    // Finally the user row itself.
    await tx.user.delete({ where: { id: userId } })
  })

  // DB erasure committed — remove the on-disk media (best-effort; orphan files
  // are harmless and must never block/raise after a successful erasure).
  await Promise.all(fileUrls.map((u) => deleteUploadByUrl(u)))
}

export async function gdprRoutes(app: FastifyInstance) {
  // DELETE /v1/me/account — right to erasure.
  app.delete('/me/account', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    // Require the typed confirmation server-side (was client-only). Guards against
    // accidental / non-interactive DELETE calls firing erasure on a single token.
    const body = (request.body ?? {}) as { confirm?: unknown }
    const confirm = typeof body.confirm === 'string' ? body.confirm.trim().toUpperCase() : ''
    if (confirm !== 'DELETE') {
      return reply.code(400).send({
        error: 'CONFIRMATION_REQUIRED',
        message: 'Type DELETE to confirm permanent account deletion.',
        requestId: request.id,
      })
    }
    // Opt-in soft-delete: mark deleted + schedule a hard erase in 30 days and
    // revoke the user's sessions, but keep all data so the account is
    // recoverable within the grace window. The login/refresh guards (auth.ts)
    // and the sweep cron (soft-delete-cron.service) complete this flow.
    if (softDeleteEnabled()) {
      try {
        const now = new Date()
        const scheduledHardEraseAt = new Date(
          now.getTime() + SOFT_DELETE_GRACE_DAYS * 24 * 60 * 60 * 1000,
        )
        await prisma.$transaction([
          prisma.user.update({
            where: { id: userId },
            data: { status: 'deleted', softDeletedAt: now, scheduledHardEraseAt },
          }),
          // Revoke sessions so the deleted account can't keep acting via an
          // existing refresh token.
          prisma.refreshToken.deleteMany({ where: { userId } }),
        ])
      } catch (err) {
        app.log.error({ err, userId }, 'Soft-delete failed')
        return reply.code(500).send({
          error: 'ERASURE_FAILED',
          message: 'Ștergerea contului a eșuat. Reîncearcă.',
          requestId: request.id,
        })
      }
      return reply.code(204).send()
    }

    try {
      await eraseUser(userId, app.log)
    } catch (err) {
      app.log.error({ err, userId }, 'Account erasure failed')
      return reply.code(500).send({
        error: 'ERASURE_FAILED',
        message: 'Ștergerea contului a eșuat. Reîncearcă.',
        requestId: request.id,
      })
    }
    return reply.code(204).send()
  })

  // POST /v1/me/change-password — requires current password (email identities only).
  app.post('/me/change-password', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = ChangePasswordSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    const identity = await prisma.authIdentity.findFirst({
      where: { userId, provider: 'email' },
    })
    if (!identity?.passwordHash) {
      return reply.code(400).send({
        error: 'NO_PASSWORD_IDENTITY',
        message: 'Contul nu are parolă (autentificare prin Google).',
        requestId: request.id,
      })
    }

    const ok = await bcrypt.compare(parsed.data.currentPassword, identity.passwordHash)
    if (!ok) {
      return reply.code(401).send({
        error: 'INVALID_CREDENTIALS',
        message: 'Parola curentă este incorectă',
        requestId: request.id,
      })
    }

    const newHash = await bcrypt.hash(parsed.data.newPassword, SALT_ROUNDS)
    await prisma.authIdentity.update({ where: { id: identity.id }, data: { passwordHash: newHash } })
    // Invalidate all sessions after a password change.
    await prisma.refreshToken.deleteMany({ where: { userId } })

    return reply.code(204).send()
  })

}

export { eraseUser, EXPORTABLE_EVENT_NAMES }
