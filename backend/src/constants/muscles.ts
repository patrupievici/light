/**
 * Controlled muscle vocabulary for ZVELT.
 *
 * Exercises carry a free-text `primaryMuscle` (legacy, author-entered) plus a
 * structured `secondaryMuscles` JSON array. To compare exercises reliably
 * (substitution overlap, muscle map, recovery model) we normalise both onto a
 * single canonical tag set defined here.
 *
 * `normalizeMuscle` maps free text / common synonyms / pluralforms to a
 * canonical tag, returning `null` when nothing recognisable is found so callers
 * can decide how to treat unknown input (we never silently coerce garbage).
 */

/** Canonical muscle tags. Snake_case, singular-ish, stable identifiers. */
export const MUSCLES = [
  // Upper — push / shoulders / chest
  'chest',
  'front_delts',
  'side_delts',
  'rear_delts',
  'triceps',
  // Upper — pull / back / arms
  'lats',
  'upper_back',
  'lower_back',
  'biceps',
  'forearms',
  'traps',
  // Core
  'abs',
  'obliques',
  // Lower
  'quads',
  'hamstrings',
  'glutes',
  'calves',
  'adductors',
  'abductors',
  'hip_flexors',
  // Neck
  'neck',
] as const

export type Muscle = (typeof MUSCLES)[number]

const MUSCLE_SET: ReadonlySet<string> = new Set(MUSCLES)

/** True when `tag` is already a canonical muscle token. */
export function isMuscle(tag: string): tag is Muscle {
  return MUSCLE_SET.has(tag)
}

/**
 * Synonym / free-text → canonical tag.
 *
 * Keys are normalised (lower-cased, non-alphanumerics collapsed to `_`) before
 * lookup, so "Rear Delts", "rear-delts" and "rear_delts" all hit the same row.
 * Canonical tags map to themselves implicitly via the early `isMuscle` check.
 */
const SYNONYMS: Readonly<Record<string, Muscle>> = {
  // Chest
  pecs: 'chest',
  pec: 'chest',
  pectorals: 'chest',
  pectoral: 'chest',
  pectoralis: 'chest',
  breast: 'chest',
  // Deltoids
  delts: 'side_delts',
  delt: 'side_delts',
  deltoids: 'side_delts',
  deltoid: 'side_delts',
  shoulders: 'side_delts',
  shoulder: 'side_delts',
  front_delt: 'front_delts',
  anterior_delts: 'front_delts',
  anterior_deltoid: 'front_delts',
  front_deltoid: 'front_delts',
  side_delt: 'side_delts',
  lateral_delts: 'side_delts',
  lateral_deltoid: 'side_delts',
  medial_delts: 'side_delts',
  middle_delts: 'side_delts',
  rear_delt: 'rear_delts',
  posterior_delts: 'rear_delts',
  posterior_deltoid: 'rear_delts',
  rear_deltoid: 'rear_delts',
  // Triceps
  tricep: 'triceps',
  triceps_brachii: 'triceps',
  // Back — lats
  lat: 'lats',
  latissimus: 'lats',
  latissimus_dorsi: 'lats',
  // Back — upper / mid
  upper_back: 'upper_back',
  mid_back: 'upper_back',
  middle_back: 'upper_back',
  rhomboids: 'upper_back',
  rhomboid: 'upper_back',
  back: 'upper_back',
  // Back — lower
  lower_back: 'lower_back',
  spinal_erectors: 'lower_back',
  erector_spinae: 'lower_back',
  erectors: 'lower_back',
  // Traps
  trap: 'traps',
  trapezius: 'traps',
  upper_traps: 'traps',
  // Biceps
  bicep: 'biceps',
  biceps_brachii: 'biceps',
  brachialis: 'biceps',
  // Forearms
  forearm: 'forearms',
  wrist_flexors: 'forearms',
  wrist_extensors: 'forearms',
  grip: 'forearms',
  // Core
  abdominals: 'abs',
  abdominal: 'abs',
  ab: 'abs',
  core: 'abs',
  rectus_abdominis: 'abs',
  six_pack: 'abs',
  oblique: 'obliques',
  // Quads
  quad: 'quads',
  quadriceps: 'quads',
  thighs: 'quads',
  thigh: 'quads',
  // Hamstrings
  hamstring: 'hamstrings',
  hams: 'hamstrings',
  ham: 'hamstrings',
  // Glutes
  glute: 'glutes',
  gluteus: 'glutes',
  gluteus_maximus: 'glutes',
  butt: 'glutes',
  // Calves
  calf: 'calves',
  gastrocnemius: 'calves',
  soleus: 'calves',
  // Adductors / abductors
  adductor: 'adductors',
  inner_thigh: 'adductors',
  inner_thighs: 'adductors',
  groin: 'adductors',
  abductor: 'abductors',
  outer_thigh: 'abductors',
  outer_thighs: 'abductors',
  // Hip flexors
  hip_flexor: 'hip_flexors',
  iliopsoas: 'hip_flexors',
  psoas: 'hip_flexors',
}

/** Collapse free text to a comparable key: lower-case, non-alnum → single `_`. */
function muscleKey(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
}

/**
 * Map free text / a synonym to a canonical {@link Muscle}, or `null` when the
 * input is empty or unrecognised. Already-canonical tags pass through unchanged.
 */
export function normalizeMuscle(raw: unknown): Muscle | null {
  if (typeof raw !== 'string') return null
  const key = muscleKey(raw)
  if (!key) return null
  if (isMuscle(key)) return key
  return SYNONYMS[key] ?? null
}

/**
 * Normalise a primary muscle plus a (possibly JSON / messy) secondary-muscle
 * list into a de-duplicated canonical set. Unrecognised entries are dropped.
 */
export function normalizeMuscleSet(primary: unknown, secondary?: unknown): Set<Muscle> {
  const out = new Set<Muscle>()

  const primaryTag = normalizeMuscle(primary)
  if (primaryTag) out.add(primaryTag)

  if (Array.isArray(secondary)) {
    for (const entry of secondary) {
      const tag = normalizeMuscle(entry)
      if (tag) out.add(tag)
    }
  }

  return out
}

/** Human label for a canonical tag (rear_delts → "rear delts"). */
export function muscleLabel(muscle: Muscle | string): string {
  return muscle.replace(/_/g, ' ')
}
