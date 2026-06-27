import type { FastifyInstance } from 'fastify'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { lpToTier } from '../services/ranking.service'
import {
  svgSlugForMuscle,
  computeMuscleLevel,
  SVG_SLUGS,
  PRIMARY_CONTRIB,
  SECONDARY_CONTRIB,
} from '../lib/muscle-levels'

/**
 * GET /v1/me/muscle-levels — per-muscle level for the front/back muscle map.
 * Derived on-the-fly (no table): WORK-set volume per muscle (primary 1.0 /
 * secondary 0.5) + the muscle's best strength (LP) → level. Slugs are emitted in
 * the Flutter SVG vocabulary so the map can key on them 1:1.
 *
 * Query: ?window=<days> (default all-time), ?includeUntrained=true (default
 * false — omit muscles never trained).
 */
export async function muscleLevelsRoutes(app: FastifyInstance) {
  app.get('/muscle-levels', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { window?: string; includeUntrained?: string }
    const windowDays = q.window ? Math.min(3650, Math.max(1, parseInt(q.window, 10) || 0)) : 0
    const includeUntrained = q.includeUntrained === 'true' || q.includeUntrained === '1'

    type Agg = { volumeXp: number; volumeKg: number; workSets: number; lastTrainedAt: Date | null; bestLp: number }
    const bySlug = new Map<string, Agg>()
    const ensure = (slug: string): Agg => {
      let a = bySlug.get(slug)
      if (!a) {
        a = { volumeXp: 0, volumeKg: 0, workSets: 0, lastTrainedAt: null, bestLp: 0 }
        bySlug.set(slug, a)
      }
      return a
    }

    // ── Volume from WORK sets ─────────────────────────────────────────────────
    const sets = await prisma.workoutSet.findMany({
      where: {
        tag: 'WORK',
        isCompleted: true,
        workoutExercise: { workout: { userId, status: { in: ['completed', 'posted'] } } },
        ...(windowDays > 0 ? { createdAt: { gte: new Date(Date.now() - windowDays * 86_400_000) } } : {}),
      },
      select: {
        weightKg: true,
        reps: true,
        createdAt: true,
        workoutExercise: { select: { exercise: { select: { primaryMuscle: true, secondaryMuscles: true } } } },
      },
      orderBy: { createdAt: 'desc' },
      take: 8000,
    })

    for (const s of sets) {
      const ex = s.workoutExercise?.exercise
      if (!ex) continue
      const vol = Number(s.weightKg) * s.reps
      const primarySlug = svgSlugForMuscle(ex.primaryMuscle)
      if (primarySlug) {
        const a = ensure(primarySlug)
        a.volumeXp += vol * PRIMARY_CONTRIB
        a.volumeKg += vol
        a.workSets += 1
        if (!a.lastTrainedAt || s.createdAt > a.lastTrainedAt) a.lastTrainedAt = s.createdAt
      }
      const secondary = Array.isArray(ex.secondaryMuscles) ? ex.secondaryMuscles : []
      const seen = new Set<string>(primarySlug ? [primarySlug] : [])
      for (const m of secondary) {
        const slug = svgSlugForMuscle(m)
        if (!slug || seen.has(slug)) continue
        seen.add(slug)
        // Secondary muscles get the half-weighted volume AND the trained-metadata
        // (volumeKg / workSets / lastTrainedAt) — otherwise a muscle worked only
        // as a secondary (e.g. triceps from bench) would show a level but read as
        // "never trained".
        const a = ensure(slug)
        a.volumeXp += vol * SECONDARY_CONTRIB
        a.volumeKg += vol * SECONDARY_CONTRIB
        a.workSets += 1
        if (!a.lastTrainedAt || s.createdAt > a.lastTrainedAt) a.lastTrainedAt = s.createdAt
      }
    }

    // ── Strength: best LP among each muscle's primary lifts ───────────────────
    const ranks = await prisma.userExerciseRank.findMany({
      where: { userId },
      select: { lpTotal: true, exercise: { select: { primaryMuscle: true } } },
    })
    for (const r of ranks) {
      const slug = svgSlugForMuscle(r.exercise?.primaryMuscle)
      if (!slug) continue
      const a = ensure(slug)
      if (r.lpTotal > a.bestLp) a.bestLp = r.lpTotal
    }

    const data = SVG_SLUGS.map((slug) => {
      const a = bySlug.get(slug) ?? { volumeXp: 0, volumeKg: 0, workSets: 0, lastTrainedAt: null, bestLp: 0 }
      const parts = computeMuscleLevel(a.volumeXp, a.bestLp)
      return {
        slug,
        level: parts.level,
        volumeLevel: parts.volumeLevel,
        strengthBonus: parts.strengthBonus,
        volumeXp: Math.round(a.volumeXp),
        volumeKg: Math.round(a.volumeKg),
        workSets: a.workSets,
        bestLp: a.bestLp,
        tier: lpToTier(a.bestLp),
        lastTrainedAt: a.lastTrainedAt ? a.lastTrainedAt.toISOString() : null,
      }
    })
      .filter((m) => includeUntrained || m.level > 0)
      .sort((x, y) => y.level - x.level || y.volumeXp - x.volumeXp)

    return reply.send({ data })
  })
}
