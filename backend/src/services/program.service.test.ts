import { describe, it, expect } from 'vitest'
import {
  computeProgramAdvance,
  programExerciseDefaultsFor,
  readState,
  type ProgramState,
} from './program.service'
import { getProgramTemplate } from '../programming/program-templates'

/** Apply N sessions of advance, threading state through. */
function advanceN(templateId: string, totalWeeks: number, n: number, start: ProgramState) {
  const tpl = getProgramTemplate(templateId)!
  let st = start
  let last = { sessionIndex: st.sessionIndex, tm: st.tm, currentWeek: 1, status: 'active' as 'active' | 'completed' }
  for (let i = 0; i < n; i++) {
    last = computeProgramAdvance(tpl, st, totalWeeks)
    st = { sessionIndex: last.sessionIndex, tm: last.tm }
  }
  return last
}

describe('readState', () => {
  it('defaults missing state and keeps numeric training maxes', () => {
    expect(readState(null)).toEqual({ sessionIndex: 0, tm: {} })
    expect(readState({ sessionIndex: 3, tm: { Squat: 140, junk: 'x' } })).toEqual({
      sessionIndex: 3,
      tm: { Squat: 140 },
    })
  })
})

describe('programExerciseDefaultsFor', () => {
  it('keeps StrongLifts core lifts mapped to ranked barbell exercises', () => {
    expect(programExerciseDefaultsFor('Squat')).toMatchObject({
      name: 'Squat',
      equipment: 'barbell',
      movementPattern: 'squat',
      rankModel: 'WEIGHTED',
    })
    expect(programExerciseDefaultsFor('Bench Press')).toMatchObject({
      name: 'Bench Press',
      equipment: 'barbell',
      movementPattern: 'horizontal_push',
      rankModel: 'WEIGHTED',
    })
    expect(programExerciseDefaultsFor('Barbell Row')).toMatchObject({
      name: 'Barbell Row',
      equipment: 'barbell',
      movementPattern: 'horizontal_pull',
      rankModel: 'WEIGHTED',
    })
  })
})

describe('computeProgramAdvance — 5/3/1 (cycle-boundary TM bumps)', () => {
  const tm = { Squat: 140, 'Bench Press': 100, Deadlift: 180, 'Overhead Press': 60 }

  it('does not bump TM within a cycle', () => {
    // 4 days/week, 4-day rotation → sessions 0..3 are week 1.
    const after1 = advanceN('531_bbb', 8, 1, { sessionIndex: 0, tm })
    expect(after1.currentWeek).toBe(1)
    expect(after1.tm).toEqual(tm) // unchanged mid-week-1

    // Cross into week 2 (mid-cycle): still no bump.
    const after4 = advanceN('531_bbb', 8, 4, { sessionIndex: 0, tm })
    expect(after4.currentWeek).toBe(2)
    expect(after4.tm).toEqual(tm)
  })

  it('bumps TM when a new 4-week cycle starts (+5kg lower / +2.5kg upper)', () => {
    // 16 sessions = end of week 4; the 16th advance lands week 5 (new cycle).
    const after16 = advanceN('531_bbb', 12, 16, { sessionIndex: 0, tm })
    expect(after16.currentWeek).toBe(5)
    expect(after16.tm).toEqual({
      Squat: 145,
      'Bench Press': 102.5,
      Deadlift: 185,
      'Overhead Press': 62.5,
    })
  })
})

describe('computeProgramAdvance — nSuns (weekly TM bumps)', () => {
  it('bumps every new week', () => {
    const tm = { Squat: 140, 'Bench Press': 100, Deadlift: 180, 'Overhead Press': 60 }
    // nSuns: 4 days/week. After 4 sessions → week 2 → one weekly bump.
    const after4 = advanceN('nsuns_4day', 8, 4, { sessionIndex: 0, tm })
    expect(after4.currentWeek).toBe(2)
    expect(after4.tm.Squat).toBe(145)
    expect(after4.tm['Bench Press']).toBe(102.5)
  })
})

describe('computeProgramAdvance — completion', () => {
  it('marks completed once past the final week', () => {
    const tpl = getProgramTemplate('full_body_3day')! // 3 days/week
    // totalWeeks 1 → finishing the 3 sessions of week 1 tips into week 2 > 1.
    let st: ProgramState = { sessionIndex: 0, tm: {} }
    let res = computeProgramAdvance(tpl, st, 1)
    // session 1,2 still week 1; session 3 → week 2 > totalWeeks
    res = computeProgramAdvance(tpl, { sessionIndex: 2, tm: {} }, 1)
    expect(res.status).toBe('completed')
    expect(res.currentWeek).toBe(1) // clamped to totalWeeks
  })
})
