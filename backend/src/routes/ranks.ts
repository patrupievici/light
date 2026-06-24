import { FastifyInstance } from 'fastify'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { srToLP, lpToTier, calcStrengthRatio, bestWorkSetForRank, resolveBwStrengthFraction } from '../services/ranking.service'

export async function rankRoutes(app: FastifyInstance) {
  // GET /v1/ranks/me — toate rangurile userului curent
  app.get('/me', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user

    const ranks = await prisma.userExerciseRank.findMany({
      where: { userId },
      include: { exercise: true },
      orderBy: { lpTotal: 'desc' },
    })

    const overallScore = ranks
      .slice(0, 10)
      .reduce((sum, r) => sum + r.lpTotal, 0)

    const overallTier = lpToTier(Math.floor(overallScore / 10))

    return reply.send({ ranks, overallScore, overallTier })
  })

  // GET /v1/ranks/exercises/:exerciseId — rang pe exercitiu specific
  app.get('/exercises/:exerciseId', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { exerciseId } = request.params as { exerciseId: string }

    const rank = await prisma.userExerciseRank.findUnique({
      where: { userId_exerciseId: { userId, exerciseId } },
      include: { exercise: true },
    })

    if (!rank) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Nu ai inca un rang pentru acest exercitiu',
        requestId: request.id,
      })
    }

    return reply.send({ rank, tier: lpToTier(rank.lpTotal) })
  })

  // GET /v1/ranks/exercises/:exerciseId/explain — explainability card
  app.get('/exercises/:exerciseId/explain', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { exerciseId } = request.params as { exerciseId: string }

    const [rank, profile, exercise] = await Promise.all([
      prisma.userExerciseRank.findUnique({
        where: { userId_exerciseId: { userId, exerciseId } },
        include: { exercise: true },
      }),
      prisma.userProfile.findUnique({ where: { userId } }),
      prisma.exercise.findUnique({ where: { id: exerciseId } }),
    ])

    if (!rank || !profile?.bodyweightKg) {
      return reply.code(404).send({
        error: 'NOT_FOUND',
        message: 'Rang sau profil negasit',
        requestId: request.id,
      })
    }

    const bw = Number(profile.bodyweightKg)
    const currentTier = lpToTier(rank.lpTotal)
    const nextTierLP = (Math.floor(rank.lpTotal / 100) + 1) * 100
    const nextTierName = lpToTier(nextTierLP)
    const rankModel = exercise?.rankModel ?? 'WEIGHTED'
    const isBwReps = rankModel === 'BW_REPS'

    const targetWeightAt5Reps = (() => {
      if (isBwReps) return null
      const targetSR = nextTierLP / 100
      const targetE1RM = targetSR * bw
      return Math.round((targetE1RM / (1 + 5 / 30)) * 2.5) / 2.5
    })()

    const bwFrac =
      exercise != null
        ? resolveBwStrengthFraction(exercise.name, exercise.rankModel, exercise.bwStrengthFraction)
        : null

    const explanation = isBwReps
      ? `Rang calistenics (BW_REPS): e1RM echivalent = sarcină efectivă × (1 + repetări/30), cu sarcină efectivă ≈ ${(bwFrac ?? 0).toFixed(2)}× greutate corporală + kg extra în set. SR = e1RM / ${bw} kg = ${Number(rank.strengthRatio).toFixed(3)}; e1RM echivalent: ${Number(rank.bestE1rmKg).toFixed(1)} kg.`
      : `Rangul tau se bazeaza pe raportul forta/greutate: ${Number(rank.strengthRatio).toFixed(3)}. Best e1RM: ${Number(rank.bestE1rmKg).toFixed(1)} kg la ${bw} kg greutate corporala.`

    return reply.send({
      exercise: exercise?.name,
      rankModel,
      currentLP: rank.lpTotal,
      currentTier,
      bestE1rmKg: rank.bestE1rmKg,
      strengthRatio: rank.strengthRatio,
      bodyweightAtCalc: bw,
      bwStrengthFraction: isBwReps ? bwFrac : null,
      nextTier: {
        name: nextTierName,
        lpNeeded: nextTierLP,
        lpRemaining: nextTierLP - rank.lpTotal,
        estimatedWeightAt5Reps: targetWeightAt5Reps,
      },
      explanation,
    })
  })

  // GET /v1/ranks/leaderboard — leaderboard sezon curent
  app.get('/leaderboard', { preHandler: authenticate }, async (request, reply) => {
    const query = request.query as { exerciseId?: string; limit?: string }
    const limit = Math.min(100, parseInt(query.limit ?? '50'))

    const activeSeason = await prisma.season.findFirst({
      where: {
        startsAt: { lte: new Date() },
        endsAt: { gte: new Date() },
      },
    })

    if (!activeSeason) {
      return reply.send({ leaderboard: [], season: null })
    }

    const leaderboard = await prisma.userSeasonStat.findMany({
      where: { seasonId: activeSeason.id },
      orderBy: { lpSeason: 'desc' },
      take: limit,
      include: {
        user: { include: { profile: true } },
      },
    })

    return reply.send({
      season: activeSeason,
      leaderboard: leaderboard.map((entry, idx) => ({
        rank: idx + 1,
        userId: entry.userId,
        username: entry.user.profile?.username ?? 'Anonymous',
        displayName: entry.user.profile?.displayName ?? 'Anonymous',
        lpSeason: entry.lpSeason,
      })),
    })
  })

  // GET /v1/ranks/me/history — progression history pentru toate exercitiile
  app.get('/me/history', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const q = request.query as { exerciseId?: string }

    // Obtine toate rank-urile userului
    const rankFilter: any = { userId }
    if (q.exerciseId) {
      rankFilter.exerciseId = q.exerciseId
    }

    const ranks = await prisma.userExerciseRank.findMany({
      where: rankFilter,
      include: { exercise: true },
      orderBy: [{ exerciseId: 'asc' }, { updatedAt: 'desc' }],
    })

    // Obtine toate workout-urile userului cu seturile pentru a calcula istoricul
    const workouts = await prisma.workout.findMany({
      where: {
        userId,
        status: { in: ['completed', 'posted'] },
      },
      include: {
        exercises: {
          include: {
            exercise: true,
            sets: {
              where: { tag: 'WORK', isCompleted: true },
            },
          },
        },
      },
      orderBy: { startedAt: 'asc' },
    })

    // Calculeaza e1RM history per exercise
    interface ExerciseProgression {
      exerciseId: string
      exerciseName: string
      currentLP: number
      currentTier: string
      bestE1rmKg: number
      dataPoints: Array<{
        date: string
        e1rmKg: number
        lp: number
        tier: string
        weightKg: number
        reps: number
      }>
    }

    const progressionMap = new Map<string, ExerciseProgression>()

    const profileRow = await prisma.userProfile.findUnique({ where: { userId } })
    const bwHist = profileRow?.bodyweightKg ? Number(profileRow.bodyweightKg) : 70

    for (const workout of workouts) {
      for (const we of workout.exercises) {
        if (!we.exercise.isRanked) continue
        if (we.exercise.rankModel !== 'WEIGHTED' && we.exercise.rankModel !== 'BW_REPS') continue
        if (we.sets.length === 0) continue

        const bestSet = bestWorkSetForRank(we.exercise, bwHist, we.sets)
        if (!bestSet) continue

        const sr = calcStrengthRatio(bestSet.e1rm, bwHist)
        const lp = srToLP(sr, we.exercise.name, we.exercise.rankModel)
        const tier = lpToTier(lp)
        const date = workout.startedAt.toISOString().slice(0, 10)

        if (!progressionMap.has(we.exerciseId)) {
          const currentRank = ranks.find(r => r.exerciseId === we.exerciseId)
          progressionMap.set(we.exerciseId, {
            exerciseId: we.exerciseId,
            exerciseName: we.exercise.name,
            currentLP: currentRank?.lpTotal ?? 0,
            currentTier: currentRank ? lpToTier(currentRank.lpTotal) : 'Iron',
            bestE1rmKg: currentRank ? Number(currentRank.bestE1rmKg) : 0,
            dataPoints: [],
          })
        }

        const progression = progressionMap.get(we.exerciseId)!
        progression.dataPoints.push({
          date,
          e1rmKg: Math.round(bestSet.e1rm * 10) / 10,
          lp,
          tier,
          weightKg: bestSet.weightKg,
          reps: bestSet.reps,
        })
      }
    }

    // Update best E1RM din rank-urile curente
    for (const rank of ranks) {
      if (progressionMap.has(rank.exerciseId)) {
        const progression = progressionMap.get(rank.exerciseId)!
        progression.bestE1rmKg = Number(rank.bestE1rmKg)
        progression.currentLP = rank.lpTotal
        progression.currentTier = lpToTier(rank.lpTotal)
      }
    }

    const progressions = Array.from(progressionMap.values())
      .map(p => ({
        ...p,
        dataPoints: p.dataPoints.sort((a, b) => a.date.localeCompare(b.date)),
      }))
      .sort((a, b) => b.currentLP - a.currentLP)

    return reply.send({ progressions })
  })
}
