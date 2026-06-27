import { describe, it, expect } from 'vitest'

import { exdbEntry, matchExdb } from './exercise-media'

// A small stand-in for the ExerciseDB catalog (names mirror its lowercase,
// equipment-prefixed style). Locks the name+equipment matcher so it keeps
// resolving Zvelt's generic built-in names to the right ExerciseDB id.
const CATALOG = [
  exdbEntry('0001', 'barbell full squat', 'barbell'),
  exdbEntry('0002', 'bodyweight squat', 'body weight'),
  exdbEntry('0003', 'barbell bench press', 'barbell'),
  exdbEntry('0004', 'dumbbell bench press', 'dumbbell'),
  exdbEntry('0005', 'barbell deadlift', 'barbell'),
  exdbEntry('0006', 'dumbbell biceps curl', 'dumbbell'),
  exdbEntry('0007', 'barbell biceps curl', 'barbell'),
  exdbEntry('0008', 'dumbbell lateral raise', 'dumbbell'),
  exdbEntry('0009', 'pull up', 'body weight'),
  exdbEntry('0010', 'push up', 'body weight'),
  exdbEntry('0011', 'cable lateral raise', 'cable'),
]

describe('matchExdb — Zvelt name+equipment → ExerciseDB id', () => {
  it('prefers the equipment-matching candidate for a generic name', () => {
    expect(matchExdb(CATALOG, 'Squat', 'barbell')).toBe('0001')
    expect(matchExdb(CATALOG, 'Bench Press', 'barbell')).toBe('0003')
    expect(matchExdb(CATALOG, 'Bench Press', 'dumbbell')).toBe('0004')
    expect(matchExdb(CATALOG, 'Dumbbell Curl', 'dumbbell')).toBe('0006')
    expect(matchExdb(CATALOG, 'Lateral Raise', 'dumbbell')).toBe('0008')
    expect(matchExdb(CATALOG, 'Lateral Raise', 'cable')).toBe('0011')
  })

  it('matches hyphenated / punctuated names after normalization', () => {
    expect(matchExdb(CATALOG, 'Pull-up', 'bodyweight')).toBe('0009')
    expect(matchExdb(CATALOG, 'Push-up', 'bodyweight')).toBe('0010')
  })

  it('takes an exact normalized name even with odd casing/spacing', () => {
    expect(matchExdb(CATALOG, '  BARBELL   Deadlift ', 'barbell')).toBe('0005')
  })

  it('returns null when no candidate contains all the wanted tokens', () => {
    expect(matchExdb(CATALOG, 'Nordic Ham Curl', 'bodyweight')).toBeNull()
    expect(matchExdb(CATALOG, '', 'barbell')).toBeNull()
  })

  it('still resolves (without equipment) by fewest-extra-tokens', () => {
    // No equipment hint → bodyweight squat (1 extra token) beats barbell full squat (2).
    expect(matchExdb(CATALOG, 'Squat', null)).toBe('0002')
  })
})
