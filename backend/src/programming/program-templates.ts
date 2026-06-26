/**
 * Multi-week program templates (the "Programe" library).
 *
 * Templates live in CODE (like blueprints.ts) — they are static, versioned, and
 * reference real Exercise catalog names (resolved via exercise-resolver). A user
 * STARTS a template, creating a `UserProgram` row that holds their mutable state
 * (training maxes / working weights). The program service materializes ONE day at
 * a time into the existing PlannedWorkout → tracker flow.
 *
 * Day model: `days[]` is the DISTINCT session ROTATION; `daysPerWeek` is the
 * training FREQUENCY. The materializer indexes `days[sessionIndex % days.length]`,
 * which cleanly expresses StrongLifts A/B alternation (2 sessions, 3×/week) and
 * PPL (3 sessions, 6×/week) without duplicating day definitions.
 *
 * Progression `scheme`:
 *   - linear / double / reps_sum → working weight lives in UserProgram.stateJson,
 *     advanced each session by the existing progression engine.
 *   - percentage → 5/3/1 & nSuns; loads are % of a stored training max (see
 *     program-progression.ts). Such templates list `trainingMaxLifts` the user
 *     seeds a 1RM for at start.
 *
 * Clean-room: program structures are reconstructed from publicly-documented
 * community programs (Wendler 5/3/1, nSuns LP, PPL/PHUL/Arnold). No code or data
 * is copied from any AGPL project (Liftosaur etc.).
 */

export type ProgramScheme = 'linear' | 'double' | 'reps_sum' | 'percentage'

export type SlotSets =
  /** Same load & reps every set (e.g. 5×5). Working weight from state. */
  | { kind: 'straight'; sets: number; reps: number }
  /** Double progression: climb reps in [min,max] at a fixed load, then add load. */
  | { kind: 'range'; sets: number; minReps: number; maxReps: number }
  /** Percentage-of-training-max wave (5/3/1, nSuns). Resolved per training week. */
  | { kind: 'wave'; wave: '531_main' | '531_bbb' | 'nsuns_t1' | 'nsuns_t2' }

export type ProgramSlot = {
  /** Stable id within the program (keys the per-slot state in UserProgram.stateJson). */
  slotKey: string
  /** Canonical catalog name — resolved to an Exercise via resolveExerciseByName. */
  exercise: string
  role: 'main' | 'accessory'
  sets: SlotSets
  restSeconds: number
  /** Generate a warm-up ramp before the working sets (weighted compounds only). */
  warmup?: boolean
  /** Lower-body lift → +5kg TM increment/cycle (vs +2.5kg upper). */
  isLowerBody?: boolean
  /** Which lift's training max drives a `wave` slot, if not this slot's exercise. */
  tmRef?: string
}

export type ProgramDay = {
  dayKey: string
  title: string
  slots: ProgramSlot[]
}

export type ProgramTemplate = {
  id: string
  title: string
  description: string
  goalTags: string[]
  level: 'beginner' | 'intermediate' | 'advanced'
  scheme: ProgramScheme
  split: string
  weeksOptions: number[]
  defaultWeeks: number
  /** Planned deload cadence (weeks); 0 = none (percentage waves carry their own). */
  deloadCadence: number
  /** Training frequency (sessions / week). May exceed days.length (rotation repeats). */
  daysPerWeek: number
  /** Lifts the user seeds a 1RM/TM for at start (percentage programs only). */
  trainingMaxLifts?: string[]
  days: ProgramDay[]
}

const r = (slotKey: string, exercise: string, sets: number, minReps: number, maxReps: number, restSeconds: number, extra: Partial<ProgramSlot> = {}): ProgramSlot => ({
  slotKey,
  exercise,
  role: extra.role ?? 'accessory',
  sets: { kind: 'range', sets, minReps, maxReps },
  restSeconds,
  ...extra,
})

export const PROGRAM_TEMPLATES: ProgramTemplate[] = [
  // ── 1. StrongLifts 5×5 (linear, beginner) ──────────────────────────────────
  {
    id: 'stronglifts_5x5',
    title: 'StrongLifts 5×5',
    description: 'Two alternating full-body days, three sessions a week. Add 2.5kg every session you hit all reps. The classic beginner barbell program.',
    goalTags: ['strength', 'hypertrophy'],
    level: 'beginner',
    scheme: 'linear',
    split: 'full_body',
    weeksOptions: [8, 10, 12],
    defaultWeeks: 12,
    deloadCadence: 0,
    daysPerWeek: 3,
    days: [
      {
        dayKey: 'A',
        title: 'Workout A',
        slots: [
          { slotKey: 'a_squat', exercise: 'Squat', role: 'main', sets: { kind: 'straight', sets: 5, reps: 5 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'a_bench', exercise: 'Bench Press', role: 'main', sets: { kind: 'straight', sets: 5, reps: 5 }, restSeconds: 180, warmup: true },
          { slotKey: 'a_row', exercise: 'Barbell Row', role: 'main', sets: { kind: 'straight', sets: 5, reps: 5 }, restSeconds: 120, warmup: true },
        ],
      },
      {
        dayKey: 'B',
        title: 'Workout B',
        slots: [
          { slotKey: 'b_squat', exercise: 'Squat', role: 'main', sets: { kind: 'straight', sets: 5, reps: 5 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'b_ohp', exercise: 'Overhead Press', role: 'main', sets: { kind: 'straight', sets: 5, reps: 5 }, restSeconds: 180, warmup: true },
          { slotKey: 'b_deadlift', exercise: 'Deadlift', role: 'main', sets: { kind: 'straight', sets: 1, reps: 5 }, restSeconds: 180, warmup: true, isLowerBody: true },
        ],
      },
    ],
  },

  // ── 2. Full Body 3-day (linear, beginner/intermediate) ─────────────────────
  {
    id: 'full_body_3day',
    title: 'Full Body 3-Day',
    description: 'Three distinct full-body sessions a week, hitting every major pattern with a compound lead and targeted accessories.',
    goalTags: ['hypertrophy', 'strength', 'fat_loss'],
    level: 'beginner',
    scheme: 'linear',
    split: 'full_body',
    weeksOptions: [4, 6, 8, 12],
    defaultWeeks: 8,
    deloadCadence: 4,
    daysPerWeek: 3,
    days: [
      {
        dayKey: 'D1',
        title: 'Day 1 — Squat focus',
        slots: [
          { slotKey: 'd1_squat', exercise: 'Squat', role: 'main', sets: { kind: 'straight', sets: 3, reps: 5 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'd1_bench', exercise: 'Bench Press', role: 'main', sets: { kind: 'straight', sets: 3, reps: 5 }, restSeconds: 150, warmup: true },
          r('d1_row', 'Barbell Row', 3, 8, 12, 120),
          r('d1_curl', 'Dumbbell Curl', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'D2',
        title: 'Day 2 — Hinge focus',
        slots: [
          { slotKey: 'd2_dl', exercise: 'Deadlift', role: 'main', sets: { kind: 'straight', sets: 3, reps: 5 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'd2_ohp', exercise: 'Overhead Press', role: 'main', sets: { kind: 'straight', sets: 3, reps: 5 }, restSeconds: 150, warmup: true },
          r('d2_pulldown', 'Lat Pulldown', 3, 8, 12, 90),
          r('d2_pushdown', 'Tricep Pushdown', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'D3',
        title: 'Day 3 — Press focus',
        slots: [
          { slotKey: 'd3_front', exercise: 'Front Squat', role: 'main', sets: { kind: 'range', sets: 3, minReps: 6, maxReps: 8 }, restSeconds: 150, warmup: true, isLowerBody: true },
          { slotKey: 'd3_incline', exercise: 'Incline Bench Press', role: 'main', sets: { kind: 'range', sets: 3, minReps: 6, maxReps: 10 }, restSeconds: 150, warmup: true },
          r('d3_pull', 'Pull-up', 3, 5, 10, 120, { role: 'main' }),
          r('d3_lat', 'Lateral Raise', 3, 12, 20, 45),
        ],
      },
    ],
  },

  // ── 3. Upper / Lower 4-day (double, intermediate) ──────────────────────────
  {
    id: 'upper_lower_4day',
    title: 'Upper / Lower 4-Day',
    description: 'Four days alternating upper and lower. Double progression on most lifts — climb the rep range, then add load.',
    goalTags: ['hypertrophy', 'strength'],
    level: 'intermediate',
    scheme: 'double',
    split: 'upper_lower',
    weeksOptions: [4, 6, 8, 12],
    defaultWeeks: 8,
    deloadCadence: 4,
    daysPerWeek: 4,
    days: [
      {
        dayKey: 'UA',
        title: 'Upper A',
        slots: [
          { slotKey: 'ua_bench', exercise: 'Bench Press', role: 'main', sets: { kind: 'range', sets: 4, minReps: 5, maxReps: 8 }, restSeconds: 150, warmup: true },
          { slotKey: 'ua_row', exercise: 'Barbell Row', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 120, warmup: true },
          r('ua_ohp', 'Overhead Press', 3, 8, 12, 120),
          r('ua_pulldown', 'Lat Pulldown', 3, 10, 15, 90),
          r('ua_curl', 'Dumbbell Curl', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'LA',
        title: 'Lower A',
        slots: [
          { slotKey: 'la_squat', exercise: 'Squat', role: 'main', sets: { kind: 'range', sets: 4, minReps: 5, maxReps: 8 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'la_rdl', exercise: 'Romanian Deadlift', role: 'main', sets: { kind: 'range', sets: 3, minReps: 8, maxReps: 12 }, restSeconds: 150, warmup: true, isLowerBody: true },
          r('la_legpress', 'Leg Press', 3, 10, 15, 120),
          r('la_calf', 'Standing Calf Raise', 4, 10, 15, 60),
        ],
      },
      {
        dayKey: 'UB',
        title: 'Upper B',
        slots: [
          { slotKey: 'ub_ohp', exercise: 'Overhead Press', role: 'main', sets: { kind: 'range', sets: 4, minReps: 5, maxReps: 8 }, restSeconds: 150, warmup: true },
          { slotKey: 'ub_pull', exercise: 'Pull-up', role: 'main', sets: { kind: 'range', sets: 4, minReps: 5, maxReps: 10 }, restSeconds: 120 },
          r('ub_incline', 'Incline Dumbbell Press', 3, 8, 12, 120),
          r('ub_facepull', 'Face Pull', 3, 12, 20, 60),
          r('ub_pushdown', 'Tricep Pushdown', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'LB',
        title: 'Lower B',
        slots: [
          { slotKey: 'lb_dl', exercise: 'Deadlift', role: 'main', sets: { kind: 'range', sets: 3, minReps: 4, maxReps: 6 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'lb_front', exercise: 'Front Squat', role: 'main', sets: { kind: 'range', sets: 3, minReps: 6, maxReps: 10 }, restSeconds: 150, warmup: true, isLowerBody: true },
          r('lb_legcurl', 'Leg Curl', 3, 10, 15, 90),
          r('lb_calf', 'Seated Calf Raise', 4, 12, 20, 60),
        ],
      },
    ],
  },

  // ── 4. Push / Pull / Legs 6-day (double, intermediate/advanced) ────────────
  {
    id: 'ppl_6day',
    title: 'Push / Pull / Legs (6-Day)',
    description: 'The high-frequency hypertrophy staple: push, pull, legs — twice a week. Double progression across the board.',
    goalTags: ['hypertrophy'],
    level: 'advanced',
    scheme: 'double',
    split: 'push_pull_legs',
    weeksOptions: [4, 6, 8],
    defaultWeeks: 6,
    deloadCadence: 4,
    daysPerWeek: 6,
    days: [
      {
        dayKey: 'PUSH',
        title: 'Push',
        slots: [
          { slotKey: 'p_bench', exercise: 'Bench Press', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 150, warmup: true },
          { slotKey: 'p_ohp', exercise: 'Overhead Press', role: 'main', sets: { kind: 'range', sets: 3, minReps: 8, maxReps: 12 }, restSeconds: 120, warmup: true },
          r('p_incline', 'Incline Dumbbell Press', 3, 8, 12, 90),
          r('p_lat', 'Lateral Raise', 4, 12, 20, 45),
          r('p_pushdown', 'Tricep Pushdown', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'PULL',
        title: 'Pull',
        slots: [
          { slotKey: 'pl_row', exercise: 'Barbell Row', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 150, warmup: true },
          { slotKey: 'pl_pull', exercise: 'Pull-up', role: 'main', sets: { kind: 'range', sets: 4, minReps: 5, maxReps: 12 }, restSeconds: 120 },
          r('pl_cablerow', 'Seated Cable Row', 3, 10, 15, 90),
          r('pl_facepull', 'Face Pull', 3, 12, 20, 60),
          r('pl_curl', 'Dumbbell Curl', 4, 10, 15, 60),
        ],
      },
      {
        dayKey: 'LEGS',
        title: 'Legs',
        slots: [
          { slotKey: 'l_squat', exercise: 'Squat', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'l_rdl', exercise: 'Romanian Deadlift', role: 'main', sets: { kind: 'range', sets: 3, minReps: 8, maxReps: 12 }, restSeconds: 150, warmup: true, isLowerBody: true },
          r('l_legpress', 'Leg Press', 3, 12, 15, 120),
          r('l_legcurl', 'Leg Curl', 3, 10, 15, 90),
          r('l_calf', 'Standing Calf Raise', 4, 12, 20, 60),
        ],
      },
    ],
  },

  // ── 5. PHUL — Power Hypertrophy Upper Lower (double, intermediate) ─────────
  {
    id: 'phul',
    title: 'PHUL (Power Hypertrophy Upper Lower)',
    description: 'Four days: two heavy power days (low reps) and two hypertrophy days (higher reps), split upper/lower. Strength and size together.',
    goalTags: ['hypertrophy', 'strength'],
    level: 'intermediate',
    scheme: 'double',
    split: 'upper_lower',
    weeksOptions: [4, 6, 8, 12],
    defaultWeeks: 8,
    deloadCadence: 4,
    daysPerWeek: 4,
    days: [
      {
        dayKey: 'UP',
        title: 'Upper Power',
        slots: [
          { slotKey: 'up_bench', exercise: 'Bench Press', role: 'main', sets: { kind: 'range', sets: 4, minReps: 3, maxReps: 5 }, restSeconds: 180, warmup: true },
          { slotKey: 'up_row', exercise: 'Barbell Row', role: 'main', sets: { kind: 'range', sets: 4, minReps: 3, maxReps: 5 }, restSeconds: 150, warmup: true },
          r('up_ohp', 'Overhead Press', 3, 5, 8, 120, { warmup: true }),
          r('up_pull', 'Pull-up', 3, 6, 10, 120, { role: 'main' }),
        ],
      },
      {
        dayKey: 'LP',
        title: 'Lower Power',
        slots: [
          { slotKey: 'lp_squat', exercise: 'Squat', role: 'main', sets: { kind: 'range', sets: 4, minReps: 3, maxReps: 5 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'lp_dl', exercise: 'Deadlift', role: 'main', sets: { kind: 'range', sets: 3, minReps: 3, maxReps: 5 }, restSeconds: 210, warmup: true, isLowerBody: true },
          r('lp_legpress', 'Leg Press', 3, 8, 12, 120),
          r('lp_calf', 'Standing Calf Raise', 4, 8, 12, 60),
        ],
      },
      {
        dayKey: 'UH',
        title: 'Upper Hypertrophy',
        slots: [
          { slotKey: 'uh_incline', exercise: 'Incline Dumbbell Press', role: 'main', sets: { kind: 'range', sets: 4, minReps: 10, maxReps: 15 }, restSeconds: 90, warmup: true },
          { slotKey: 'uh_cablerow', exercise: 'Seated Cable Row', role: 'main', sets: { kind: 'range', sets: 4, minReps: 10, maxReps: 15 }, restSeconds: 90 },
          r('uh_lat', 'Lateral Raise', 4, 12, 20, 45),
          r('uh_curl', 'Dumbbell Curl', 3, 12, 15, 60),
          r('uh_pushdown', 'Tricep Pushdown', 3, 12, 15, 60),
        ],
      },
      {
        dayKey: 'LH',
        title: 'Lower Hypertrophy',
        slots: [
          { slotKey: 'lh_front', exercise: 'Front Squat', role: 'main', sets: { kind: 'range', sets: 4, minReps: 10, maxReps: 15 }, restSeconds: 120, warmup: true, isLowerBody: true },
          { slotKey: 'lh_rdl', exercise: 'Romanian Deadlift', role: 'main', sets: { kind: 'range', sets: 3, minReps: 10, maxReps: 15 }, restSeconds: 120, warmup: true, isLowerBody: true },
          r('lh_legcurl', 'Leg Curl', 4, 12, 15, 90),
          r('lh_calf', 'Seated Calf Raise', 4, 15, 20, 60),
        ],
      },
    ],
  },

  // ── 6. Arnold Split 6-day (double, advanced) ───────────────────────────────
  {
    id: 'arnold_split',
    title: 'Arnold Split (6-Day)',
    description: "Arnold's classic bro split: chest & back, shoulders & arms, legs — twice a week. Very high volume for advanced lifters.",
    goalTags: ['hypertrophy'],
    level: 'advanced',
    scheme: 'double',
    split: 'arnold',
    weeksOptions: [4, 6, 8],
    defaultWeeks: 6,
    deloadCadence: 4,
    daysPerWeek: 6,
    days: [
      {
        dayKey: 'CB',
        title: 'Chest & Back',
        slots: [
          { slotKey: 'cb_bench', exercise: 'Bench Press', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 120, warmup: true },
          { slotKey: 'cb_row', exercise: 'Barbell Row', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 120, warmup: true },
          r('cb_incline', 'Incline Dumbbell Press', 3, 8, 12, 90),
          r('cb_pulldown', 'Lat Pulldown', 3, 10, 15, 90),
          r('cb_fly', 'Chest Fly', 3, 12, 15, 60),
        ],
      },
      {
        dayKey: 'SA',
        title: 'Shoulders & Arms',
        slots: [
          { slotKey: 'sa_ohp', exercise: 'Overhead Press', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 120, warmup: true },
          r('sa_lat', 'Lateral Raise', 4, 12, 20, 45),
          r('sa_curl', 'Dumbbell Curl', 4, 8, 12, 60),
          r('sa_skull', 'Dumbbell Skull Crusher', 3, 10, 15, 60),
          r('sa_hammer', 'Hammer Curl', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'LEG',
        title: 'Legs',
        slots: [
          { slotKey: 'lg_squat', exercise: 'Squat', role: 'main', sets: { kind: 'range', sets: 4, minReps: 6, maxReps: 10 }, restSeconds: 180, warmup: true, isLowerBody: true },
          { slotKey: 'lg_rdl', exercise: 'Romanian Deadlift', role: 'main', sets: { kind: 'range', sets: 3, minReps: 8, maxReps: 12 }, restSeconds: 150, warmup: true, isLowerBody: true },
          r('lg_legpress', 'Leg Press', 4, 12, 15, 120),
          r('lg_legcurl', 'Leg Curl', 3, 12, 15, 90),
          r('lg_calf', 'Standing Calf Raise', 4, 15, 20, 60),
        ],
      },
    ],
  },

  // ── 7. nSuns LP 4-day (percentage, advanced) ───────────────────────────────
  {
    id: 'nsuns_4day',
    title: 'nSuns 5/3/1 LP (4-Day)',
    description: 'High-volume linear progression: each session a 9-set T1 main lift and an 8-set T2 secondary, all percentages of training max. AMRAP sets drive weekly TM jumps.',
    goalTags: ['strength', 'hypertrophy'],
    level: 'advanced',
    scheme: 'percentage',
    split: 'upper_lower',
    weeksOptions: [4, 6, 8],
    defaultWeeks: 6,
    deloadCadence: 0,
    daysPerWeek: 4,
    trainingMaxLifts: ['Squat', 'Bench Press', 'Deadlift', 'Overhead Press'],
    days: [
      {
        dayKey: 'N1',
        title: 'Bench day',
        slots: [
          { slotKey: 'n1_t1', exercise: 'Bench Press', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t1' }, restSeconds: 180, warmup: true },
          { slotKey: 'n1_t2', exercise: 'Overhead Press', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t2' }, restSeconds: 150, warmup: true, tmRef: 'Overhead Press' },
          r('n1_pulldown', 'Lat Pulldown', 3, 10, 15, 90),
          r('n1_curl', 'Dumbbell Curl', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'N2',
        title: 'Squat day',
        slots: [
          { slotKey: 'n2_t1', exercise: 'Squat', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t1' }, restSeconds: 210, warmup: true, isLowerBody: true },
          { slotKey: 'n2_t2', exercise: 'Sumo Deadlift', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t2' }, restSeconds: 180, warmup: true, isLowerBody: true, tmRef: 'Deadlift' },
          r('n2_legcurl', 'Leg Curl', 3, 10, 15, 90),
          r('n2_calf', 'Standing Calf Raise', 4, 12, 20, 60),
        ],
      },
      {
        dayKey: 'N3',
        title: 'Overhead Press day',
        slots: [
          { slotKey: 'n3_t1', exercise: 'Overhead Press', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t1' }, restSeconds: 180, warmup: true },
          { slotKey: 'n3_t2', exercise: 'Close-Grip Bench Press', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t2' }, restSeconds: 150, warmup: true, tmRef: 'Bench Press' },
          r('n3_row', 'Cable Row', 3, 10, 15, 90),
          r('n3_lat', 'Lateral Raise', 3, 12, 20, 45),
        ],
      },
      {
        dayKey: 'N4',
        title: 'Deadlift day',
        slots: [
          { slotKey: 'n4_t1', exercise: 'Deadlift', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t1' }, restSeconds: 210, warmup: true, isLowerBody: true },
          { slotKey: 'n4_t2', exercise: 'Front Squat', role: 'main', sets: { kind: 'wave', wave: 'nsuns_t2' }, restSeconds: 180, warmup: true, isLowerBody: true, tmRef: 'Squat' },
          r('n4_pull', 'Pull-up', 3, 6, 10, 120, { role: 'main' }),
          r('n4_pushdown', 'Tricep Pushdown', 3, 10, 15, 60),
        ],
      },
    ],
  },

  // ── 8. 5/3/1 Boring But Big 4-day (percentage, intermediate) ───────────────
  {
    id: '531_bbb',
    title: '5/3/1 Boring But Big (4-Day)',
    description: "Wendler's 5/3/1: one main lift per day on a 3-week wave (5s/3s/1s) plus 5×10 supplemental at 50% TM. Week 4 is a built-in deload. TM climbs each cycle.",
    goalTags: ['strength', 'hypertrophy'],
    level: 'intermediate',
    scheme: 'percentage',
    split: 'upper_lower',
    weeksOptions: [4, 8, 12],
    defaultWeeks: 8,
    deloadCadence: 4,
    daysPerWeek: 4,
    trainingMaxLifts: ['Squat', 'Bench Press', 'Deadlift', 'Overhead Press'],
    days: [
      {
        dayKey: 'B1',
        title: 'Overhead Press day',
        slots: [
          { slotKey: 'b1_main', exercise: 'Overhead Press', role: 'main', sets: { kind: 'wave', wave: '531_main' }, restSeconds: 180, warmup: true },
          { slotKey: 'b1_bbb', exercise: 'Overhead Press', role: 'main', sets: { kind: 'wave', wave: '531_bbb' }, restSeconds: 120 },
          r('b1_pulldown', 'Lat Pulldown', 5, 10, 15, 90),
          r('b1_curl', 'Dumbbell Curl', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'B2',
        title: 'Deadlift day',
        slots: [
          { slotKey: 'b2_main', exercise: 'Deadlift', role: 'main', sets: { kind: 'wave', wave: '531_main' }, restSeconds: 210, warmup: true, isLowerBody: true },
          { slotKey: 'b2_bbb', exercise: 'Deadlift', role: 'main', sets: { kind: 'wave', wave: '531_bbb' }, restSeconds: 150, isLowerBody: true },
          r('b2_legcurl', 'Leg Curl', 5, 10, 15, 90),
          r('b2_abs', 'Hanging Leg Raise', 4, 10, 15, 60),
        ],
      },
      {
        dayKey: 'B3',
        title: 'Bench day',
        slots: [
          { slotKey: 'b3_main', exercise: 'Bench Press', role: 'main', sets: { kind: 'wave', wave: '531_main' }, restSeconds: 180, warmup: true },
          { slotKey: 'b3_bbb', exercise: 'Bench Press', role: 'main', sets: { kind: 'wave', wave: '531_bbb' }, restSeconds: 120 },
          r('b3_row', 'Barbell Row', 5, 10, 15, 90),
          r('b3_pushdown', 'Tricep Pushdown', 3, 10, 15, 60),
        ],
      },
      {
        dayKey: 'B4',
        title: 'Squat day',
        slots: [
          { slotKey: 'b4_main', exercise: 'Squat', role: 'main', sets: { kind: 'wave', wave: '531_main' }, restSeconds: 210, warmup: true, isLowerBody: true },
          { slotKey: 'b4_bbb', exercise: 'Squat', role: 'main', sets: { kind: 'wave', wave: '531_bbb' }, restSeconds: 150, isLowerBody: true },
          r('b4_legpress', 'Leg Press', 5, 10, 15, 120),
          r('b4_calf', 'Standing Calf Raise', 4, 12, 20, 60),
        ],
      },
    ],
  },
]

/** Lookup a template by id. */
export function getProgramTemplate(id: string): ProgramTemplate | null {
  return PROGRAM_TEMPLATES.find((t) => t.id === id) ?? null
}

/** Lightweight metadata for the library list screen (no day detail). */
export function programTemplateSummaries() {
  return PROGRAM_TEMPLATES.map((t) => ({
    id: t.id,
    title: t.title,
    description: t.description,
    goalTags: t.goalTags,
    level: t.level,
    scheme: t.scheme,
    split: t.split,
    weeksOptions: t.weeksOptions,
    defaultWeeks: t.defaultWeeks,
    daysPerWeek: t.daysPerWeek,
    sessionsInRotation: t.days.length,
    requiresTrainingMax: (t.trainingMaxLifts?.length ?? 0) > 0,
  }))
}
