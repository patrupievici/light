// Challenge recalculation — the bridge between real workout data and the pure
// scoring engine. Loads a participant's valid workouts in the challenge window,
// runs challenge-scoring.service, and persists the official score + rank onto
// challenge_participants (backend = source of truth for standings).
//
// Invoked from the workout complete/edit/delete flow so the leaderboard updates
// automatically — no manual progress logging for auto-scored challenges.

import { prisma } from '../lib/prisma'
import {
  computeScore,
  rankByScore,
  validWorkoutsInWindow,
  epleyE1rm,
  DEFAULT_RULES,
  type ChallengeRules,
  type ChallengeScoringType,
  type ScoringWorkout,
  type WorkoutTag,
} from './challenge-scoring.service'

const NINETY_DAYS_MS = 90 * 24 * 60 * 60 * 1000

function rulesFor(c: {
  ruleMinDurationMin: number | null
  ruleMinSets: number | null
  ruleMinExercises: number | null
  ruleMaxPerDay: number | null
}): ChallengeRules {
  return {
    minDurationMin: c.ruleMinDurationMin ?? DEFAULT_RULES.minDurationMin,
    minExercises: c.ruleMinExercises ?? DEFAULT_RULES.minExercises,
    minSets: c.ruleMinSets ?? DEFAULT_RULES.minSets,
    maxPerDayMostWorkouts: c.ruleMaxPerDay ?? DEFAULT_RULES.maxPerDayMostWorkouts,
    maxPerDayStreak: DEFAULT_RULES.maxPerDayStreak,
  }
}

async function loadScoringWorkouts(userId: string, gte: Date, lte: Date): Promise<ScoringWorkout[]> {
  const rows = await prisma.workout.findMany({
    where: { userId, status: { in: ['completed', 'posted'] }, startedAt: { gte, lte } },
    include: { exercises: { include: { sets: true } } },
  })
  return rows.map((w) => ({
    startedAt: w.startedAt,
    endedAt: w.endedAt,
    exercises: w.exercises.map((ex) => ({
      exerciseId: ex.exerciseId,
      sets: ex.sets.map((s) => ({
        weightKg: Number(s.weightKg),
        reps: s.reps,
        tag: s.tag as WorkoutTag,
        isCompleted: s.isCompleted,
      })),
    })),
  }))
}

/** Best Epley e1RM for an exercise in the 90 days BEFORE the challenge start. */
async function prBaseline(userId: string, exerciseId: string, startAt: Date): Promise<number | null> {
  const from = new Date(startAt.getTime() - NINETY_DAYS_MS)
  const ws = await loadScoringWorkouts(userId, from, new Date(startAt.getTime() - 1))
  let best: number | null = null
  for (const w of ws) {
    for (const ex of w.exercises) {
      if (ex.exerciseId !== exerciseId) continue
      for (const s of ex.sets) {
        if (s.tag !== 'WORK' || !s.isCompleted) continue
        const e = epleyE1rm(s.weightKg, s.reps)
        if (e != null && (best == null || e > best)) best = e
      }
    }
  }
  return best
}

/** Recompute + persist scores/ranks for one auto-scored challenge. No-op for
 *  legacy/manual challenges (scoringType null). */
export async function recomputeChallenge(challengeId: string): Promise<void> {
  const c = await prisma.challenge.findUnique({ where: { id: challengeId } })
  if (!c || !c.scoringType) return

  const type = c.scoringType as ChallengeScoringType
  const rules = rulesFor(c)
  const startAt = c.startsAt ?? c.createdAt
  const endAt = c.endsAt

  const participants = await prisma.challengeParticipant.findMany({
    where: { challengeId, status: 'accepted' },
  })

  const scored: { userId: string; result: ReturnType<typeof computeScore> }[] = []
  for (const p of participants) {
    const acceptedAt = p.acceptedAt ?? p.joinedAt
    const all = await loadScoringWorkouts(p.userId, startAt, endAt)
    // Fairness (spec): only workouts done AFTER the user accepted count.
    const afterAccept = all.filter((w) => w.startedAt >= acceptedAt)
    const valid = validWorkoutsInWindow(afterAccept, rules, startAt, endAt)
    let baseline: number | null = null
    if (type === 'pr_battle' && c.ruleExerciseId) {
      baseline = await prBaseline(p.userId, c.ruleExerciseId, startAt)
    }
    const result = computeScore({
      type,
      validWorkouts: valid,
      rules,
      exerciseId: c.ruleExerciseId ?? undefined,
      baselineE1rm: baseline,
      targetDays: c.ruleTargetDays ?? undefined,
    })
    scored.push({ userId: p.userId, result })
  }

  const ranked = rankByScore(scored)
  const now = new Date()
  await Promise.all(
    ranked.map((r) =>
      prisma.challengeParticipant.update({
        where: { challengeId_userId: { challengeId, userId: r.userId } },
        data: { score: r.result.score, rank: r.rank, lastScoreUpdate: now },
      }),
    ),
  )
}

/** Recompute + persist ONLY `userId`'s own score slot for one challenge, without
 *  reloading the whole roster. This is the SLO-safe path for POST /complete: a
 *  completion only changes the completing user's data, so we recompute a single
 *  participant instead of N heavy per-participant history loads.
 *
 *  NOTE: cross-participant re-ranking is intentionally DEFERRED here — we update
 *  this user's `score` immediately but leave `rank` untouched. The full re-rank
 *  (recomputeChallenge) still runs on the standings-read / background path so the
 *  leaderboard order settles lazily without blocking the completion request. */
export async function recomputeParticipantScore(challengeId: string, userId: string): Promise<void> {
  const c = await prisma.challenge.findUnique({ where: { id: challengeId } })
  if (!c || !c.scoringType) return

  const p = await prisma.challengeParticipant.findUnique({
    where: { challengeId_userId: { challengeId, userId } },
  })
  if (!p || p.status !== 'accepted') return

  const type = c.scoringType as ChallengeScoringType
  const rules = rulesFor(c)
  const startAt = c.startsAt ?? c.createdAt
  const endAt = c.endsAt
  const acceptedAt = p.acceptedAt ?? p.joinedAt

  const all = await loadScoringWorkouts(userId, startAt, endAt)
  // Fairness (spec): only workouts done AFTER the user accepted count.
  const afterAccept = all.filter((w) => w.startedAt >= acceptedAt)
  const valid = validWorkoutsInWindow(afterAccept, rules, startAt, endAt)
  let baseline: number | null = null
  if (type === 'pr_battle' && c.ruleExerciseId) {
    baseline = await prBaseline(userId, c.ruleExerciseId, startAt)
  }
  const result = computeScore({
    type,
    validWorkouts: valid,
    rules,
    exerciseId: c.ruleExerciseId ?? undefined,
    baselineE1rm: baseline,
    targetDays: c.ruleTargetDays ?? undefined,
  })

  await prisma.challengeParticipant.update({
    where: { challengeId_userId: { challengeId, userId } },
    data: { score: result.score, lastScoreUpdate: new Date() },
  })
}

/** Recompute ONLY the completing user's score across their active, auto-scored
 *  joined challenges. Cheap enough (one participant per challenge, not the whole
 *  roster) to run synchronously on the POST /complete hot path. */
export async function recomputeCompletingUserChallenges(userId: string): Promise<void> {
  const now = new Date()
  const parts = await prisma.challengeParticipant.findMany({
    where: {
      userId,
      status: 'accepted',
      challenge: { scoringType: { not: null }, endsAt: { gte: now } },
    },
    select: { challengeId: true },
  })
  for (const p of parts) {
    await recomputeParticipantScore(p.challengeId, userId)
  }
}

/** Recompute every active, auto-scored challenge this user participates in.
 *  Full-roster re-rank — use on the standings-read / background path, NOT
 *  synchronously in POST /complete (see recomputeCompletingUserChallenges). */
export async function recomputeUserChallenges(userId: string): Promise<void> {
  const now = new Date()
  const parts = await prisma.challengeParticipant.findMany({
    where: {
      userId,
      status: 'accepted',
      challenge: { scoringType: { not: null }, endsAt: { gte: now } },
    },
    select: { challengeId: true },
  })
  for (const p of parts) {
    await recomputeChallenge(p.challengeId)
  }
}
