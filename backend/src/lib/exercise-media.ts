import type { Exercise } from '@prisma/client'
import pg from 'pg'

let pool: pg.Pool | null | undefined

function getPool(): pg.Pool | null {
  if (pool !== undefined) return pool
  const conn = process.env.EXERCISE_MEDIA_DATABASE_URL?.trim()
  if (!conn) {
    pool = null
    return null
  }
  pool = new pg.Pool({ connectionString: conn, max: 6 })
  return pool
}

/** Safe identifier for schema/table/column names only */
function sqlIdent(raw: string, fallback: string): string | null {
  const s = raw.trim()
  const use = s.length > 0 ? s : fallback
  return /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(use) ? use : null
}

/**
 * Normalized exercise name (trim + lowercase) → GIF URL.
 * Second DB row keys must match Zvelt seed exercise names case-insensitively after trim.
 */
async function lookupGifUrls(normalizedNames: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>()
  const client = getPool()
  if (!client || normalizedNames.length === 0) return out

  const table = sqlIdent(process.env.EXERCISE_MEDIA_TABLE ?? '', 'exercise_gifs')
  const nameCol = sqlIdent(process.env.EXERCISE_MEDIA_NAME_COLUMN ?? '', 'exercise_name')
  const urlCol = sqlIdent(process.env.EXERCISE_MEDIA_URL_COLUMN ?? '', 'gif_url')
  if (!table || !nameCol || !urlCol) return out

  const schemaRaw = process.env.EXERCISE_MEDIA_SCHEMA?.trim()
  let fqtn = `"${table}"`
  if (schemaRaw) {
    const sch = sqlIdent(schemaRaw, schemaRaw)
    if (sch) fqtn = `"${sch}"."${table}"`
  }

  const uniq = [...new Set(normalizedNames.filter(Boolean))]
  if (uniq.length === 0) return out

  try {
    const res = await client.query<{ nk: string; u: string }>(
      `SELECT lower(trim("${nameCol}")) AS nk, "${urlCol}"::text AS u
       FROM ${fqtn}
       WHERE lower(trim("${nameCol}")) = ANY($1::text[])`,
      [uniq],
    )
    for (const row of res.rows) {
      if (row.nk && row.u?.trim()) out.set(row.nk, row.u.trim())
    }
  } catch (e) {
    console.warn('[exercise-media] GIF lookup failed:', e instanceof Error ? e.message : e)
  }
  return out
}

export function gifMediaPayload(exerciseId: string, url: string): Record<string, string> {
  return {
    id: `${exerciseId}-demo-gif`,
    kind: 'gif',
    url,
    thumbnailUrl: url,
  }
}

export async function buildMediaByExerciseId(exercises: Exercise[]): Promise<Map<string, unknown[]>> {
  const byId = new Map<string, unknown[]>()
  const norms = exercises.map((e) => e.name.trim().toLowerCase())
  const urlByNorm = await lookupGifUrls(norms)
  for (const ex of exercises) {
    const url = urlByNorm.get(ex.name.trim().toLowerCase())
    byId.set(ex.id, url ? [gifMediaPayload(ex.id, url)] : [])
  }
  return byId
}

export async function enrichExerciseWithMedia(ex: Exercise): Promise<Record<string, unknown>> {
  const m = await buildMediaByExerciseId([ex])
  return { ...(ex as Record<string, unknown>), media: m.get(ex.id) ?? [] }
}

type WorkoutExerciseRow = { exercise: Exercise } & Record<string, unknown>

export async function enrichWorkoutExerciseRow(row: WorkoutExerciseRow): Promise<WorkoutExerciseRow> {
  const m = await buildMediaByExerciseId([row.exercise])
  return {
    ...row,
    exercise: { ...(row.exercise as object), media: m.get(row.exercise.id) ?? [] } as unknown as Exercise,
  }
}

type WorkoutWithNest = {
  exercises: WorkoutExerciseRow[]
} & Record<string, unknown>

export async function enrichWorkoutWithExerciseMedia<T extends WorkoutWithNest>(workout: T): Promise<T> {
  const list = workout.exercises.map((we) => we.exercise)
  const mediaById = await buildMediaByExerciseId(list)
  return {
    ...workout,
    exercises: workout.exercises.map((we) => ({
      ...we,
      exercise: { ...(we.exercise as object), media: mediaById.get(we.exercise.id) ?? [] } as unknown as Exercise,
    })),
  } as T
}

export async function enrichWorkoutsWithExerciseMedia<T extends WorkoutWithNest>(
  workouts: T[],
): Promise<T[]> {
  const allEx = workouts.flatMap((w) => w.exercises.map((we) => we.exercise))
  const mediaById = await buildMediaByExerciseId(allEx)
  return workouts.map((workout) => ({
    ...workout,
    exercises: workout.exercises.map((we) => ({
      ...we,
      exercise: { ...(we.exercise as object), media: mediaById.get(we.exercise.id) ?? [] } as unknown as Exercise,
    })),
  })) as T[]
}
