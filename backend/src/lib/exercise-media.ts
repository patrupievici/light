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
async function queryGifUrls(normalizedNames: string[]): Promise<Map<string, string>> {
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

type GifCacheEntry = { url: string | null; expiresAt: number }

const GIF_CACHE_TTL_MS = 6 * 60 * 60 * 1000
const GIF_MISS_CACHE_TTL_MS = 15 * 60 * 1000
const GIF_CACHE_MAX = 2_000
const gifUrlCache = new Map<string, GifCacheEntry>()
const gifUrlInFlight = new Map<string, Promise<string | null>>()

function cacheGifUrl(name: string, url: string | null): string | null {
  if (gifUrlCache.size >= GIF_CACHE_MAX) {
    const now = Date.now()
    for (const [key, entry] of gifUrlCache) {
      if (entry.expiresAt <= now) gifUrlCache.delete(key)
    }
    while (gifUrlCache.size >= GIF_CACHE_MAX) {
      const oldest = gifUrlCache.keys().next().value as string | undefined
      if (!oldest) break
      gifUrlCache.delete(oldest)
    }
  }
  gifUrlCache.set(name, {
    url,
    expiresAt: Date.now() + (url ? GIF_CACHE_TTL_MS : GIF_MISS_CACHE_TTL_MS),
  })
  return url
}

/** Cache both hits and misses; coalesce overlapping lookups across requests. */
async function lookupGifUrls(normalizedNames: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>()
  const now = Date.now()
  const missing: string[] = []

  for (const name of [...new Set(normalizedNames.filter(Boolean))]) {
    const cached = gifUrlCache.get(name)
    if (cached && cached.expiresAt > now) {
      if (cached.url) out.set(name, cached.url)
      continue
    }
    if (cached) gifUrlCache.delete(name)
    missing.push(name)
  }

  const fresh = missing.filter((name) => !gifUrlInFlight.has(name))
  if (fresh.length > 0) {
    const batch = queryGifUrls(fresh)
    for (const name of fresh) {
      const pending = batch
        .then((rows) => cacheGifUrl(name, rows.get(name) ?? null))
        .finally(() => gifUrlInFlight.delete(name))
      gifUrlInFlight.set(name, pending)
    }
  }

  const values = await Promise.all(missing.map(async (name) => ({
    name,
    url: await gifUrlInFlight.get(name),
  })))
  for (const { name, url } of values) {
    if (url) out.set(name, url)
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

// ─── ExerciseDB (RapidAPI) fallback ──────────────────────────────────────────
// When the dedicated media DB has no GIF for an exercise, resolve the name
// against the ExerciseDB catalog (fetched once per process) and serve the GIF
// through the public image proxy (/v1/exercises/db/image/:id), which injects
// EXERCISEDB_KEY server-side. Requires PUBLIC_BASE_URL so the URL the app loads
// is absolute (the client renders media[].url directly, no prefixing).
const EXDB_HOST = 'exercisedb.p.rapidapi.com'

/** Aggressive normalize for cross-source name matching (lowercase, alnum+space). */
function normForMatch(s: string): string {
  return s.trim().toLowerCase().replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim()
}

/** Map a Zvelt equipment value → the ExerciseDB equipment token (best-effort). */
function exdbEquip(equipment: string | null | undefined): string | null {
  const e = (equipment ?? '').toLowerCase()
  if (!e) return null
  if (e.includes('barbell')) return 'barbell'
  if (e.includes('dumbbell')) return 'dumbbell'
  if (e.includes('cable')) return 'cable'
  if (e.includes('kettlebell')) return 'kettlebell'
  if (e.includes('band')) return 'band'
  if (e.includes('smith')) return 'smith machine'
  if (e.includes('machine')) return 'machine' // also matches ExerciseDB "leverage machine"
  if (e.includes('body') || e === 'none' || e === 'bodyweight') return 'body weight'
  return null
}

export type ExdbEntry = { id: string; norm: string; tokens: string[]; eq: string }

/** Build an ExdbEntry from a raw {id,name,equipment} (exported for tests). */
export function exdbEntry(id: string, name: string, equipment = ''): ExdbEntry {
  const norm = normForMatch(name)
  return { id, norm, tokens: norm.split(' '), eq: equipment.toLowerCase() }
}

let exdbCatalogPromise: Promise<ExdbEntry[]> | null = null

/** ExerciseDB catalog (id + normalized name + tokens + equipment). 1 API call/process. */
async function loadExdbCatalog(): Promise<ExdbEntry[]> {
  const key = process.env.EXERCISEDB_KEY?.trim()
  if (!key) return []
  try {
    const res = await fetch(`https://${EXDB_HOST}/exercises?limit=1500&offset=0`, {
      headers: { 'X-RapidAPI-Key': key, 'X-RapidAPI-Host': EXDB_HOST },
    })
    if (!res.ok) {
      console.warn('[exercise-media] ExerciseDB catalog fetch failed:', res.status)
      return []
    }
    const arr = (await res.json()) as Array<{ id?: string; name?: string; equipment?: string }>
    if (!Array.isArray(arr)) return []
    const out: ExdbEntry[] = []
    for (const e of arr) {
      if (e?.id && e?.name) {
        const norm = normForMatch(e.name)
        if (norm) out.push({ id: e.id, norm, tokens: norm.split(' '), eq: (e.equipment ?? '').toLowerCase() })
      }
    }
    console.log(`[exercise-media] ExerciseDB catalog loaded: ${out.length} exercises`)
    return out
  } catch (e) {
    console.warn('[exercise-media] ExerciseDB catalog error:', e instanceof Error ? e.message : e)
    return []
  }
}

function getExdbCatalog(): Promise<ExdbEntry[]> {
  exdbCatalogPromise ??= loadExdbCatalog()
  return exdbCatalogPromise
}

/**
 * Best-effort match of a Zvelt exercise (name + equipment) to an ExerciseDB id.
 * Exact normalized-name match wins; otherwise the best name where every Zvelt
 * token is present, strongly preferring the matching equipment, then the fewest
 * extra tokens, then the shortest name.
 */
export function matchExdb(catalog: ExdbEntry[], name: string, equipment: string | null | undefined): string | null {
  const norm = normForMatch(name)
  if (!norm) return null
  const wantTokens = norm.split(' ')
  const wantEq = exdbEquip(equipment)

  let best: ExdbEntry | null = null
  let bestScore = Number.POSITIVE_INFINITY
  for (const c of catalog) {
    if (c.norm === norm) return c.id
    let subset = true
    for (const t of wantTokens) {
      if (!c.tokens.includes(t)) { subset = false; break }
    }
    if (!subset) continue
    const eqMatch = wantEq != null && (c.eq.includes(wantEq) || c.tokens.includes(wantEq.split(' ')[0]))
    const extra = c.tokens.length - wantTokens.length
    const score = (eqMatch ? 0 : 1000) + extra * 10 + c.norm.length
    if (score < bestScore) {
      bestScore = score
      best = c
    }
  }
  return best?.id ?? null
}

function exdbProxyUrl(exdbId: string): string | null {
  const base = process.env.PUBLIC_BASE_URL?.trim().replace(/\/+$/, '')
  if (!base) return null
  return `${base}/v1/exercises/db/image/${encodeURIComponent(exdbId)}?resolution=360`
}

export async function buildMediaByExerciseId(exercises: Exercise[]): Promise<Map<string, unknown[]>> {
  const byId = new Map<string, unknown[]>()
  const norms = exercises.map((e) => e.name.trim().toLowerCase())
  const urlByNorm = await lookupGifUrls(norms)

  const useExdb = !!process.env.EXERCISEDB_KEY?.trim() && !!process.env.PUBLIC_BASE_URL?.trim()
  const catalog = useExdb ? await getExdbCatalog() : []

  for (const ex of exercises) {
    const url = urlByNorm.get(ex.name.trim().toLowerCase())
    if (url) {
      byId.set(ex.id, [gifMediaPayload(ex.id, url)])
      continue
    }
    if (catalog.length > 0) {
      const exdbId = matchExdb(catalog, ex.name, ex.equipment)
      const proxied = exdbId ? exdbProxyUrl(exdbId) : null
      if (proxied) {
        byId.set(ex.id, [gifMediaPayload(ex.id, proxied)])
        continue
      }
    }
    byId.set(ex.id, [])
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
