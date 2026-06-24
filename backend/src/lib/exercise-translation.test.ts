import { describe, it, expect } from 'vitest'

import {
  localizeExercise,
  inheritClassification,
  normalizeLocale,
  type ExerciseTranslationRow,
} from './exercise-translation'

const ex = { name: 'Back Squat', description: 'A squat with the bar on the back.' }

const roRows: ExerciseTranslationRow[] = [
  { locale: 'ro', name: 'Genuflexiuni cu bara', description: 'Genuflexiuni cu bara pe spate.' },
  { locale: 'es', name: 'Sentadilla con barra', description: null },
]

describe('normalizeLocale', () => {
  it('lowercases, trims, and normalizes separators', () => {
    expect(normalizeLocale('  RO-RO ')).toBe('ro-ro')
    expect(normalizeLocale('es_ES')).toBe('es-es')
  })
  it('returns empty for nullish/blank input', () => {
    expect(normalizeLocale(undefined)).toBe('')
    expect(normalizeLocale(null)).toBe('')
    expect(normalizeLocale('   ')).toBe('')
  })
})

describe('localizeExercise — fallback chain', () => {
  it('returns canonical name when no locale requested', () => {
    const out = localizeExercise(ex, roRows, undefined)
    expect(out.name).toBe('Back Squat')
    expect(out.description).toBe(ex.description)
    expect(out.resolvedLocale).toBe('')
  })

  it('returns canonical when no translation exists for locale', () => {
    const out = localizeExercise(ex, roRows, 'de')
    expect(out.name).toBe('Back Squat')
    expect(out.resolvedLocale).toBe('')
  })

  it('returns canonical when there are no translation rows', () => {
    const out = localizeExercise(ex, [], 'ro')
    expect(out.name).toBe('Back Squat')
    expect(out.resolvedLocale).toBe('')
  })

  it('returns the localized name for an exact locale match', () => {
    const out = localizeExercise(ex, roRows, 'ro')
    expect(out.name).toBe('Genuflexiuni cu bara')
    expect(out.description).toBe('Genuflexiuni cu bara pe spate.')
    expect(out.resolvedLocale).toBe('ro')
  })

  it('falls back from regional tag to base language (ro-RO -> ro)', () => {
    const out = localizeExercise(ex, roRows, 'ro-RO')
    expect(out.name).toBe('Genuflexiuni cu bara')
    expect(out.resolvedLocale).toBe('ro')
  })

  it('falls back to canonical description when translation omits it', () => {
    const out = localizeExercise(ex, roRows, 'es')
    expect(out.name).toBe('Sentadilla con barra')
    expect(out.description).toBe(ex.description) // canonical kept
    expect(out.resolvedLocale).toBe('es')
  })

  it('ignores blank-name translation rows and falls back', () => {
    const rows: ExerciseTranslationRow[] = [{ locale: 'ro', name: '   ', description: 'x' }]
    const out = localizeExercise(ex, rows, 'ro')
    expect(out.name).toBe('Back Squat')
    expect(out.resolvedLocale).toBe('')
  })

  it('handles a null canonical description', () => {
    const out = localizeExercise({ name: 'Plank', description: null }, [], 'ro')
    expect(out.name).toBe('Plank')
    expect(out.description).toBeNull()
  })
})

describe('inheritClassification', () => {
  const defaults = { movementPattern: 'skill_stability', rankModel: 'WEIGHTED', category: 'strength' }
  const parent = { movementPattern: 'squat', rankModel: 'BW_REPS', category: 'bodyweight' }

  it('uses defaults when no parent and nothing provided', () => {
    expect(inheritClassification({}, null, defaults)).toEqual(defaults)
  })

  it('inherits every missing field from the parent', () => {
    expect(inheritClassification({}, parent, defaults)).toEqual(parent)
  })

  it('child-provided values always win over the parent', () => {
    const out = inheritClassification({ movementPattern: 'hinge' }, parent, defaults)
    expect(out.movementPattern).toBe('hinge') // explicit
    expect(out.rankModel).toBe('BW_REPS') // inherited
    expect(out.category).toBe('bodyweight') // inherited
  })

  it('falls through parent to defaults for fields the parent lacks', () => {
    const partialParent = { movementPattern: 'squat' } as typeof parent
    const out = inheritClassification({}, partialParent, defaults)
    expect(out.movementPattern).toBe('squat') // from parent
    expect(out.rankModel).toBe('WEIGHTED') // default
    expect(out.category).toBe('strength') // default
  })
})
