import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { getStreakStatus } from '../services/streak.service'
import { gameXpPayload } from '../services/gym-xp.service'
import { loadDailyQuoteForApi } from '../services/global-daily-quote'
import { decodePostPhotoBase64, saveAvatarPhoto } from '../lib/post-photo'

const UpdateProfileSchema = z.object({
  displayName: z.string().min(1).max(50).optional(),
  username: z.string().min(3).max(30).regex(/^[a-zA-Z0-9_]+$/).optional(),
  bio: z.string().max(200).optional(),
  unitSystem: z.enum(['metric', 'imperial']).optional(),
  bodyweightKg: z.number().min(30).max(250).optional(),
  heightCm: z.number().min(100).max(250).optional(),
  birthYear: z.number().int().min(1900).max(2015).optional(),
  sex: z.enum(['male', 'female', 'other']).optional(),
  privacyDefault: z.enum(['private', 'friends', 'public']).optional(),
  dailyCalories: z.number().int().min(800).max(20000).optional(),
  dailyProtein: z.number().min(0).max(1000).optional(),
  dailyCarbs: z.number().min(0).max(2000).optional(),
  dailyFat: z.number().min(0).max(1000).optional(),
  dailyWaterMl: z.number().int().min(0).max(20000).optional(),
  /// Direct URL override (e.g. user pastes a URL or migrating from another
  /// provider). For in-app uploads use POST /v1/me/avatar instead.
  photoUrl: z.string().url().max(512).nullable().optional(),
})

const AvatarUploadSchema = z.object({
  photoBase64: z.string().max(4_000_000),
})

const UpdateSettingsSchema = z.object({
  feedFriendsOnly: z.boolean().optional(),
  discoveryOptIn: z.boolean().optional(),
  dmFriendsOnly: z.boolean().optional(),
  showBodyStats: z.boolean().optional(),
  showActivityFeed: z.boolean().optional(),
}).strict()

/**
 * Shape of a single media/route entry in the export manifest. Each entry is
 * self-describing: a consumer of the archive can resolve `url` (relative to the
 * API host) or read the inline `routePoints` to reconstruct every artefact the
 * account owns. We list references + metadata rather than inlining binary blobs,
 * so the JSON export stays portable while remaining COMPLETE.
 */
export type ExportMediaEntry = {
  /** avatar | post_image | story_image | gps_route */
  kind: 'avatar' | 'post_image' | 'story_image' | 'gps_route'
  /** Stable id of the owning row (userId for the avatar). */
  refId: string
  /** Relative URL under /uploads/* (image media). Null for GPS routes. */
  url: string | null
  /** Free-form per-entry metadata (caption, timestamps, distance, etc.). */
  meta?: Record<string, unknown>
  /** Inline GPS route geometry — only present for kind === 'gps_route'. */
  routePoints?: unknown
}

/**
 * Minimal subset of the export selection that the manifest builder reads. Kept
 * structurally typed (not tied to Prisma payload types) so it stays pure and
 * trivially unit-testable.
 */
type ExportManifestInput = {
  id: string
  profile?: { photoUrl?: string | null } | null
  posts?: Array<{ id: string; imageUrl?: string | null; caption?: string | null; createdAt?: unknown }>
  stories?: Array<{ id: string; imageUrl?: string | null; caption?: string | null; location?: string | null; createdAt?: unknown }>
  gpsActivities?: Array<{
    id: string
    routePoints?: unknown
    distanceM?: number | null
    durationS?: number | null
    visibility?: string | null
    startedAt?: unknown
    endedAt?: unknown
  }>
}

/**
 * Build a self-describing manifest of every media artefact and GPS route the
 * account owns. Image media is listed by URL + metadata (not inlined); GPS
 * routes carry their full geometry inline since `route_points` is the only place
 * the path exists. Image-less rows (text-only posts/stories) are skipped so the
 * manifest only references artefacts that actually exist on disk.
 */
export function buildExportManifest(data: ExportManifestInput): {
  mediaCount: number
  routeCount: number
  /** Image URLs are relative to the API host (e.g. /uploads/posts/{id}.jpg). */
  urlsRelativeTo: string
  entries: ExportMediaEntry[]
} {
  const entries: ExportMediaEntry[] = []

  if (data.profile?.photoUrl) {
    entries.push({
      kind: 'avatar',
      refId: data.id,
      url: data.profile.photoUrl,
    })
  }

  for (const post of data.posts ?? []) {
    if (!post.imageUrl) continue
    entries.push({
      kind: 'post_image',
      refId: post.id,
      url: post.imageUrl,
      meta: { caption: post.caption ?? null, createdAt: post.createdAt ?? null },
    })
  }

  for (const story of data.stories ?? []) {
    if (!story.imageUrl) continue
    entries.push({
      kind: 'story_image',
      refId: story.id,
      url: story.imageUrl,
      meta: {
        caption: story.caption ?? null,
        location: story.location ?? null,
        createdAt: story.createdAt ?? null,
      },
    })
  }

  for (const act of data.gpsActivities ?? []) {
    entries.push({
      kind: 'gps_route',
      refId: act.id,
      url: null,
      meta: {
        distanceM: act.distanceM ?? null,
        durationS: act.durationS ?? null,
        visibility: act.visibility ?? null,
        startedAt: act.startedAt ?? null,
        endedAt: act.endedAt ?? null,
      },
      routePoints: act.routePoints ?? [],
    })
  }

  const routeCount = entries.filter((e) => e.kind === 'gps_route').length
  return {
    mediaCount: entries.length - routeCount,
    routeCount,
    urlsRelativeTo: 'api-host',
    entries,
  }
}

export async function profileRoutes(app: FastifyInstance) {
  // GET /v1/me
  app.get('/me', { preHandler: authenticate }, async (request, reply) => {
    const { userId, email } = request.user

    const [profile, streak, trainingProfile] = await Promise.all([
      prisma.userProfile.findUnique({ where: { userId } }),
      getStreakStatus(userId),
      prisma.userTrainingProfile.findUnique({ where: { userId } }),
    ])

    const gameXp = gameXpPayload(profile?.gameXpTotal ?? 0)

    return reply.send({
      id: userId,
      email,
      profile,
      streak,
      trainingProfile,
      gameXp,
    })
  })

  // PATCH /v1/me/profile
  app.patch('/me/profile', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const raw = { ...((request.body as Record<string, unknown>) ?? {}) }
    // Accept both casings for backward compatibility (old clients may still send "bodweightKg")
    if (raw.bodweightKg !== undefined && raw.bodyweightKg === undefined) {
      raw.bodyweightKg = raw.bodweightKg
    }
    delete raw.bodweightKg

    const parsed = UpdateProfileSchema.safeParse(raw)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }

    // Verifica username unic daca e schimbat
    if (parsed.data.username) {
      const taken = await prisma.userProfile.findFirst({
        where: {
          username: parsed.data.username,
          NOT: { userId },
        },
      })
      if (taken) {
        return reply.code(409).send({
          error: 'USERNAME_TAKEN',
          message: 'Acest username este deja folosit',
          requestId: request.id,
        })
      }
    }

    const { dailyCalories, dailyProtein, dailyCarbs, dailyFat, dailyWaterMl, ...rest } =
      parsed.data

    const profile = await prisma.userProfile.update({
      where: { userId },
      data: {
        ...rest,
        ...(dailyCalories !== undefined && { dailyCalories }),
        ...(dailyProtein !== undefined && { dailyProtein }),
        ...(dailyCarbs !== undefined && { dailyCarbs }),
        ...(dailyFat !== undefined && { dailyFat }),
        ...(dailyWaterMl !== undefined && { dailyWaterMl }),
      },
    })

    // Daca s-a setat bodyweight, emite eveniment analytics
    if (parsed.data.bodyweightKg) {
      await prisma.analyticsEvent.create({
        data: { userId, eventName: 'bodyweight_set' },
      })
    }

    return reply.send({ profile })
  })

  // PATCH /v1/me/settings - privacy controls enforced by server-side reads.
  app.patch('/me/settings', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = UpdateSettingsSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Invalid privacy settings',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const profile = await prisma.userProfile.update({
      where: { userId },
      data: parsed.data,
    })
    return reply.send({ settings: {
      feedFriendsOnly: profile.feedFriendsOnly,
      discoveryOptIn: profile.discoveryOptIn,
      dmFriendsOnly: profile.dmFriendsOnly,
      showBodyStats: profile.showBodyStats,
      showActivityFeed: profile.showActivityFeed,
    } })
  })

  // GET /v1/me/export-data - immediate GDPR portability export. Credentials,
  // password hashes and refresh tokens are intentionally excluded.
  app.get('/me/export-data', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const data = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        createdAt: true,
        status: true,
        profile: true,
        trainingProfile: true,
        workouts: {
          include: {
            exercises: { include: { sets: true } },
          },
        },
        posts: true,
        postLikes: true,
        postComments: true,
        friendsFrom: true,
        friendsTo: true,
        exerciseRanks: true,
        seasonStats: true,
        analyticsEvents: true,
        userAchievements: true,
        notifications: true,
        dmConversationsLow: true,
        dmConversationsHigh: true,
        directMessagesSent: true,
        wallet: { include: { transactions: true } },
        nutritionLogDays: true,
        nutritionPlanDays: true,
        plannedWorkouts: true,
        challengesCreated: true,
        challengeParticipations: true,
        challengeProgressLogs: true,
        challengeMessages: true,
        stories: true,
        storyLikes: true,
        postBookmarks: true,
        postHides: true,
        postReports: true,
        gpsActivities: true,
        createdSegments: true,
        segmentEfforts: true,
        wearableConnections: true,
        healthImports: true,
        healthDailyMetrics: true,
      },
    })
    if (!data) {
      return reply.code(404).send({
        error: 'USER_NOT_FOUND',
        message: 'Account not found',
        requestId: request.id,
      })
    }
    // Self-describing media + GPS-route manifest so the export is COMPLETE:
    // a consumer can resolve every avatar/post/story image URL (relative to the
    // API host) and read every GPS route the account owns from one document.
    const mediaManifest = buildExportManifest(data)
    reply.header('Content-Disposition', 'attachment; filename="zvelt-data-export.json"')
    reply.header('Cache-Control', 'private, no-store')
    return reply.send({
      exportedAt: new Date().toISOString(),
      formatVersion: 2,
      mediaManifest,
      data,
    })
  })

  // POST /v1/me/avatar — accepts base64-encoded JPG/PNG/WebP (≤1.8MB).
  // Saves to /uploads/avatars/<userId>.<ext>, updates userProfile.photoUrl,
  // returns the new URL. Frontend appends `?v=<timestamp>` when rendering to
  // bypass caches after re-upload (the file path itself is stable per user).
  app.post('/me/avatar', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = AvatarUploadSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Body invalid',
        requestId: request.id,
      })
    }
    let buf: Buffer
    try {
      buf = decodePostPhotoBase64(parsed.data.photoBase64)
    } catch (err: any) {
      return reply.code(400).send({
        error: 'PHOTO_INVALID',
        message: err?.message ?? 'Photo too large or wrong format (JPEG/PNG/WebP).',
        requestId: request.id,
      })
    }
    const url = await saveAvatarPhoto(userId, buf)
    await prisma.userProfile.update({
      where: { userId },
      data: { photoUrl: url },
    })
    return reply.send({ photoUrl: url })
  })

  // DELETE /v1/me/avatar — clears photoUrl so the UI falls back to initials.
  // Doesn't delete the file from disk (cheap retention; rebroadcasts on
  // re-upload anyway since the filename is stable per user).
  app.delete('/me/avatar', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    await prisma.userProfile.update({
      where: { userId },
      data: { photoUrl: null },
    })
    return reply.code(204).send()
  })

  // GET /v1/me/daily-quote — read-only; quote for UK „today” pre-generated @ 00:00 UK (cron).
  app.get('/me/daily-quote', async (_request, reply) => {
    reply.header('Cache-Control', 'private, no-store')
    const body = await loadDailyQuoteForApi()
    return reply.send(body)
  })
}
