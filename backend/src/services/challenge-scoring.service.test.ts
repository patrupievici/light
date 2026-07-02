import { describe, it, expect } from 'vitest'

import {
  epleyE1rm,
  workoutVolumeKg,
  completedWorkSets,
  workedExerciseCount,
  workoutDurationMin,
  isValidWorkout,
  longestConsecutiveRun,
  scoreWorkoutStreak,
  scoreMostWorkouts,
  scoreTotalVolume,
  scorePrBattle,
  scoreConsistency,
  rankByScore,
  DEFAULT_RULES,
  type ScoringWorkout,
  type ScoringSet,
} from './challenge-scoring.service'

const set = (weightKg: number, reps: number, tag: ScoringSet['tag'] = 'WORK', isCompleted = true): ScoringSet => ({
  weightKg,
  reps,
  tag,
  isCompleted,
})

function workout(day: string, durationMin: number, exercises: ScoringWorkout['exercises']): ScoringWorkout {
  const startedAt = new Date(`${day}T08:00:00Z`)
  const endedAt = new Date(startedAt.getTime() + durationMin * 60000)
  return { startedAt, endedAt, exercises }
}

/** A clean valid workout (30 min, 3 exercises, 6 completed WORK sets). */
function validDay(day: string): ScoringWorkout {
  return workout(day, 30, [
    { exerciseId: 'a', sets: [set(60, 5), set(60, 5)] },
    { exerciseId: 'b', sets: [set(40, 8), set(40, 8)] },
    { exerciseId: 'c', sets: [set(20, 10), set(20, 10)] },
  ])
}

describe('e1RM (Epley)', () => {
  it('matches weight*(1+reps/30) for valid reps', () => {
    expect(epleyE1rm(80, 5)).toBeCloseTo(93.333, 2)
    expect(epleyE1rm(100, 1)).toBeCloseTo(103.333, 2)
  })
  it('rejects reps outside 1..12 and implausible loads', () => {
    expect(epleyE1rm(80, 13)).toBeNull()
    expect(epleyE1rm(80, 0)).toBeNull()
    expect(epleyE1rm(600, 12)).toBeNull() // > 600kg cap
    expect(epleyE1rm(0, 5)).toBeNull()
  })
})

describe('workout aggregates + validity', () => {
  it('volume counts only completed WORK sets', () => {
    const w = workout('2026-06-01', 20, [
      { exerciseId: 'a', sets: [set(60, 10), set(50, 10, 'WARMUP'), set(60, 10, 'WORK', false)] },
    ])
    expect(workoutVolumeKg(w)).toBe(600) // only the first set
    expect(completedWorkSets(w)).toBe(1)
    expect(workedExerciseCount(w)).toBe(1)
  })
  it('duration is endedAt-startedAt in minutes', () => {
    expect(workoutDurationMin(workout('2026-06-01', 45, []))).toBe(45)
    expect(workoutDurationMin({ startedAt: new Date(), endedAt: null, exercises: [] })).toBe(0)
  })
  it('isValidWorkout enforces 15 min / 3 exercises / 6 sets', () => {
    expect(isValidWorkout(validDay('2026-06-01'), DEFAULT_RULES)).toBe(true)
    // too short
    expect(isValidWorkout(workout('2026-06-01', 10, validDay('x').exercises), DEFAULT_RULES)).toBe(false)
    // too few exercises
    const twoEx = workout('2026-06-01', 30, [
      { exerciseId: 'a', sets: [set(60, 5), set(60, 5), set(60, 5)] },
      { exerciseId: 'b', sets: [set(60, 5), set(60, 5), set(60, 5)] },
    ])
    expect(isValidWorkout(twoEx, DEFAULT_RULES)).toBe(false)
  })
})

describe('longestConsecutiveRun', () => {
  it('finds the longest run across gaps', () => {
    expect(longestConsecutiveRun(['2026-06-01', '2026-06-02', '2026-06-03'])).toBe(3)
    expect(longestConsecutiveRun(['2026-06-01', '2026-06-02', '2026-06-05', '2026-06-06', '2026-06-07'])).toBe(3)
    expect(longestConsecutiveRun([])).toBe(0)
    // month boundary
    expect(longestConsecutiveRun(['2026-05-31', '2026-06-01'])).toBe(2)
  })
})

describe('Workout Streak scoring', () => {
  it('longest*100 + total_valid_days*10 (spec example → 560)', () => {
    const valid = ['2026-06-01', '2026-06-02', '2026-06-03', '2026-06-04', '2026-06-05', '2026-06-10'].map(validDay)
    const r = scoreWorkoutStreak(valid)
    expect(r.score).toBe(5 * 100 + 6 * 10) // 560
    expect(r.metric).toBe('5-day streak')
  })
})

describe('Most Workouts scoring', () => {
  it('counts ≤2 per day, *100 + active_days*10', () => {
    const valid = [
      validDay('2026-06-01'), validDay('2026-06-01'),
      validDay('2026-06-02'), validDay('2026-06-02'),
      validDay('2026-06-03'),
    ]
    const r = scoreMostWorkouts(valid, DEFAULT_RULES)
    expect(r.score).toBe(5 * 100 + 3 * 10) // 530
  })
  it('caps a heavy day at 2 counted', () => {
    const valid = [validDay('2026-06-01'), validDay('2026-06-01'), validDay('2026-06-01')]
    const r = scoreMostWorkouts(valid, DEFAULT_RULES)
    expect(r.score).toBe(2 * 100 + 1 * 10) // 210 — third same-day workout ignored
  })
})

describe('Total Volume scoring', () => {
  it('floor(volume/100); primary metric is kg (spec → 14,237 kg / 142)', () => {
    const w = workout('2026-06-01', 30, [
      { exerciseId: 'a', sets: [set(1423, 10), set(7, 1)] }, // 14230 + 7 = 14237
    ])
    const r = scoreTotalVolume([w])
    expect(r.score).toBe(142)
    expect(r.metric).toBe('14,237 kg')
  })
})

describe('Exercise PR Battle scoring', () => {
  it('max(0, best_e1RM − baseline) * 20', () => {
    // best set 85×5 → e1RM 99.1667; baseline 90 → improvement 9.1667 → 183
    const valid = [
      workout('2026-06-02', 30, [{ exerciseId: 'bench', sets: [set(85, 5)] }]),
    ]
    const r = scorePrBattle(valid, 'bench', 90)
    expect(r.score).toBe(Math.round((85 * (1 + 5 / 30) - 90) * 20)) // 183
    expect(r.metric).toContain('e1RM')
  })
  it('no prior baseline → first lift is the baseline, improvement 0', () => {
    const valid = [workout('2026-06-02', 30, [{ exerciseId: 'bench', sets: [set(80, 5)] }])]
    const r = scorePrBattle(valid, 'bench', null)
    expect(r.score).toBe(0)
  })
  it('never negative when user gets weaker', () => {
    const valid = [workout('2026-06-02', 30, [{ exerciseId: 'bench', sets: [set(60, 5)] }])]
    expect(scorePrBattle(valid, 'bench', 120).score).toBe(0)
  })
})

describe('Consistency scoring', () => {
  it('completed*100 + 25 bonus when all target days hit (spec → 425)', () => {
    const valid = ['2026-06-01', '2026-06-02', '2026-06-03', '2026-06-04'].map(validDay)
    expect(scoreConsistency(valid, 4).score).toBe(425)
  })
  it('no bonus when target not met', () => {
    const valid = ['2026-06-01', '2026-06-02', '2026-06-03'].map(validDay)
    expect(scoreConsistency(valid, 4).score).toBe(300)
  })
})

describe('rankByScore + tie-breakers', () => {
  it('ranks by score then tie-breakers (higher wins)', () => {
    const ranked = rankByScore([
      { id: 'a', result: { score: 1200, metric: '', tiebreak: [5, 0] } },
      { id: 'b', result: { score: 1250, metric: '', tiebreak: [3, 0] } },
      { id: 'c', result: { score: 1200, metric: '', tiebreak: [9, 0] } }, // beats a on tiebreak
    ])
    expect(ranked.map((r) => r.id)).toEqual(['b', 'c', 'a'])
    expect(ranked.map((r) => r.rank)).toEqual([1, 2, 3])
  })
})
