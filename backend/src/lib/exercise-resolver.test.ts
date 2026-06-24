import { describe, it, expect } from 'vitest'

import { normalizeExerciseName } from './exercise-resolver'

// Note: `resolveExerciseByName` hits Prisma — skipped here to keep tests
// pure. Tested via integration once we have a test DB set up.

describe('normalizeExerciseName', () => {
  it('lowercases and trims punctuation', () => {
    expect(normalizeExerciseName('Back Squat')).toBe('back squat')
    expect(normalizeExerciseName("Bench Press!")).toBe('bench press')
  })

  it('strips diacritics so "Genuflexiuni" matches "genuflexiuni"', () => {
    // Spanish: "Sentadilla con barra" → ascii
    expect(normalizeExerciseName('Sentadílla')).toBe('sentadilla')
  })

  it('drops common filler words (the/a/an/with/using/on/in/at)', () => {
    expect(normalizeExerciseName('Squat with the Barbell')).toBe('squat barbell')
    expect(normalizeExerciseName('Press on a Bench')).toBe('press bench')
  })

  it('normalizes hyphenated names to space-separated', () => {
    expect(normalizeExerciseName('Push-Up')).toBe('push up')
    expect(normalizeExerciseName('Pull-Up')).toBe('pull up')
  })

  it('collapses multiple whitespace into single spaces', () => {
    expect(normalizeExerciseName('Bench    Press')).toBe('bench press')
    expect(normalizeExerciseName('  Squat  \t  ')).toBe('squat')
  })

  it('returns empty string for input that is pure punctuation/whitespace', () => {
    expect(normalizeExerciseName('   ')).toBe('')
    expect(normalizeExerciseName('!!!')).toBe('')
  })

  it('handles equivalent spellings consistently', () => {
    // All three should normalize to the same thing
    const a = normalizeExerciseName('Barbell Back Squat')
    const b = normalizeExerciseName('barbell back squat')
    const c = normalizeExerciseName('  Barbell-Back-Squat ')
    expect(a).toBe(b)
    expect(b).toBe(c)
  })
})
