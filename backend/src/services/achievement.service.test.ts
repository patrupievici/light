import { describe, expect, it } from 'vitest'
import {
  achievementKeysForProgress,
  isProjectedSeasonTop10,
  type AchievementProgressSnapshot,
} from './achievement.service'

function progress(
  overrides: Partial<AchievementProgressSnapshot> = {},
): AchievementProgressSnapshot {
  return {
    workoutCount: 0,
    setCount: 0,
    earnedKeys: new Set(),
    maxLp: 0,
    distinctExerciseCount: 0,
    workoutStreak: 0,
    isSeasonTop10: false,
    ...overrides,
  }
}

describe('achievementKeysForProgress', () => {
  it('evaluates workout, set, exercise and streak thresholds together', () => {
    expect(achievementKeysForProgress(progress({
      workoutCount: 10,
      setCount: 100,
      distinctExerciseCount: 5,
      workoutStreak: 7,
    }))).toEqual(expect.arrayContaining([
      'first_workout',
      'workouts_10',
      'sets_10',
      'sets_100',
      'exercises_5',
      'streak_3',
      'streak_7',
    ]))
  })

  it('merges a rank calculated concurrently with the pre-rank snapshot', () => {
    expect(achievementKeysForProgress(progress(), { rankLpFloor: 320 }))
      .toEqual(expect.arrayContaining(['first_rank', 'rank_bronze', 'rank_gold']))
  })

  it('does not return achievements that are already earned', () => {
    expect(achievementKeysForProgress(progress({
      workoutCount: 1,
      earnedKeys: new Set(['first_workout']),
    }))).not.toContain('first_workout')
  })
})

describe('isProjectedSeasonTop10', () => {
  const top = Array.from({ length: 10 }, (_, index) => ({
    userId: `u${index}`,
    lpSeason: 1000 - index * 50,
  }))

  it('projects a user into the top 10 after the pending rank delta', () => {
    expect(isProjectedSeasonTop10('me', top, 400, 200)).toBe(true)
  })

  it('does not invent a standing for a user with no row and no LP gain', () => {
    expect(isProjectedSeasonTop10('me', top, null, 0)).toBe(false)
  })
})
