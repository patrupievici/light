import { describe, it, expect } from 'vitest'
import { redactHiddenSets } from './posts'

function post(overrides: Record<string, unknown> = {}) {
  return {
    userId: 'owner',
    privacySettings: { hideWeights: false, hideReps: false },
    workout: {
      exercises: [
        { sets: [{ weightKg: 100, reps: 5, tag: 'WORK' }] },
      ],
    },
    ...overrides,
  }
}

describe('redactHiddenSets — server-side privacy of hidden set data', () => {
  it('strips weightKg for a non-owner when hideWeights is set', () => {
    const p = post({ privacySettings: { hideWeights: true, hideReps: false } })
    const out = redactHiddenSets(p, 'viewer')
    expect(out.workout.exercises[0].sets[0].weightKg).toBeNull()
    expect(out.workout.exercises[0].sets[0].reps).toBe(5) // reps not hidden
  })

  it('strips reps for a non-owner when hideReps is set', () => {
    const p = post({ privacySettings: { hideWeights: false, hideReps: true } })
    const out = redactHiddenSets(p, 'viewer')
    expect(out.workout.exercises[0].sets[0].reps).toBeNull()
    expect(out.workout.exercises[0].sets[0].weightKg).toBe(100)
  })

  it('does NOT redact for the owner even when hidden', () => {
    const p = post({ privacySettings: { hideWeights: true, hideReps: true } })
    const out = redactHiddenSets(p, 'owner')
    expect(out.workout.exercises[0].sets[0].weightKg).toBe(100)
    expect(out.workout.exercises[0].sets[0].reps).toBe(5)
  })

  it('leaves data intact when nothing is hidden', () => {
    const out = redactHiddenSets(post(), 'viewer')
    expect(out.workout.exercises[0].sets[0].weightKg).toBe(100)
    expect(out.workout.exercises[0].sets[0].reps).toBe(5)
  })

  it('tolerates a post with no workout / no privacy settings', () => {
    expect(() =>
      redactHiddenSets({ userId: 'owner', privacySettings: null, workout: null }, 'viewer'),
    ).not.toThrow()
  })
})
