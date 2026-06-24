/**
 * Translatable exercise layer (additive).
 *
 * The catalog stores a single canonical `Exercise.name` / `description`
 * (English). Localized strings live in the `exercise_translations` table keyed
 * by `(exerciseId, locale)`. These pure helpers resolve the right string for an
 * active locale with a deterministic fallback chain so callers never get an
 * empty name:
 *
 *   exact locale → base language (e.g. "ro-RO" → "ro") → canonical Exercise.name
 *
 * Everything here is side-effect free and Prisma-free so it is trivially unit
 * testable; the route layer is responsible for loading translation rows.
 */

/** Minimal shape consumed from an `Exercise` row. */
export type LocalizableExercise = {
  name: string
  description?: string | null
}

/** Minimal shape consumed from an `ExerciseTranslation` row. */
export type ExerciseTranslationRow = {
  locale: string
  name: string
  description?: string | null
}

export type LocalizedExerciseFields = {
  name: string
  description: string | null
  /** Locale actually used for `name` ("" = fell back to canonical). */
  resolvedLocale: string
}

/**
 * Normalize a locale tag to a stable lowercase form. Accepts "ro", "ro-RO",
 * "ro_RO", with surrounding whitespace. Returns "" for nullish/blank input.
 */
export function normalizeLocale(locale: string | null | undefined): string {
  if (!locale) return ''
  return locale.trim().toLowerCase().replace(/_/g, '-')
}

/** Base language subtag, e.g. "ro-ro" → "ro". */
function baseLanguage(locale: string): string {
  const dash = locale.indexOf('-')
  return dash === -1 ? locale : locale.slice(0, dash)
}

/**
 * Build the ordered list of candidate locales to try for a requested locale.
 * "ro-RO" → ["ro-ro", "ro"]; "ro" → ["ro"]; "" → [].
 */
function localeCandidates(normalized: string): string[] {
  if (!normalized) return []
  const base = baseLanguage(normalized)
  return base === normalized ? [normalized] : [normalized, base]
}

/**
 * Resolve the localized name/description for an exercise.
 *
 * `translations` is the set of translation rows for THIS exercise (any locale).
 * Falls back to the canonical `exercise.name` (and its description) when no
 * translation matches the requested locale — so the response is never empty.
 *
 * Behavior-preserving: when `locale` is blank or no translation matches, the
 * returned `name`/`description` equal the canonical values exactly.
 */
export function localizeExercise(
  exercise: LocalizableExercise,
  translations: ReadonlyArray<ExerciseTranslationRow>,
  locale: string | null | undefined,
): LocalizedExerciseFields {
  const canonical: LocalizedExerciseFields = {
    name: exercise.name,
    description: exercise.description ?? null,
    resolvedLocale: '',
  }

  const normalized = normalizeLocale(locale)
  if (!normalized || translations.length === 0) return canonical

  // Index by normalized locale; first row wins on duplicate (rows are unique
  // per (exerciseId, locale) in the DB, so duplicates only arise from callers
  // passing mixed-case tags).
  const byLocale = new Map<string, ExerciseTranslationRow>()
  for (const t of translations) {
    const key = normalizeLocale(t.locale)
    if (key && !byLocale.has(key)) byLocale.set(key, t)
  }

  for (const candidate of localeCandidates(normalized)) {
    const hit = byLocale.get(candidate)
    if (hit && hit.name.trim().length > 0) {
      return {
        name: hit.name,
        // A translation may localize only the name; fall back to canonical
        // description rather than emitting null.
        description: hit.description ?? canonical.description,
        resolvedLocale: candidate,
      }
    }
  }

  return canonical
}

/** Classification fields a CUSTOM exercise can inherit from a parent. */
export type InheritableClassification = {
  movementPattern: string
  rankModel: string
  category: string
}

/**
 * Resolve classification for a new custom exercise, inheriting each field from
 * the parent ONLY when the child did not supply it. Explicit child values
 * always win; with no parent, the provided `defaults` apply.
 *
 * Returns plain fields ready to spread into `prisma.exercise.create`.
 */
export function inheritClassification(
  provided: Partial<InheritableClassification>,
  parent: InheritableClassification | null | undefined,
  defaults: InheritableClassification,
): InheritableClassification {
  const pick = (
    key: keyof InheritableClassification,
  ): string =>
    provided[key] ?? parent?.[key] ?? defaults[key]

  return {
    movementPattern: pick('movementPattern'),
    rankModel: pick('rankModel'),
    category: pick('category'),
  }
}
