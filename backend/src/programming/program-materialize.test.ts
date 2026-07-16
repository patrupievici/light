import { describe, it, expect } from 'vitest'
import {
  buildDayExercises,
  sessionToWeekAndDay,
  weekInCycleFor,
  type ResolvedSlotMeta,
  type SlotLoad,
} from './program-materialize'
import { getProgramTemplate, PROGRAM_TEMPLATES } from './program-templates'

/** Build a meta map for every slot of a template day, marking compounds as weighted. */
function metaForDay(templateId: string, dayInRotation: number): Record<string, ResolvedSlotMeta> {
  const t = getProgramTemplate(templateId)!
  const day = t.days[dayInRotation]
  const out: Record<string, ResolvedSlotMeta> = {}
  for (const s of day.slots) {
    out[s.slotKey] = {
      exerciseId: `id_${s.slotKey}`,
      name: s.exercise,
      equipment: 'barbell',
      movementPattern: 'squat', // a rampable pattern so warmups generate
      rankModel: 'WEIGHTED',
      category: 'strength',
    }
  }
  return out
}

function loadsForDay(templateId: string, dayInRotation: number, weightKg: number): Record<string, SlotLoad> {
  const t = getProgramTemplate(templateId)!
  const day = t.days[dayInRotation]
  const out: Record<string, SlotLoad> = {}
  for (const s of day.slots) out[s.slotKey] = { suggestedWeightKg: weightKg, suggestedReps: 10, reason: 'test' }
  return out
}

describe('session math', () => {
  it('maps session index to week + rotation day', () => {
    // daysPerWeek 4, rotation length 4
    expect(sessionToWeekAndDay(0, 4, 4)).toEqual({ week: 1, dayInRotation: 0 })
    expect(sessionToWeekAndDay(3, 4, 4)).toEqual({ week: 1, dayInRotation: 3 })
    expect(sessionToWeekAndDay(4, 4, 4)).toEqual({ week: 2, dayInRotation: 0 })
    // StrongLifts: 3 sessions/week, 2-day A/B rotation → week 2 starts at session 3
    expect(sessionToWeekAndDay(3, 3, 2)).toEqual({ week: 2, dayInRotation: 1 })
  })

  it('weekInCycleFor wraps on cadence', () => {
    expect(weekInCycleFor(1, 4)).toBe(1)
    expect(weekInCycleFor(4, 4)).toBe(4)
    expect(weekInCycleFor(5, 4)).toBe(1)
  })
})

describe('percentage program materialization (5/3/1 BBB)', () => {
  it('week 1 main lift is the 5s wave off the training max, with warmups', () => {
    const day = buildDayExercises({
      template: getProgramTemplate('531_bbb')!,
      week: 1,
      dayInRotation: 0, // Overhead Press day
      tm: { 'Overhead Press': 60 },
      meta: metaForDay('531_bbb', 0),
      loads: {},
    })
    const main = day.exercises[0]
    expect(main.setsDetail).toHaveLength(3)
    expect(main.setsDetail!.at(-1)!.amrap).toBe(true)
    // every working load is plate-rounded (multiple of 2.5)
    for (const s of main.setsDetail!) expect(s.weightKg! % 2.5).toBe(0)
    expect(main.warmups).toHaveLength(2)
    expect((main.warmups?.length ?? 0) + main.setsDetail!.length).toBeLessThanOrEqual(5)
    expect(day.isDeload).toBe(false)

    const bbb = day.exercises[1]
    expect(bbb.setsDetail).toHaveLength(5)
    expect(bbb.setsDetail!.every((s) => s.reps === 10)).toBe(true)
  })

  it('week 4 is the built-in deload wave (no AMRAP)', () => {
    const day = buildDayExercises({
      template: getProgramTemplate('531_bbb')!,
      week: 4,
      dayInRotation: 0,
      tm: { 'Overhead Press': 60 },
      meta: metaForDay('531_bbb', 0),
      loads: {},
    })
    expect(day.isDeload).toBe(true)
    expect(day.exercises[0].setsDetail!.some((s) => s.amrap)).toBe(false)
  })

  it('leaves weights null when no training max is set', () => {
    const day = buildDayExercises({
      template: getProgramTemplate('nsuns_4day')!,
      week: 1,
      dayInRotation: 0,
      tm: {}, // none seeded
      meta: metaForDay('nsuns_4day', 0),
      loads: loadsForDay('nsuns_4day', 0, 0),
    })
    expect(day.exercises[0].setsDetail!.every((s) => s.weightKg === null)).toBe(true)
  })
})

describe('linear program materialization (StrongLifts 5x5)', () => {
  it('uses history-driven load uniformly with a warmup ramp', () => {
    const day = buildDayExercises({
      template: getProgramTemplate('stronglifts_5x5')!,
      week: 1,
      dayInRotation: 0,
      tm: {},
      meta: metaForDay('stronglifts_5x5', 0),
      loads: loadsForDay('stronglifts_5x5', 0, 100),
    })
    const squat = day.exercises[0]
    expect(squat.sets).toBe(5)
    expect(squat.reps).toBe(5)
    expect(squat.suggestedWeightKg).toBe(100)
    expect(squat.setsDetail).toBeUndefined() // uniform → converter expands
    expect(squat.warmups).toBeUndefined()
    expect(day.isDeload).toBe(false) // SL has no scheduled deload
  })
})

describe('double program deload (Upper/Lower, cadence 4)', () => {
  it('week 4 trims a set and backs off the load', () => {
    const normal = buildDayExercises({
      template: getProgramTemplate('upper_lower_4day')!,
      week: 1,
      dayInRotation: 0,
      tm: {},
      meta: metaForDay('upper_lower_4day', 0),
      loads: loadsForDay('upper_lower_4day', 0, 100),
    })
    const deload = buildDayExercises({
      template: getProgramTemplate('upper_lower_4day')!,
      week: 4,
      dayInRotation: 0,
      tm: {},
      meta: metaForDay('upper_lower_4day', 0),
      loads: loadsForDay('upper_lower_4day', 0, 100),
    })
    expect(deload.isDeload).toBe(true)
    expect(deload.exercises[0].suggestedWeightKg!).toBeLessThan(normal.exercises[0].suggestedWeightKg!)
    expect(deload.exercises[0].sets).toBeLessThan(normal.exercises[0].sets)
  })
})

describe('program tracker set budget', () => {
  it('keeps every exercise in every program day at five preset rows or fewer', () => {
    for (const template of PROGRAM_TEMPLATES) {
      const trainingMaxes = Object.fromEntries(
        (template.trainingMaxLifts ?? []).map((name) => [name, 100]),
      )

      for (const week of [1, 2, 3, 4]) {
        for (let dayIndex = 0; dayIndex < template.days.length; dayIndex++) {
          const day = buildDayExercises({
            template,
            week,
            dayInRotation: dayIndex,
            tm: trainingMaxes,
            meta: metaForDay(template.id, dayIndex),
            loads: loadsForDay(template.id, dayIndex, 60),
          })

          for (const exercise of day.exercises) {
            const workingSets = exercise.setsDetail?.length ?? exercise.sets
            const totalSets = workingSets + (exercise.warmups?.length ?? 0)
            expect(
              totalSets,
              `${template.id}/week-${week}/${day.dayKey}/${exercise.name}`,
            ).toBeLessThanOrEqual(5)
          }
        }
      }
    }
  })
})
