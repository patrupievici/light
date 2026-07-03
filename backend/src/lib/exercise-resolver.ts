import { prisma } from './prisma'

/**
 * Resolve an AI-returned exercise name (e.g. "Barbell Back Squat") to a real
 * row in the `exercises` table. Returns `null` when no candidate clears the
 * similarity threshold — callers should still keep the AI name as plain text
 * so the user sees something.
 *
 * Match order:
 *  1. Exact case-insensitive
 *  2. Normalized form (lowercase, ASCII, stripped punctuation/filler words)
 *  3. Dice coefficient on bigrams; threshold 0.72
 *
 * Catalog is cached in-process for `CACHE_TTL_MS`. Re-seeding the exercises
 * table during dev clears the cache on next request after TTL.
 */

type ExerciseRow = { id: string; name: string }

const CACHE_TTL_MS = 5 * 60 * 1000
const FUZZY_THRESHOLD = 0.72

let cachedCatalog: ExerciseRow[] | null = null
let cachedNormalized: Array<{ id: string; name: string; norm: string; bigrams: Set<string> }> = []
let cachedAt = 0

const FILLER_TOKENS = new Set([
  'the', 'a', 'an', 'with', 'using', 'on', 'in', 'at',
])

function stripDiacritics(input: string): string {
  return input.normalize('NFD').replace(/[̀-ͯ]/g, '')
}

export function normalizeExerciseName(raw: string): string {
  const ascii = stripDiacritics(raw.toLowerCase())
  const cleaned = ascii.replace(/[^a-z0-9\s-]/g, ' ').replace(/-/g, ' ')
  const tokens = cleaned
    .split(/\s+/)
    .map((t) => t.trim())
    .filter((t) => t.length > 0 && !FILLER_TOKENS.has(t))
  return tokens.join(' ')
}

function buildBigrams(s: string): Set<string> {
  const padded = ` ${s} `
  const out = new Set<string>()
  for (let i = 0; i < padded.length - 1; i++) out.add(padded.slice(i, i + 2))
  return out
}

function diceCoefficient(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0
  let common = 0
  for (const g of a) if (b.has(g)) common++
  return (2 * common) / (a.size + b.size)
}

async function loadCatalog(): Promise<typeof cachedNormalized> {
  const now = Date.now()
  if (cachedCatalog && now - cachedAt < CACHE_TTL_MS) return cachedNormalized

  const rows = await prisma.exercise.findMany({
    where: { isCustom: false },
    select: { id: true, name: true },
  })
  cachedCatalog = rows
  cachedNormalized = rows.map((r) => {
    const norm = normalizeExerciseName(r.name)
    return { id: r.id, name: r.name, norm, bigrams: buildBigrams(norm) }
  })
  cachedAt = now
  return cachedNormalized
}

export async function resolveExerciseByName(raw: string): Promise<ExerciseRow | null> {
  if (!raw || raw.trim().length === 0) return null
  const catalog = await loadCatalog()

  const lowered = raw.trim().toLowerCase()
  for (const r of catalog) {
    if (r.name.toLowerCase() === lowered) return { id: r.id, name: r.name }
  }

  const norm = normalizeExerciseName(raw)
  if (norm.length === 0) return null
  for (const r of catalog) {
    if (r.norm === norm) return { id: r.id, name: r.name }
  }

  const targetBigrams = buildBigrams(norm)
  let best: { id: string; name: string; score: number } | null = null
  for (const r of catalog) {
    const score = diceCoefficient(targetBigrams, r.bigrams)
    if (score >= FUZZY_THRESHOLD && (!best || score > best.score)) {
      best = { id: r.id, name: r.name, score }
    }
  }
  if (best) return { id: best.id, name: best.name }
  return null
}
