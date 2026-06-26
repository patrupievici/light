import { describe, it, expect } from 'vitest'
import fs from 'fs'
import path from 'path'
import { PROGRAM_TEMPLATES, getProgramTemplate, programTemplateSummaries } from './program-templates'

/** Catalog names actually seeded into the `exercises` table (ex('Name', ...)). */
function seededExerciseNames(): Set<string> {
  const seedPath = path.resolve(process.cwd(), 'prisma/seed.ts')
  const src = fs.readFileSync(seedPath, 'utf8')
  const names = new Set<string>()
  const re = /\bex\(\s*'([^']+)'/g
  let m: RegExpExecArray | null
  while ((m = re.exec(src)) !== null) names.add(m[1])
  return names
}

describe('program templates — structure', () => {
  it('ships the expected 8 templates with unique ids', () => {
    expect(PROGRAM_TEMPLATES).toHaveLength(8)
    const ids = PROGRAM_TEMPLATES.map((t) => t.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids).toEqual(
      expect.arrayContaining([
        'stronglifts_5x5', 'full_body_3day', 'upper_lower_4day', 'ppl_6day',
        'phul', 'arnold_split', 'nsuns_4day', '531_bbb',
      ]),
    )
  })

  it('each template has a non-empty rotation and valid frequency', () => {
    for (const t of PROGRAM_TEMPLATES) {
      expect(t.days.length, t.id).toBeGreaterThan(0)
      expect(t.daysPerWeek, t.id).toBeGreaterThanOrEqual(1)
      expect(t.weeksOptions, t.id).toContain(t.defaultWeeks)
    }
  })

  it('slot keys are unique within each program', () => {
    for (const t of PROGRAM_TEMPLATES) {
      const keys = t.days.flatMap((d) => d.slots.map((s) => s.slotKey))
      expect(new Set(keys).size, `${t.id} has duplicate slotKeys`).toBe(keys.length)
    }
  })

  it('every slot has sane sets/reps/rest', () => {
    for (const t of PROGRAM_TEMPLATES) {
      for (const d of t.days) {
        for (const s of d.slots) {
          expect(s.restSeconds, `${t.id}/${s.slotKey}`).toBeGreaterThanOrEqual(30)
          if (s.sets.kind === 'straight') {
            expect(s.sets.sets).toBeGreaterThan(0)
            expect(s.sets.reps).toBeGreaterThan(0)
          } else if (s.sets.kind === 'range') {
            expect(s.sets.sets).toBeGreaterThan(0)
            expect(s.sets.minReps).toBeLessThanOrEqual(s.sets.maxReps)
          }
        }
      }
    }
  })
})

describe('program templates — scheme integrity', () => {
  it('only percentage programs use wave slots, and they declare training-max lifts', () => {
    for (const t of PROGRAM_TEMPLATES) {
      const hasWave = t.days.some((d) => d.slots.some((s) => s.sets.kind === 'wave'))
      if (t.scheme === 'percentage') {
        expect(hasWave, `${t.id} percentage program must have wave slots`).toBe(true)
        expect((t.trainingMaxLifts ?? []).length, t.id).toBeGreaterThan(0)
      } else {
        expect(hasWave, `${t.id} non-percentage program must not use wave slots`).toBe(false)
      }
    }
  })

  it('every wave slot references a known wave', () => {
    const known = new Set(['531_main', '531_bbb', 'nsuns_t1', 'nsuns_t2'])
    for (const t of PROGRAM_TEMPLATES) {
      for (const d of t.days) {
        for (const s of d.slots) {
          if (s.sets.kind === 'wave') expect(known.has(s.sets.wave), `${t.id}/${s.slotKey}`).toBe(true)
        }
      }
    }
  })
})

describe('program templates — catalog resolution guard', () => {
  it('every referenced exercise exists in the seeded catalog', () => {
    const catalog = seededExerciseNames()
    expect(catalog.size).toBeGreaterThan(50) // sanity: seed parsed
    const missing: string[] = []
    for (const t of PROGRAM_TEMPLATES) {
      for (const d of t.days) {
        for (const s of d.slots) {
          if (!catalog.has(s.exercise)) missing.push(`${t.id}/${s.slotKey}: "${s.exercise}"`)
          if (s.tmRef && !catalog.has(s.tmRef)) missing.push(`${t.id}/${s.slotKey}: tmRef "${s.tmRef}"`)
        }
      }
    }
    expect(missing, `Exercises not in seed catalog (would fail resolution):\n${missing.join('\n')}`).toEqual([])
  })
})

describe('program templates — helpers', () => {
  it('getProgramTemplate finds by id and returns null for unknown', () => {
    expect(getProgramTemplate('531_bbb')?.title).toContain('Boring But Big')
    expect(getProgramTemplate('nope')).toBeNull()
  })

  it('summaries expose library metadata without day detail', () => {
    const s = programTemplateSummaries()
    expect(s).toHaveLength(8)
    const nsuns = s.find((x) => x.id === 'nsuns_4day')!
    expect(nsuns.requiresTrainingMax).toBe(true)
    expect(nsuns.daysPerWeek).toBe(4)
  })
})
