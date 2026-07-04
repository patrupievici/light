import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { normalizeRoutePoints } from './activities'
import { matchSegmentEffort, type LatLng } from '../lib/segment-match'
import { areFriends } from '../lib/friendships'

// ─── Validation schemas ───────────────────────────────────────────────────────

const NearbyQuery = z.object({
  lat:    z.coerce.number().min(-90).max(90),
  lng:    z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().min(100).max(50_000).default(5_000),
})

const CreateEffortBody = z.object({
  segmentId:    z.string().uuid(),
  // Required: every leaderboard-eligible effort must reference an owned activity
  // so it goes through the ownership + path/direction validation below. Without
  // it a bare {segmentId, elapsedTimeS:1} would skip all checks and land rank 1.
  activityId:   z.string().uuid(),
  elapsedTimeS: z.number().int().positive(),
  avgSpeedKmh:  z.number().positive().optional(),
})

// ─── Raw-query row types ──────────────────────────────────────────────────────

type NearbyRow = {
  id:                   string
  name:                 string
  description:          string | null
  start_lat:            number | null
  start_lng:            number | null
  end_lat:              number | null
  end_lng:              number | null
  distance_m:           number | null
  elev_gain_m:          number | null
  created_by:           string | null
  created_at:           Date
  distance_from_start_m: number
}

type SegmentRow = {
  id:         string
  name:       string
  distance_m: number | null
  elev_gain_m: number | null
}

/** Segment row carrying the stored polyline, for effort path validation. */
type SegmentRouteRow = {
  id:           string
  route_points: unknown
}

/** Activity row carrying the recorded GPS track, for effort path validation. */
type ActivityRouteRow = {
  id:           string
  user_id:      string
  route_points: unknown
}

type LeaderboardRow = {
  rank:            number
  effort_id:       string
  user_id:         string
  display_name:    string | null
  username:        string | null
  elapsed_time_s:  number
  avg_speed_kmh:   number | null
  created_at:      Date
}

type UserEffortRow = {
  effort_id:          string
  segment_id:         string
  segment_name:       string
  elapsed_time_s:     number
  avg_speed_kmh:      number | null
  created_at:         Date
  segment_distance_m: number | null
  elev_gain_m:        number | null
}

type CountRow = { count: bigint }

// ─── Routes ───────────────────────────────────────────────────────────────────

export async function segmentRoutes(app: FastifyInstance) {
  // ── GET /v1/segments/nearby?lat=&lng=&radius= ─────────────────────────────
  // Returns segments whose start point lies within `radius` metres of (lat, lng).
  // Uses a degree-based bounding-box pre-filter on the B-tree index, then the
  // Haversine formula for the exact distance check.
  app.get('/segments/nearby', { preHandler: authenticate }, async (request, reply) => {
    const parsed = NearbyQuery.safeParse(request.query)
    if (!parsed.success) {
      return reply.code(400).send({
        error:     'VALIDATION_ERROR',
        message:   'Required: lat, lng. Optional: radius (100–50000 m, default 5000)',
        requestId: request.id,
      })
    }
    const { lat, lng, radius } = parsed.data

    // Convert radius to a lat/lng bounding box for the index pre-filter.
    const latDelta = radius / 111_320
    const lngDelta = radius / (111_320 * Math.cos((lat * Math.PI) / 180))

    const rows = await prisma.$queryRawUnsafe<NearbyRow[]>(
      `SELECT
         id, name, description,
         start_lat, start_lng, end_lat, end_lng,
         distance_m, elev_gain_m, created_by, created_at,
         (6371000.0 * 2.0 * asin(sqrt(
           power(sin(radians(($1::float8 - start_lat) / 2.0)), 2) +
           cos(radians(start_lat)) * cos(radians($1::float8)) *
           power(sin(radians(($2::float8 - start_lng) / 2.0)), 2)
         )))::float8 AS distance_from_start_m
       FROM segments
       WHERE start_lat IS NOT NULL
         AND start_lng  IS NOT NULL
         AND start_lat  BETWEEN $1::float8 - $4::float8 AND $1::float8 + $4::float8
         AND start_lng  BETWEEN $2::float8 - $5::float8 AND $2::float8 + $5::float8
         AND (6371000.0 * 2.0 * asin(sqrt(
               power(sin(radians(($1::float8 - start_lat) / 2.0)), 2) +
               cos(radians(start_lat)) * cos(radians($1::float8)) *
               power(sin(radians(($2::float8 - start_lng) / 2.0)), 2)
             ))) <= $3::float8
       ORDER BY distance_from_start_m ASC
       LIMIT 50`,
      lat, lng, radius, latDelta, lngDelta,
    )

    return reply.send({
      segments: rows.map((r) => ({
        id:                 r.id,
        name:               r.name,
        description:        r.description,
        startLat:           r.start_lat,
        startLng:           r.start_lng,
        endLat:             r.end_lat,
        endLng:             r.end_lng,
        distanceM:          r.distance_m   != null ? Number(r.distance_m)  : null,
        elevGainM:          r.elev_gain_m  != null ? Number(r.elev_gain_m) : null,
        createdBy:          r.created_by,
        createdAt:          r.created_at.toISOString(),
        distanceFromStartM: Number(r.distance_from_start_m),
      })),
      count:  rows.length,
      radius,
      center: { lat, lng },
    })
  })

  // ── POST /v1/segment-efforts ──────────────────────────────────────────────
  // Saves a new effort for the authenticated user.
  // Multiple efforts per user per segment are allowed; the leaderboard picks
  // the personal best (lowest elapsed_time_s) via DISTINCT ON.
  app.post('/segment-efforts', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const parsed = CreateEffortBody.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error:     'VALIDATION_ERROR',
        message:   parsed.error.errors[0]?.message ?? 'Invalid request body',
        requestId: request.id,
      })
    }
    const { segmentId, activityId, elapsedTimeS, avgSpeedKmh } = parsed.data

    // Verify segment exists (and pull its polyline for path validation).
    const segs = await prisma.$queryRawUnsafe<SegmentRouteRow[]>(
      `SELECT id, route_points FROM segments WHERE id = $1 LIMIT 1`,
      segmentId,
    )
    if (segs.length === 0) {
      return reply.code(404).send({
        error:     'SEGMENT_NOT_FOUND',
        message:   'Segmentul nu există',
        requestId: request.id,
      })
    }

    // ── Path-following + direction validation ───────────────────────────────
    // When the effort references a recorded GPS activity, confirm the track
    // actually traversed the segment polyline start→end inside a corridor — not
    // just passed near the endpoints. Reversed / partial / off-path efforts are
    // rejected so they can't pollute the leaderboard.
    //
    // Behaviour-preserving fallbacks: efforts without an activityId, and efforts
    // whose segment or activity lacks usable geometry, are accepted exactly as
    // before (the matcher returns `no-data`, which we treat as "can't judge").
    if (activityId) {
      const acts = await prisma.$queryRawUnsafe<ActivityRouteRow[]>(
        `SELECT id, user_id, route_points FROM activities WHERE id = $1 LIMIT 1`,
        activityId,
      )
      if (acts.length === 0) {
        return reply.code(404).send({
          error:     'ACTIVITY_NOT_FOUND',
          message:   'Activitatea nu există',
          requestId: request.id,
        })
      }
      // Only the activity's owner may claim an effort from it.
      if (acts[0].user_id !== userId) {
        return reply.code(403).send({
          error:     'ACTIVITY_FORBIDDEN',
          message:   'Activitatea nu îți aparține',
          requestId: request.id,
        })
      }

      const polyline = normalizeRoutePoints(segs[0].route_points) as LatLng[]
      const track    = normalizeRoutePoints(acts[0].route_points) as LatLng[]
      const match    = matchSegmentEffort(polyline, track)

      // `no-data` means we lack the geometry to judge → keep legacy behaviour.
      if (!match.matched && match.direction !== 'no-data') {
        const messages: Record<string, string> = {
          reversed:   'Traseul a fost parcurs în sens invers segmentului',
          'off-path': 'Activitatea nu a urmat traseul segmentului',
        }
        return reply.code(422).send({
          error:     'EFFORT_PATH_MISMATCH',
          message:   messages[match.direction] ?? 'Activitatea nu corespunde segmentului',
          requestId: request.id,
          details:   {
            direction:       match.direction,
            coverage:        match.coverage,
            reverseCoverage: match.reverseCoverage,
          },
        })
      }
    }

    const effortId = crypto.randomUUID()
    const now      = new Date().toISOString()

    await prisma.$executeRawUnsafe(
      `INSERT INTO segment_efforts
         (id, segment_id, user_id, activity_id, elapsed_time_s, avg_speed_kmh, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7::timestamp)`,
      effortId,
      segmentId,
      userId,
      activityId ?? null,
      elapsedTimeS,
      avgSpeedKmh ?? null,
      now,
    )

    return reply.code(201).send({
      effort: {
        id:           effortId,
        segmentId,
        userId,
        activityId:   activityId ?? null,
        elapsedTimeS,
        avgSpeedKmh:  avgSpeedKmh ?? null,
        createdAt:    now,
      },
    })
  })

  // ── GET /v1/segments/:id/leaderboard ─────────────────────────────────────
  // Top-10 personal-best efforts for a segment (one entry per user, fastest first).
  // DISTINCT ON (user_id) ORDER BY elapsed_time_s selects each user's PB, then
  // RANK() OVER assigns the leaderboard position.
  app.get('/segments/:id/leaderboard', { preHandler: authenticate }, async (request, reply) => {
    const { id: segmentId } = request.params as { id: string }
    const { userId: currentUserId } = request.user

    const segs = await prisma.$queryRawUnsafe<SegmentRow[]>(
      `SELECT id, name, distance_m, elev_gain_m FROM segments WHERE id = $1 LIMIT 1`,
      segmentId,
    )
    if (segs.length === 0) {
      return reply.code(404).send({
        error:     'SEGMENT_NOT_FOUND',
        message:   'Segmentul nu există',
        requestId: request.id,
      })
    }
    const segment = segs[0]

    const rows = await prisma.$queryRawUnsafe<LeaderboardRow[]>(
      `SELECT
         RANK() OVER (ORDER BY elapsed_time_s ASC)::int AS rank,
         effort_id, user_id,
         elapsed_time_s, avg_speed_kmh, created_at,
         display_name, username
       FROM (
         SELECT DISTINCT ON (se.user_id)
           se.id              AS effort_id,
           se.user_id,
           se.elapsed_time_s,
           se.avg_speed_kmh,
           se.created_at,
           up.display_name,
           up.username
         FROM segment_efforts se
         LEFT JOIN user_profiles up ON up.user_id = se.user_id
         WHERE se.segment_id = $1
         ORDER BY se.user_id, se.elapsed_time_s ASC
       ) best
       ORDER BY elapsed_time_s ASC
       LIMIT 10`,
      segmentId,
    )

    return reply.send({
      segment: {
        id:        segment.id,
        name:      segment.name,
        distanceM: segment.distance_m != null ? Number(segment.distance_m) : null,
        elevGainM: segment.elev_gain_m != null ? Number(segment.elev_gain_m) : null,
      },
      leaderboard: rows.map((r) => ({
        rank:          Number(r.rank),
        effortId:      r.effort_id,
        userId:        r.user_id,
        displayName:   r.display_name ?? r.username ?? 'Athlete',
        username:      r.username,
        elapsedTimeS:  Number(r.elapsed_time_s),
        avgSpeedKmh:   r.avg_speed_kmh != null ? Number(r.avg_speed_kmh) : null,
        createdAt:     r.created_at.toISOString(),
        isCurrentUser: r.user_id === currentUserId,
      })),
    })
  })

  // ── GET /v1/users/:id/segment-efforts ─────────────────────────────────────
  // All efforts of a user, newest first, with segment metadata.
  // Privacy: a caller reading their OWN efforts sees everything. Reading another
  // user's efforts only surfaces those whose SOURCE ACTIVITY is visible to the
  // caller — public always, friends-only when an accepted friendship exists —
  // mirroring canViewActivity in activities.ts. Efforts without a source
  // activity (or from a `private` activity) are owner-only.
  app.get('/users/:id/segment-efforts', { preHandler: authenticate }, async (request, reply) => {
    const { id: targetUserId } = request.params as { id: string }
    const { userId: viewerId } = request.user
    const q = request.query as { limit?: string; offset?: string }

    const limit  = Math.min(100, Math.max(1, parseInt(q.limit  ?? '20', 10) || 20))
    const offset = Math.max(0,               parseInt(q.offset ?? '0',  10) || 0)

    const isOwn = viewerId === targetUserId
    const isFriend = isOwn ? false : await areFriends(viewerId, targetUserId)
    // SQL fragment restricting cross-user reads to visible source activities.
    // Joined activity is aliased `a`; owner reads apply no restriction.
    const visibilityClause = isOwn
      ? ''
      : isFriend
        ? `AND a.visibility IN ('public', 'friends')`
        : `AND a.visibility = 'public'`

    const [rows, countRows] = await Promise.all([
      prisma.$queryRawUnsafe<UserEffortRow[]>(
        `SELECT
           se.id            AS effort_id,
           se.segment_id,
           s.name           AS segment_name,
           se.elapsed_time_s,
           se.avg_speed_kmh,
           se.created_at,
           s.distance_m     AS segment_distance_m,
           s.elev_gain_m
         FROM segment_efforts se
         JOIN segments s ON s.id = se.segment_id
         LEFT JOIN activities a ON a.id = se.activity_id
         WHERE se.user_id = $1 ${visibilityClause}
         ORDER BY se.created_at DESC
         LIMIT $2 OFFSET $3`,
        targetUserId, limit, offset,
      ),
      prisma.$queryRawUnsafe<CountRow[]>(
        `SELECT COUNT(*)::bigint AS count
         FROM segment_efforts se
         LEFT JOIN activities a ON a.id = se.activity_id
         WHERE se.user_id = $1 ${visibilityClause}`,
        targetUserId,
      ),
    ])

    const total = Number(countRows[0]?.count ?? 0)

    return reply.send({
      userId: targetUserId,
      efforts: rows.map((r) => ({
        effortId:         r.effort_id,
        segmentId:        r.segment_id,
        segmentName:      r.segment_name,
        elapsedTimeS:     Number(r.elapsed_time_s),
        avgSpeedKmh:      r.avg_speed_kmh      != null ? Number(r.avg_speed_kmh)      : null,
        createdAt:        r.created_at.toISOString(),
        segmentDistanceM: r.segment_distance_m != null ? Number(r.segment_distance_m) : null,
        elevGainM:        r.elev_gain_m        != null ? Number(r.elev_gain_m)        : null,
      })),
      total,
      limit,
      offset,
    })
  })
}
