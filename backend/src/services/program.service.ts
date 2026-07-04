import { prisma } from '../lib/prisma'
import { resolveExerciseByName } from '../lib/exercise-resolver'
import { computeProgressiveLoads, type ProgressionLevel } from '../lib/progressive-overload'
import {
  getProgramTemplate,
  programTemplateSummaries,
  type ProgramTemplate,
} from '../programming/program-templates'
import { buildMediaByExerciseId } from '../lib/exercise-media'
import {
  buildDayExercises,
  sessionToWeekAndDay,
  weekInCycleFor,
  type ResolvedSlotMeta,
  type SlotLoad,
  type MaterializedDay,
} from '../programming/program-materialize'
import { trainingMaxFromOneRm, incrementTrainingMax } from '../programming/program-progression'
import { exerciseFitsUserEquipment } from '../programming/equipment-compatibility'
import { rankSubstitutes, type SubstitutionExercise } from '../lib/exercise-substitution'
import { createWorkoutFromPlanned } from './planned-workout-converter.service'

/** First GIF URL from a media[] payload, or null. */
function firstGifUrl(media: unknown[] | undefined): string | null {
  if (!media || media.length === 0) return null
  const m = media[0] as { url?: unknown }
  return typeof m?.url === 'string' ? m.url : null
}

/** Display order for the equipment chips (most "primary" first). */
const EQUIPMENT_ORDER = [
  'Barbell', 'Dumbbell', 'EZ Bar', 'Kettlebell', 'Cable',
  'Leverage Machine', 'Smith Machine', 'Band', 'Bodyweight',
]

/**
 * Library summaries enriched with catalog-derived card data: per-exercise GIF
 * thumbnails + the distinct equipment list (Liftosaur-style cards). Resolves the
 * union of template exercises against the catalog + media DB in two batch queries.
 * Degrades gracefully — an exercise missing from the catalog or media just yields
 * no thumbnail/equipment for that slot.
 */
export async function getEnrichedTemplateSummaries() {
  const summaries = programTemplateSummaries()

  const namesOriginal = new Set<string>()
  for (const s of summaries) for (const n of s.exerciseNames) namesOriginal.add(n)

  const catalog = await prisma.exercise.findMany({
    where: { name: { in: [...namesOriginal] } },
    select: { id: true, name: true, equipment: true },
  })
  const byNorm = new Map<string, { id: string; name: string; equipment: string | null }>()
  for (const e of catalog) byNorm.set(e.name.trim().toLowerCase(), e)

  const mediaById = await buildMediaByExerciseId(catalog as never)

  return summaries.map((s) => {
    const thumbnails: string[] = []
    const equip = new Set<string>()
    for (const name of s.exerciseNames) {
      const ex = byNorm.get(name.trim().toLowerCase())
      if (!ex) continue
      if (ex.equipment && ex.equipment.trim()) equip.add(ex.equipment.trim())
      const gif = firstGifUrl(mediaById.get(ex.id))
      if (gif) thumbnails.push(gif)
    }
    const equipment = [...equip].sort((a, b) => {
      const ia = EQUIPMENT_ORDER.indexOf(a)
      const ib = EQUIPMENT_ORDER.indexOf(b)
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b)
    })
    // exerciseNames was only needed to resolve catalog rows — drop from the wire.
    const { exerciseNames: _names, ...rest } = s
    return { ...rest, equipment, thumbnails }
  })
}

/**
 * Program service — the Prisma glue that turns a code template + a user's
 * `UserProgram` state into a tracker-ready session, and advances the program.
 *
 * Heavy lifting (the day build, the percentage waves, deload) lives in the PURE
 * modules (program-materialize / program-progression). This file only resolves
 * DB state and orchestrates; the schedulable math is extracted into
 * `computeProgramAdvance` so it stays unit-testable.
 */

export class ProgramError extends Error {
  constructor(
    public code: 'TEMPLATE_NOT_FOUND' | 'NOT_FOUND' | 'NO_ACTIVE' | 'BAD_INPUT',
    message: string,
  ) {
    super(message)
  }
}

export type ProgramState = { sessionIndex: number; tm: Record<string, number> }

export function readState(stateJson: unknown): ProgramState {
  const s = (stateJson ?? {}) as Record<string, unknown>
  const tmRaw = s.tm
  const tm: Record<string, number> = {}
  if (tmRaw && typeof tmRaw === 'object') {
    for (const [k, v] of Object.entries(tmRaw as Record<string, unknown>)) {
      if (typeof v === 'number' && Number.isFinite(v)) tm[k] = v
    }
  }
  return {
    sessionIndex: typeof s.sessionIndex === 'number' && s.sessionIndex >= 0 ? Math.floor(s.sessionIndex) : 0,
    tm,
  }
}

function isLowerBodyLift(name: string): boolean {
  return /squat|deadlift/i.test(name)
}

/**
 * PURE: compute the program's next state after one completed session.
 * Increments the session cursor, advances training maxes on schedule
 * (5/3/1: at each new 4-week cycle; nSuns: every new week), and decides when the
 * program is complete.
 */
export function computeProgramAdvance(
  template: ProgramTemplate,
  state: ProgramState,
  totalWeeks: number,
): { sessionIndex: number; tm: Record<string, number>; currentWeek: number; status: 'active' | 'completed' } {
  const prevWeek = sessionToWeekAndDay(state.sessionIndex, template.daysPerWeek, template.days.length).week
  const nextSessionIndex = state.sessionIndex + 1
  const nextWeek = sessionToWeekAndDay(nextSessionIndex, template.daysPerWeek, template.days.length).week

  const tm: Record<string, number> = { ...state.tm }
  if (template.scheme === 'percentage' && nextWeek > prevWeek) {
    const newCycle =
      template.deloadCadence >= 2
        ? weekInCycleFor(nextWeek, template.deloadCadence) === 1 // entering a fresh 5/3/1 cycle
        : true // nSuns / no cadence → bump every week
    if (newCycle) {
      for (const lift of template.trainingMaxLifts ?? []) {
        if (tm[lift] != null) tm[lift] = incrementTrainingMax(tm[lift], isLowerBodyLift(lift))
      }
    }
  }

  const status: 'active' | 'completed' = nextWeek > totalWeeks ? 'completed' : 'active'
  return { sessionIndex: nextSessionIndex, tm, currentWeek: Math.min(nextWeek, totalWeeks), status }
}

async function levelFor(userId: string): Promise<ProgressionLevel> {
  const tp = await prisma.userTrainingProfile.findUnique({
    where: { userId },
    select: { trainingLevel: true },
  })
  const lvl = (tp?.trainingLevel ?? '').toLowerCase()
  if (lvl === 'beginner' || lvl === 'advanced') return lvl
  return 'intermediate'
}

export async function startProgram(
  userId: string,
  input: { templateId: string; weeks?: number; equipmentTags?: string[]; oneRepMaxes?: Record<string, number> },
) {
  const tpl = getProgramTemplate(input.templateId)
  if (!tpl) throw new ProgramError('TEMPLATE_NOT_FOUND', `Unknown program template: ${input.templateId}`)

  const totalWeeks = input.weeks && tpl.weeksOptions.includes(input.weeks) ? input.weeks : tpl.defaultWeeks

  // Seed training maxes for percentage programs (from supplied 1RMs, else from
  // the user's best e1RM rank when available).
  const tm: Record<string, number> = {}
  if (tpl.scheme === 'percentage') {
    for (const lift of tpl.trainingMaxLifts ?? []) {
      const orm = input.oneRepMaxes?.[lift]
      if (typeof orm === 'number' && orm > 0) {
        tm[lift] = trainingMaxFromOneRm(orm)
        continue
      }
      const ex = await resolveExerciseByName(lift)
      if (ex) {
        const rank = await prisma.userExerciseRank.findFirst({
          where: { userId, exerciseId: ex.id },
          select: { bestE1rmKg: true },
        })
        if (rank?.bestE1rmKg) tm[lift] = trainingMaxFromOneRm(Number(rank.bestE1rmKg))
      }
    }
  }

  // One active program at a time — archive any current one.
  await prisma.userProgram.updateMany({
    where: { userId, status: 'active' },
    data: { status: 'archived' },
  })

  return prisma.userProgram.create({
    data: {
      userId,
      templateId: tpl.id,
      title: tpl.title,
      totalWeeks,
      daysPerWeek: tpl.daysPerWeek,
      progressionScheme: tpl.scheme,
      deloadCadence: tpl.deloadCadence,
      status: 'active',
      currentWeek: 1,
      stateJson: { sessionIndex: 0, tm },
      equipmentTags: input.equipmentTags ?? [],
    },
  })
}

export async function getActiveProgram(userId: string) {
  return prisma.userProgram.findFirst({
    where: { userId, status: 'active' },
    orderBy: { startedAt: 'desc' },
  })
}

/** The most recently finished program — used to show a completion card after an
 *  active program ends (status flips to 'completed' on the final advance). */
export async function getLatestCompletedProgram(userId: string) {
  return prisma.userProgram.findFirst({
    where: { userId, status: 'completed' },
    orderBy: { completedAt: 'desc' },
  })
}

/** Set/refresh training maxes mid-program from supplied 1RMs (TM = 90% of 1RM).
 *  Lets a user load a percentage program they started without entering 1RMs. */
export async function setProgramTrainingMaxes(program: ProgramRow, oneRepMaxes: Record<string, number>) {
  const state = readState(program.stateJson)
  const tm = { ...state.tm }
  for (const [lift, orm] of Object.entries(oneRepMaxes)) {
    if (typeof orm === 'number' && Number.isFinite(orm) && orm > 0) {
      tm[lift] = trainingMaxFromOneRm(orm)
    }
  }
  return prisma.userProgram.update({
    where: { id: program.id },
    data: { stateJson: { sessionIndex: state.sessionIndex, tm } },
  })
}

type ProgramRow = {
  id: string
  templateId: string
  totalWeeks: number
  progressionScheme: string
  stateJson: unknown
  status?: string
  equipmentTags?: unknown
}

function parseEquipmentTags(raw: unknown): string[] {
  if (!Array.isArray(raw)) return []
  return raw.filter((t): t is string => typeof t === 'string')
}

/** Catalog fields needed for resolution, warmups, and equipment substitution. */
const EX_SELECT = {
  id: true,
  name: true,
  equipment: true,
  movementPattern: true,
  rankModel: true,
  category: true,
  primaryMuscle: true,
  secondaryMuscles: true,
  secondaryPatterns: true,
  fatigueScore: true,
} as const

/** Resolve + materialize the program's CURRENT day into tracker-ready exercises. */
export async function materializeCurrentDay(userId: string, program: ProgramRow): Promise<MaterializedDay> {
  const tpl = getProgramTemplate(program.templateId)
  if (!tpl) throw new ProgramError('TEMPLATE_NOT_FOUND', `Unknown template: ${program.templateId}`)

  const state = readState(program.stateJson)
  const { week, dayInRotation } = sessionToWeekAndDay(state.sessionIndex, tpl.daysPerWeek, tpl.days.length)
  const day = tpl.days[dayInRotation]

  const tags = parseEquipmentTags(program.equipmentTags)

  // Resolve every slot's exercise name → catalog row.
  const resolved = await Promise.all(day.slots.map(async (s) => ({ slot: s, ex: await resolveExerciseByName(s.exercise) })))
  const ids = resolved.map((x) => x.ex?.id).filter((x): x is string => !!x)
  const rows = ids.length
    ? await prisma.exercise.findMany({ where: { id: { in: ids } }, select: EX_SELECT })
    : []
  const rowById = new Map(rows.map((r) => [r.id, r]))

  // Equipment auto-substitution: if the user selected equipment and a resolved
  // lift doesn't fit their kit, swap it for the best-ranked compatible
  // alternative. Percentage (wave) main lifts are left untouched — their load is
  // a % of a barbell training max that wouldn't transfer to a machine swap.
  let catalog: typeof rows | null = null
  const meta: Record<string, ResolvedSlotMeta> = {}
  for (const { slot, ex } of resolved) {
    let exerciseId = ex?.id ?? null
    let name = ex?.name ?? slot.exercise
    let row = ex ? rowById.get(ex.id) ?? null : null

    const swappable = tags.length > 0 && slot.sets.kind !== 'wave'
    if (swappable && row && !exerciseFitsUserEquipment(row.equipment, tags)) {
      if (!catalog) {
        catalog = await prisma.exercise.findMany({ where: { isCustom: false }, select: EX_SELECT })
      }
      const best = rankSubstitutes(row as SubstitutionExercise, catalog as SubstitutionExercise[], {
        isEquipmentAvailable: (eq) => exerciseFitsUserEquipment(eq, tags),
        limit: 5,
      }).find((s) => s.equipmentAvailable)
      if (best) {
        exerciseId = best.exercise.id
        name = best.exercise.name
        row = best.exercise as (typeof rows)[number]
      }
    }

    meta[slot.slotKey] = {
      exerciseId,
      name,
      movementPattern: row?.movementPattern ?? null,
      rankModel: row?.rankModel ?? null,
      category: row?.category ?? null,
    }
  }

  // History-driven loads for non-wave slots (reuse the proven overload engine).
  const loadSlots = day.slots.filter((s) => s.sets.kind !== 'wave')
  const loads: Record<string, SlotLoad> = {}
  if (loadSlots.length) {
    const level = await levelFor(userId)
    const inputs = loadSlots.map((s) => ({
      exerciseId: meta[s.slotKey].exerciseId,
      prescribedReps: s.sets.kind === 'straight' ? s.sets.reps : s.sets.kind === 'range' ? s.sets.maxReps : 8,
    }))
    const decisions = await computeProgressiveLoads(userId, inputs, level, {
      progressionScheme: program.progressionScheme,
    })
    loadSlots.forEach((s, i) => {
      const d = decisions[i]
      loads[s.slotKey] = { suggestedWeightKg: d.suggestedWeightKg, suggestedReps: d.suggestedReps, reason: d.reason }
    })
  }

  return buildDayExercises({ template: tpl, week, dayInRotation, tm: state.tm, meta, loads })
}

function isoDay(d: Date): string {
  return d.toISOString().slice(0, 10)
}
function mondayOf(d: Date): string {
  const x = new Date(d)
  const dow = (x.getUTCDay() + 6) % 7 // 0 = Monday
  x.setUTCDate(x.getUTCDate() - dow)
  return isoDay(x)
}

/**
 * Idempotency guard for startProgramDay: the client re-fires POST /start-day
 * every time the tracker is opened/exited uncompleted, which would otherwise
 * mint a NEW planned calendar row + a NEW orphan draft workout each call. Before
 * creating anything, look for today's still-open planned session (same user +
 * day + title, not yet completed) and REUSE it — plus its live draft workout
 * (the converter names the draft `From plan: <title>`). Returns null when there
 * is nothing to reuse (→ caller creates fresh).
 */
export async function reuseExistingProgramDay(
  userId: string,
  day: string,
  title: string,
): Promise<{ workoutId: string | null; plannedWorkoutId: string; resolved: number } | null> {
  const existingPlanned = await prisma.plannedWorkout.findFirst({
    where: { userId, day, title, status: { in: ['pending', 'in_progress'] } },
    orderBy: { createdAt: 'desc' },
  })
  if (!existingPlanned) return null

  const existingWorkout = await prisma.workout.findFirst({
    where: { userId, status: 'draft', notes: `From plan: ${title}` },
    orderBy: { startedAt: 'desc' },
    select: { id: true, _count: { select: { exercises: true } } },
  })
  if (existingWorkout) {
    return {
      workoutId: existingWorkout.id,
      plannedWorkoutId: existingPlanned.id,
      resolved: existingWorkout._count.exercises,
    }
  }

  // Planned row exists but its draft is gone (e.g. discarded) — convert the SAME
  // planned row rather than minting a duplicate calendar entry.
  const result = await createWorkoutFromPlanned(userId, existingPlanned.id)
  return {
    workoutId: (result.workout as { id?: string } | null)?.id ?? null,
    plannedWorkoutId: existingPlanned.id,
    resolved: result.meta.resolved,
  }
}

/** Materialize today's day → a PlannedWorkout + a live draft Workout for the tracker. */
export async function startProgramDay(userId: string, program: ProgramRow & { title?: string }) {
  const tpl = getProgramTemplate(program.templateId)
  if (!tpl) throw new ProgramError('TEMPLATE_NOT_FOUND', `Unknown template: ${program.templateId}`)
  const built = await materializeCurrentDay(userId, program)

  const now = new Date()
  const day = isoDay(now)
  const title = `${tpl.title} — ${built.title}`

  // Idempotent: re-firing start-day for the same session reuses today's still-open
  // planned + draft instead of creating duplicate 'planned' rows / orphan drafts.
  const reused = await reuseExistingProgramDay(userId, day, title)
  if (reused) {
    return {
      workoutId: reused.workoutId,
      plannedWorkoutId: reused.plannedWorkoutId,
      day: built,
      meta: { plannedWorkoutId: reused.plannedWorkoutId, resolved: reused.resolved, unresolved: [], reused: true },
    }
  }

  const planned = await prisma.plannedWorkout.create({
    data: {
      userId,
      day,
      weekStart: mondayOf(now),
      title,
      kind: 'gym',
      status: 'pending',
      exercisesJson: built.exercises as unknown as object,
      notes: `Week ${built.week} of ${program.totalWeeks}${built.isDeload ? ' · deload week' : ''}`,
    },
  })

  const result = await createWorkoutFromPlanned(userId, planned.id)
  const workoutId = (result.workout as { id?: string } | null)?.id ?? null
  return { workoutId, plannedWorkoutId: planned.id, day: built, meta: result.meta }
}

/** Advance the program one session and persist the new state. */
export async function advanceProgram(userId: string, program: ProgramRow & { totalWeeks: number }) {
  const tpl = getProgramTemplate(program.templateId)
  if (!tpl) throw new ProgramError('TEMPLATE_NOT_FOUND', `Unknown template: ${program.templateId}`)
  // Defense-in-depth: never advance a completed/archived program (the route also
  // guards this) — a double-advance could over-increment training maxes.
  if (program.status && program.status !== 'active') {
    throw new ProgramError('NO_ACTIVE', 'Cannot advance a program that is not active')
  }
  const next = computeProgramAdvance(tpl, readState(program.stateJson), program.totalWeeks)
  return prisma.userProgram.update({
    where: { id: program.id },
    data: {
      stateJson: { sessionIndex: next.sessionIndex, tm: next.tm },
      currentWeek: next.currentWeek,
      status: next.status,
      completedAt: next.status === 'completed' ? new Date() : null,
    },
  })
}
