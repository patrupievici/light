import {
  applyBlockDeload,
  isDeloadWeek,
  type OverloadDecision,
} from '../lib/progressive-overload'
import { generateWarmupSets } from '../lib/warmup'
import { capPresetSets, MAX_PRESET_SETS_PER_EXERCISE } from '../lib/preset-set-limit'
import { percentSetsFromTM, resolveWave, type MaterializedSet } from './program-progression'
import type { ProgramTemplate, ProgramSlot } from './program-templates'

/**
 * PURE day materialization: turn a program template's day into the concrete
 * `exercisesJson` entries the tracker consumes — with per-set auto targets,
 * warm-up ramps, and deload back-off applied.
 *
 * No Prisma, no Date — the service resolves exercise ids/meta, training maxes,
 * and history-driven loads, then hands plain data here. This keeps the
 * week/wave/deload logic unit-testable in isolation.
 */

/** Resolved catalog info for one slot (from exercise-resolver + Exercise row). */
export type ResolvedSlotMeta = {
  exerciseId: string | null
  name: string
  equipment: string | null
  movementPattern: string | null
  rankModel: string | null
  category: string | null
}

/** History-driven load decision for a straight/range slot (from computeProgressiveLoads). */
export type SlotLoad = {
  suggestedWeightKg: number | null
  suggestedReps: number
  reason: string
}

/** One exercises_json entry — superset of what the converter reads. */
export type MaterializedEntry = {
  name: string
  exerciseId: string | null
  sets: number
  reps: number
  restSeconds: number
  /** Uniform working load (used when setsDetail is absent). */
  suggestedWeightKg: number | null
  /** Explicit per-set targets (percentage waves) — overrides uniform sets/reps/weight. */
  setsDetail?: Array<{ weightKg: number | null; reps: number; amrap?: boolean; pctOfTM?: number }>
  /** Warm-up ramp seeded as WARMUP sets before the working sets. */
  warmups?: Array<{ weightKg: number; reps: number }>
  notes?: string
}

export type MaterializedDay = {
  dayKey: string
  title: string
  week: number
  weekInCycle: number
  isDeload: boolean
  exercises: MaterializedEntry[]
}

export type BuildDayOpts = {
  template: ProgramTemplate
  /** 1-based training week within the program. */
  week: number
  /** Index into template.days (0-based) — the session in the rotation. */
  dayInRotation: number
  /** Training maxes keyed by exercise name (percentage programs). */
  tm: Record<string, number>
  /** Resolved catalog meta keyed by slotKey. */
  meta: Record<string, ResolvedSlotMeta>
  /** History-driven loads keyed by slotKey (straight/range slots). */
  loads: Record<string, SlotLoad>
}

/** 1-based week-in-cycle for a 4-week wave (5/3/1). */
export function weekInCycleFor(week: number, cadence: number): number {
  const c = cadence >= 2 ? cadence : 4
  return ((Math.max(1, Math.floor(week)) - 1) % c) + 1
}

/** Compute the day index in the rotation + 1-based week from a 0-based session index. */
export function sessionToWeekAndDay(
  sessionIndex: number,
  daysPerWeek: number,
  rotationLength: number,
): { week: number; dayInRotation: number } {
  const s = Math.max(0, Math.floor(sessionIndex))
  const week = Math.floor(s / Math.max(1, daysPerWeek)) + 1
  const dayInRotation = s % Math.max(1, rotationLength)
  return { week, dayInRotation }
}

function warmupsFor(
  meta: ResolvedSlotMeta | undefined,
  topWeightKg: number | null,
  workingSetCount: number,
): Array<{ weightKg: number; reps: number }> | undefined {
  if (!meta || topWeightKg == null || topWeightKg <= 0) return undefined
  const ramp = generateWarmupSets(topWeightKg, {
    movementPattern: meta.movementPattern,
    rankModel: meta.rankModel,
    category: meta.category,
  })
  if (ramp.length === 0) return undefined
  const candidates = ramp.map((w) => ({ weightKg: w.weightKg, reps: w.reps }))
  const placeholders = Array.from({ length: workingSetCount }, () => null)
  const limited = capPresetSets(placeholders, candidates).warmups
  return limited.length > 0 ? limited : undefined
}

function buildWaveSlot(slot: ProgramSlot, meta: ResolvedSlotMeta | undefined, tm: Record<string, number>, weekInCycle: number): MaterializedEntry {
  if (slot.sets.kind !== 'wave') throw new Error('buildWaveSlot called on non-wave slot')
  const tmKey = slot.tmRef ?? slot.exercise
  const tmKg = tm[tmKey] ?? null
  const steps = resolveWave(slot.sets.wave, weekInCycle)
  const detail = capPresetSets(percentSetsFromTM(tmKg, steps), []).workSets
  const workWeights = detail.map((d) => d.weightKg).filter((w): w is number => w != null)
  const topWeight = workWeights.length ? Math.max(...workWeights) : null
  const firstReps = detail[0]?.reps ?? 5
  return {
    name: meta?.name ?? slot.exercise,
    exerciseId: meta?.exerciseId ?? null,
    sets: detail.length,
    reps: firstReps,
    restSeconds: slot.restSeconds,
    suggestedWeightKg: topWeight,
    setsDetail: detail.map((d: MaterializedSet) => ({ weightKg: d.weightKg, reps: d.reps, amrap: d.amrap, pctOfTM: d.pctOfTM })),
    warmups: slot.warmup ? warmupsFor(meta, topWeight, detail.length) : undefined,
    notes: tmKg != null ? `${slot.sets.wave} · TM ${tmKg}kg` : `${slot.sets.wave} · set your 1RM to load this`,
  }
}

function buildLoadedSlot(slot: ProgramSlot, meta: ResolvedSlotMeta | undefined, load: SlotLoad | undefined, isDeload: boolean): MaterializedEntry {
  const requestedSets = slot.sets.kind === 'straight' ? slot.sets.sets : slot.sets.kind === 'range' ? slot.sets.sets : 3
  const baseSets = Math.min(MAX_PRESET_SETS_PER_EXERCISE, requestedSets)
  // Reps target: straight = fixed; range = climbed reps from the engine, clamped to band.
  let reps: number
  if (slot.sets.kind === 'straight') {
    reps = slot.sets.reps
  } else if (slot.sets.kind === 'range') {
    const sug = load?.suggestedReps ?? slot.sets.maxReps
    reps = Math.min(slot.sets.maxReps, Math.max(slot.sets.minReps, sug))
  } else {
    reps = 8
  }

  let weight = load?.suggestedWeightKg ?? null
  let sets = baseSets
  let note = load?.reason

  // Scheduled block deload (non-percentage programs): −12% load, trim a set.
  if (isDeload) {
    const d = applyBlockDeload(
      { suggestedWeightKg: weight, sets, reason: load?.reason ?? '', source: 'progression' as OverloadDecision['source'] },
      true,
    )
    weight = d.suggestedWeightKg
    sets = d.sets
    note = d.reason
  }

  return {
    name: meta?.name ?? slot.exercise,
    exerciseId: meta?.exerciseId ?? null,
    sets,
    reps,
    restSeconds: slot.restSeconds,
    suggestedWeightKg: weight,
    warmups: slot.warmup ? warmupsFor(meta, weight, sets) : undefined,
    notes: note,
  }
}

/** Build one program day into tracker-ready exercises (pure). */
export function buildDayExercises(opts: BuildDayOpts): MaterializedDay {
  const { template, week, dayInRotation, tm, meta, loads } = opts
  const day = template.days[dayInRotation % template.days.length]
  const weekInCycle = weekInCycleFor(week, template.deloadCadence)

  // Percentage programs carry their deload inside the wave (5/3/1 week 4); only
  // non-percentage programs get the block-deload transform applied here.
  const scheduledDeload =
    template.scheme !== 'percentage' &&
    template.deloadCadence >= 2 &&
    isDeloadWeek(week - 1, template.deloadCadence)

  const exercises = day.slots.map((slot) => {
    const m = meta[slot.slotKey]
    if (slot.sets.kind === 'wave') {
      return buildWaveSlot(slot, m, tm, weekInCycle)
    }
    return buildLoadedSlot(slot, m, loads[slot.slotKey], scheduledDeload)
  })

  // isDeload is an INFORMATIONAL flag for the UI banner. For non-percentage
  // programs it means applyBlockDeload was applied above. For percentage programs
  // the deload lives INSIDE the wave (5/3/1 week 4 = light 40/50/60%), so the flag
  // just labels that week — applyBlockDeload is NOT also applied (guarded above),
  // so there is no double back-off.
  const percentageDeloadWeek =
    template.scheme === 'percentage' && template.deloadCadence >= 2 && weekInCycle === template.deloadCadence
  return {
    dayKey: day.dayKey,
    title: day.title,
    week,
    weekInCycle,
    isDeload: scheduledDeload || percentageDeloadWeek,
    exercises,
  }
}
