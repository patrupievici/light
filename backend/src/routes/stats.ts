import type { FastifyInstance } from 'fastify'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'

export async function statsRoutes(app: FastifyInstance) {
  // GET /v1/me/stats/weekly-effort — volum (kg×reps) + seturi WORK pe săptămână (task #46)
  app.get('/stats/weekly-effort', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { weeks?: string }
    const weeks = Math.min(52, Math.max(1, parseInt(q.weeks ?? '12', 10) || 12))

    const rows = await prisma.$queryRawUnsafe<
      { week_start: Date; volume_kg: number; work_sets: number }[]
    >(
      `SELECT date_trunc('week', w.started_at) AS week_start,
              COALESCE(SUM(CAST(ws.weight_kg AS DOUBLE PRECISION) * ws.reps), 0) AS volume_kg,
              COUNT(*)::int AS work_sets
       FROM workouts w
       INNER JOIN workout_exercises we ON we.workout_id = w.id
       INNER JOIN workout_sets ws ON ws.workout_exercise_id = we.id AND ws.tag = 'WORK' AND ws.is_completed = true
       WHERE w.user_id = $1 AND w.status IN ('completed','posted')
       GROUP BY 1
       ORDER BY 1 DESC
       LIMIT $2`,
      userId,
      weeks,
    )

    const data = rows.map((r) => ({
      weekStart: r.week_start.toISOString().slice(0, 10),
      volumeKg: Number(r.volume_kg),
      workSets: r.work_sets,
    }))

    return reply.send({ data })
  })

  // GET /v1/me/stats/daily-training — sesiuni + volum + seturi WORK pe zi (ultimele N zile)
  app.get('/stats/daily-training', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { days?: string }
    const days = Math.min(90, Math.max(7, parseInt(q.days ?? '42', 10) || 42))

    const rows = await prisma.$queryRawUnsafe<
      { day: string; sessions: number; volume_kg: number; work_sets: number }[]
    >(
      `WITH series AS (
         SELECT generate_series(
           (CURRENT_DATE - ($2::int - 1))::date,
           CURRENT_DATE::date,
           '1 day'::interval
         )::date AS day
       ),
       sess AS (
         SELECT (w.started_at AT TIME ZONE 'UTC')::date AS day,
                COUNT(*)::int AS sessions
         FROM workouts w
         WHERE w.user_id = $1
           AND w.status IN ('completed','posted')
           AND (w.started_at AT TIME ZONE 'UTC')::date >= (CURRENT_DATE - ($2::int - 1))
         GROUP BY 1
       ),
       vol AS (
         SELECT (w.started_at AT TIME ZONE 'UTC')::date AS day,
                COALESCE(SUM(CAST(ws.weight_kg AS DOUBLE PRECISION) * ws.reps), 0) AS volume_kg,
                COUNT(*)::int AS work_sets
         FROM workouts w
         INNER JOIN workout_exercises we ON we.workout_id = w.id
         INNER JOIN workout_sets ws ON ws.workout_exercise_id = we.id AND ws.tag = 'WORK' AND ws.is_completed = true
         WHERE w.user_id = $1
           AND w.status IN ('completed','posted')
           AND (w.started_at AT TIME ZONE 'UTC')::date >= (CURRENT_DATE - ($2::int - 1))
         GROUP BY 1
       )
       SELECT s.day::text AS day,
              COALESCE(sess.sessions, 0)::int AS sessions,
              COALESCE(vol.volume_kg, 0)::float8 AS volume_kg,
              COALESCE(vol.work_sets, 0)::int AS work_sets
       FROM series s
       LEFT JOIN sess ON sess.day = s.day
       LEFT JOIN vol ON vol.day = s.day
       ORDER BY s.day`,
      userId,
      days,
    )

    return reply.send({
      data: rows.map((r) => ({
        day: r.day,
        sessions: r.sessions,
        volumeKg: Number(r.volume_kg),
        workSets: r.work_sets,
      })),
    })
  })

  // GET /v1/me/stats/weekly-sessions — număr de antrenamente distincte pe săptămână
  app.get('/stats/weekly-sessions', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { weeks?: string }
    const weeks = Math.min(52, Math.max(1, parseInt(q.weeks ?? '12', 10) || 12))

    const rows = await prisma.$queryRawUnsafe<{ week_start: Date; sessions: number }[]>(
      `SELECT date_trunc('week', w.started_at) AS week_start,
              COUNT(DISTINCT w.id)::int AS sessions
       FROM workouts w
       WHERE w.user_id = $1 AND w.status IN ('completed','posted')
       GROUP BY 1
       ORDER BY 1 DESC
       LIMIT $2`,
      userId,
      weeks,
    )

    return reply.send({
      data: rows.map((r) => ({
        weekStart: r.week_start.toISOString().slice(0, 10),
        sessions: r.sessions,
      })),
    })
  })

  // GET /v1/me/stats/top-exercises — volum WORK după exercițiu (ultimele N zile)
  app.get('/stats/top-exercises', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { days?: string; limit?: string }
    const days = Math.min(365, Math.max(7, parseInt(q.days ?? '90', 10) || 90))
    const limit = Math.min(25, Math.max(3, parseInt(q.limit ?? '10', 10) || 10))

    const rows = await prisma.$queryRawUnsafe<
      { exercise_id: string; name: string; volume_kg: number; work_sets: number }[]
    >(
      `SELECT e.id::text AS exercise_id,
              e.name,
              COALESCE(SUM(CAST(ws.weight_kg AS DOUBLE PRECISION) * ws.reps), 0) AS volume_kg,
              COUNT(*)::int AS work_sets
       FROM workouts w
       INNER JOIN workout_exercises we ON we.workout_id = w.id
       INNER JOIN workout_sets ws ON ws.workout_exercise_id = we.id AND ws.tag = 'WORK' AND ws.is_completed = true
       INNER JOIN exercises e ON e.id = we.exercise_id
       WHERE w.user_id = $1
         AND w.status IN ('completed','posted')
         AND w.started_at >= NOW() - (interval '1 day' * $2::int)
       GROUP BY e.id, e.name
       ORDER BY volume_kg DESC
       LIMIT $3`,
      userId,
      days,
      limit,
    )

    return reply.send({
      data: rows.map((r) => ({
        exerciseId: r.exercise_id,
        name: r.name,
        volumeKg: Number(r.volume_kg),
        workSets: r.work_sets,
      })),
    })
  })

  // GET /v1/me/stats/rank-lp — snapshot curent LP per exercițiu (top N)
  app.get('/stats/rank-lp', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { limit?: string }
    const limit = Math.min(30, Math.max(5, parseInt(q.limit ?? '12', 10) || 12))

    const rows = await prisma.userExerciseRank.findMany({
      where: { userId },
      include: { exercise: { select: { name: true } } },
      orderBy: { lpTotal: 'desc' },
      take: limit,
    })

    return reply.send({
      data: rows.map((r) => ({
        exerciseId: r.exerciseId,
        name: r.exercise.name,
        lpTotal: r.lpTotal,
        bestE1rmKg: Number(r.bestE1rmKg),
      })),
    })
  })

  // GET /v1/me/stats (prefix înregistrat: /v1/me)
  app.get('/stats', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const [ranks, workouts] = await Promise.all([
      prisma.userExerciseRank.findMany({
        where: { userId },
        include: { exercise: true },
      }),
      prisma.workout.findMany({
        where: { userId, status: { in: ['completed', 'posted'] } },
        orderBy: { startedAt: 'desc' },
        take: 30,
        select: { startedAt: true },
      }),
    ])

    const strengthRanks = ranks.filter((r) => r.exercise.category === 'strength')
    const strengthScore =
      strengthRanks.length > 0
        ? Math.min(
            100,
            Math.round(
              strengthRanks.reduce((sum, r) => sum + r.lpTotal, 0) /
                strengthRanks.length /
                3
            )
          )
        : 0

    const explosiveRanks = ranks.filter((r) => r.exercise.category === 'explosive')
    const agilityScore =
      explosiveRanks.length > 0
        ? Math.min(
            100,
            Math.round(
              explosiveRanks.reduce((sum, r) => sum + r.lpTotal, 0) /
                explosiveRanks.length /
                3
            )
          )
        : 0

    const last30Days = workouts.filter((w) => {
      const diff = Date.now() - new Date(w.startedAt).getTime()
      return diff <= 30 * 24 * 60 * 60 * 1000
    })
    const vitalityScore = Math.min(100, Math.round((last30Days.length / 20) * 100))

    const streakDays = calculateStreak(workouts.map((w) => w.startedAt))
    const intelligenceScore = Math.min(
      100,
      Math.round((streakDays / 30) * 60 + (workouts.length / 50) * 40)
    )

    const distinctExercises = new Set(ranks.map((r) => r.exerciseId)).size
    const perceptionScore = Math.min(100, Math.round((distinctExercises / 15) * 100))

    return reply.send({
      stats: {
        strength: {
          value: strengthScore,
          label: 'Strength',
          description: 'Based on your weighted exercise ranks',
        },
        agility: {
          value: agilityScore,
          label: 'Agility',
          description: 'Based on your explosive exercise ranks',
        },
        vitality: {
          value: vitalityScore,
          label: 'Vitality',
          description: 'Based on workout consistency last 30 days',
        },
        intelligence: {
          value: intelligenceScore,
          label: 'Intelligence',
          description: 'Based on streak and total workouts',
        },
        perception: {
          value: perceptionScore,
          label: 'Perception',
          description: 'Based on exercise variety',
        },
      },
      overall: Math.round(
        (strengthScore + agilityScore + vitalityScore + intelligenceScore + perceptionScore) / 5
      ),
    })
  })

  // GET /v1/me/stats/cumulative-volume?year=YYYY
  // Daily volume (kg × reps, WORK sets only) plus running total for the year.
  // The cumulative series is the "hero chart" — it never goes down, so users
  // see progress every time they show up even when individual lifts plateau.
  app.get('/stats/cumulative-volume', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { year?: string }
    const now = new Date()
    const yearNum = parseInt(q.year ?? `${now.getUTCFullYear()}`, 10)
    const year = Number.isFinite(yearNum) && yearNum >= 2000 && yearNum <= 2100
      ? yearNum
      : now.getUTCFullYear()

    const start = new Date(Date.UTC(year, 0, 1, 0, 0, 0, 0))
    const end = new Date(Date.UTC(year + 1, 0, 1, 0, 0, 0, 0))

    const sets = await prisma.workoutSet.findMany({
      where: {
        tag: 'WORK',
        isCompleted: true,
        weightKg: { gt: 0 },
        createdAt: { gte: start, lt: end },
        workoutExercise: {
          workout: { userId, status: { in: ['completed', 'posted'] } },
        },
      },
      select: { weightKg: true, reps: true, createdAt: true },
    })

    // Aggregate per UTC day. We use UTC for storage; UI can shift to local on
    // render. Going local server-side would explode index complexity.
    const byDay = new Map<string, number>()
    for (const s of sets) {
      const day = s.createdAt.toISOString().slice(0, 10)
      const vol = Number(s.weightKg) * s.reps
      byDay.set(day, (byDay.get(day) ?? 0) + vol)
    }

    const sortedDays = [...byDay.entries()].sort((a, b) => a[0].localeCompare(b[0]))
    let cumulative = 0
    const data = sortedDays.map(([day, daily]) => {
      cumulative += daily
      return {
        day,
        dailyVolumeKg: Math.round(daily * 10) / 10,
        cumulativeVolumeKg: Math.round(cumulative * 10) / 10,
      }
    })

    return reply.send({
      year,
      totalKg: Math.round(cumulative * 10) / 10,
      activeDays: data.length,
      data,
    })
  })

  // GET /v1/me/stats/recent-prs?days=N
  // Rep-range PR detection: for each (exercise, reps) pair, find max weight
  // ever, and flag sets in the window that broke a prior max. Catches PRs
  // that pure 1RM tracking misses — e.g. 100×5 after 100×4 IS a PR even
  // though weight didn't move.
  app.get('/stats/recent-prs', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { days?: string }
    const days = Math.min(180, Math.max(1, parseInt(q.days ?? '30', 10) || 30))
    const windowSince = new Date(Date.now() - days * 24 * 60 * 60 * 1000)

    const sets = await prisma.workoutSet.findMany({
      where: {
        tag: 'WORK',
        isCompleted: true,
        weightKg: { gt: 0 },
        reps: { gte: 1, lte: 30 },
        workoutExercise: {
          workout: { userId, status: { in: ['completed', 'posted'] } },
        },
      },
      select: {
        weightKg: true,
        reps: true,
        createdAt: true,
        workoutExercise: {
          select: {
            exerciseId: true,
            exercise: { select: { name: true } },
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    })

    // Track running max per (exerciseId, reps). A set is a PR iff its weight
    // strictly exceeds the prior max for that pair AND it falls in window.
    const maxByExRep = new Map<string, number>()
    const prs: Array<{
      exerciseId: string
      exerciseName: string
      weightKg: number
      reps: number
      previousBestKg: number
      date: string
    }> = []

    for (const s of sets) {
      const eid = s.workoutExercise.exerciseId
      const key = `${eid}::${s.reps}`
      const prev = maxByExRep.get(key) ?? 0
      const w = Number(s.weightKg)
      if (w > prev) {
        if (s.createdAt >= windowSince) {
          prs.push({
            exerciseId: eid,
            exerciseName: s.workoutExercise.exercise.name,
            weightKg: w,
            reps: s.reps,
            previousBestKg: prev,
            date: s.createdAt.toISOString(),
          })
        }
        maxByExRep.set(key, w)
      }
    }

    // Most recent PR first — the celebration list, not a history.
    prs.sort((a, b) => b.date.localeCompare(a.date))

    return reply.send({
      days,
      count: prs.length,
      data: prs,
    })
  })
}

function calculateStreak(dates: Date[]): number {
  if (dates.length === 0) return 0
  const sorted = [...dates]
    .map((d) => new Date(d).toDateString())
    .filter((v, i, a) => a.indexOf(v) === i)
    .map((d) => new Date(d).getTime())
    .sort((a, b) => b - a)

  let streak = 0
  const day = 24 * 60 * 60 * 1000
  const today = new Date(new Date().toDateString()).getTime()

  for (let i = 0; i < sorted.length; i++) {
    const expected = today - i * day
    if (Math.abs(sorted[i] - expected) < day) streak++
    else break
  }
  return streak
}
