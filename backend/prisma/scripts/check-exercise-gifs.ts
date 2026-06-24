/**
 * Coverage check for ExerciseDB GIF lookups (with smart variant cascade).
 *
 * The Zvelt app fetches GIFs at runtime through `/v1/exercises/db/name/:name`,
 * which forwards to the RapidAPI ExerciseDB `/exercises/name/{name}` endpoint
 * (substring match on the name). When a user opens the GIF dialog for an
 * exercise we just added to the seed, *they* discover whether it has a match —
 * which is a bad time to find out.
 *
 * For each Zvelt exercise this script tries a cascade of name variants. The
 * first variant that returns hits wins. If no variant matches, it falls back
 * to a noun-keyword search and returns up to 5 candidates as suggestions.
 *
 *   ✓ exact       — variant matched, first hit's name == Zvelt name
 *   ~ partial     — variant matched, first hit's name differs (usually fine)
 *   ? suggestions — no variant matched, but key-word search found candidates
 *                   (need manual selection or seed rename)
 *   ✗ none        — nothing at all (need to find/create a GIF manually)
 *
 * Variant order (short-circuits on first hit, so most exercises cost 1 call):
 *   1. Full name as-is                       "Pull-up"
 *   2. Lowercase, no hyphens, single spaces  "pull up"
 *   3. Strip leading equipment word          "Barbell Bench Press" → "bench press"
 *   4. Last-two-words noun search            "Zercher Squat" → "zercher"/"squat"
 *
 * Usage:
 *   npm run db:check-gifs                    # check all
 *   npm run db:check-gifs -- --new-only      # only post-v1 exercises
 *   npm run db:check-gifs -- --json=report.json
 *                                            # write structured report
 *   npm run db:check-gifs -- --slow=300      # ms between API calls (default 150)
 *
 * Requires EXERCISEDB_KEY in backend/.env (same one the runtime uses).
 */

import { PrismaClient } from '@prisma/client'
import { writeFile } from 'node:fs/promises'

const prisma = new PrismaClient()

const EXDB_HOST = 'exercisedb.p.rapidapi.com'
const EXDB_BASE = `https://${EXDB_HOST}`

/** First word of the Zvelt name that we'll strip when retrying.
 *  ExerciseDB names often omit the equipment word or put it elsewhere. */
const EQUIPMENT_PREFIXES = [
  'barbell',
  'dumbbell',
  'cable',
  'machine',
  'kettlebell',
  'smith',
  'band',
  'trap bar',
  'ez bar',
  'bodyweight',
]

type Args = {
  newOnly: boolean
  jsonPath: string | null
  slowMs: number
}

function parseArgs(): Args {
  const args = process.argv.slice(2)
  const jsonArg = args.find((a) => a.startsWith('--json='))
  const slowArg = args.find((a) => a.startsWith('--slow='))
  const slow = slowArg ? parseInt(slowArg.split('=')[1] ?? '150', 10) : 150
  return {
    newOnly: args.includes('--new-only'),
    jsonPath: jsonArg ? jsonArg.split('=')[1] ?? null : null,
    slowMs: Number.isFinite(slow) && slow >= 0 ? slow : 150,
  }
}

function normalize(name: string): string {
  return name.trim().toLowerCase().replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim()
}

/** Generate name variants in priority order. Stops at the first that hits. */
function generateVariants(name: string): string[] {
  const out: string[] = []
  const seen = new Set<string>()
  const add = (s: string) => {
    const t = s.trim()
    if (t && !seen.has(t)) {
      seen.add(t)
      out.push(t)
    }
  }
  // 1. As-is — covers cases where ExerciseDB happens to have the exact string.
  add(name)
  // 2. Normalized — lowercase, hyphens/punctuation → spaces.
  const norm = normalize(name)
  add(norm)
  // 3. Strip a leading equipment word (longest prefix first, so "trap bar" beats "bar").
  const byLength = [...EQUIPMENT_PREFIXES].sort((a, b) => b.length - a.length)
  for (const prefix of byLength) {
    if (norm.startsWith(prefix + ' ')) {
      add(norm.slice(prefix.length + 1).trim())
      break
    }
  }
  return out
}

type ExdbHit = {
  id?: string
  name?: string
  bodyPart?: string
  equipment?: string
  target?: string
  gifUrl?: string
}

type SearchCache = Map<string, ExdbHit[]>

async function exdbSearchRaw(query: string, key: string): Promise<ExdbHit[]> {
  const url = `${EXDB_BASE}/exercises/name/${encodeURIComponent(query)}`
  const res = await fetch(url, {
    headers: { 'X-RapidAPI-Key': key, 'X-RapidAPI-Host': EXDB_HOST },
  })
  if (res.status === 404) return []
  if (!res.ok) {
    throw new Error(`ExerciseDB ${res.status} for "${query}"`)
  }
  const data = await res.json()
  return Array.isArray(data) ? (data as ExdbHit[]) : []
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms))
}

type CheckResult =
  | {
      kind: 'exact'
      zveltName: string
      usedVariant: string
      hit: ExdbHit
      hitsTotal: number
      tier: number
    }
  | {
      kind: 'partial'
      zveltName: string
      usedVariant: string
      hit: ExdbHit
      hitsTotal: number
      tier: number
    }
  | {
      kind: 'suggestions'
      zveltName: string
      suggestions: ExdbHit[]
      triedVariants: string[]
    }
  | { kind: 'none'; zveltName: string; triedVariants: string[] }
  | { kind: 'error'; zveltName: string; error: string }

async function checkOne(
  name: string,
  key: string,
  cache: SearchCache,
  slowMs: number,
): Promise<CheckResult> {
  const variants = generateVariants(name)
  let tier = 0
  for (const variant of variants) {
    tier++
    let hits: ExdbHit[]
    const cached = cache.get(variant.toLowerCase())
    if (cached) {
      hits = cached
    } else {
      hits = await exdbSearchRaw(variant, key)
      cache.set(variant.toLowerCase(), hits)
      if (slowMs > 0) await sleep(slowMs)
    }
    if (hits.length === 0) continue
    const first = hits[0]
    const firstName = first.name?.trim() ?? ''
    const kind: 'exact' | 'partial' =
      normalize(firstName) === normalize(name) ? 'exact' : 'partial'
    return {
      kind,
      zveltName: name,
      usedVariant: variant,
      hit: first,
      hitsTotal: hits.length,
      tier,
    }
  }

  // Suggestions fallback: try noun-keyword search (last 1-2 words) to
  // produce a shortlist instead of "no idea".
  const tokens = normalize(name).split(/\s+/).filter((t) => t.length >= 3)
  const fallbackQueries: string[] = []
  if (tokens.length >= 1) fallbackQueries.push(tokens[tokens.length - 1]!)
  if (tokens.length >= 2) {
    const lastTwo = tokens.slice(-2).join(' ')
    if (!fallbackQueries.includes(lastTwo)) fallbackQueries.unshift(lastTwo)
  }

  const seenIds = new Set<string>()
  const suggestions: ExdbHit[] = []
  for (const q of fallbackQueries) {
    let hits: ExdbHit[]
    const cached = cache.get(q.toLowerCase())
    if (cached) {
      hits = cached
    } else {
      hits = await exdbSearchRaw(q, key)
      cache.set(q.toLowerCase(), hits)
      if (slowMs > 0) await sleep(slowMs)
    }
    for (const h of hits) {
      const dedupeKey = h.id ?? h.name ?? ''
      if (!dedupeKey || seenIds.has(dedupeKey)) continue
      seenIds.add(dedupeKey)
      suggestions.push(h)
      if (suggestions.length >= 5) break
    }
    if (suggestions.length >= 5) break
  }

  if (suggestions.length > 0) {
    return { kind: 'suggestions', zveltName: name, suggestions, triedVariants: variants }
  }
  return { kind: 'none', zveltName: name, triedVariants: variants }
}

/** Names from seed v1 (first 40) — used by --new-only to focus on the cohort
 *  we just added. Names not in this list are treated as "new". */
const SEED_V1_NAMES = new Set<string>([
  'Squat',
  'Bench Press',
  'Deadlift',
  'Overhead Press',
  'Barbell Row',
  'Romanian Deadlift',
  'Front Squat',
  'Dumbbell Press',
  'Dumbbell Row',
  'Dumbbell Curl',
  'Lateral Raise',
  'Dumbbell Lunge',
  'Leg Press',
  'Lat Pulldown',
  'Cable Row',
  'Tricep Pushdown',
  'Leg Curl',
  'Leg Extension',
  'Pull-up',
  'Chin-up',
  'Push-up',
  'Dip',
  'Pistol Squat',
  'L-sit',
  'Plank',
  'Bulgarian Split Squat',
  'Walking Lunge',
  'Hip Thrust',
  'Calf Raise',
  'Box Jump',
  'Burpee',
  'Mountain Climber',
  'Jumping Jack',
  'High Knees',
  'Battle Ropes',
  'Treadmill Run',
  'Stationary Bike',
  'Rowing Machine',
  'Power Clean',
  'Snatch',
])

async function main(): Promise<void> {
  const args = parseArgs()
  const key = process.env.EXERCISEDB_KEY?.trim()
  if (!key) {
    console.error('EXERCISEDB_KEY is not set in env. Add it to backend/.env.')
    process.exit(1)
  }

  console.log('─'.repeat(70))
  console.log(`Mode: ${args.newOnly ? 'NEW-ONLY (post-v1 additions)' : 'ALL EXERCISES'}`)
  console.log(`Throttle: ${args.slowMs}ms between API calls (cached calls are free)`)
  if (args.jsonPath) console.log(`JSON report: ${args.jsonPath}`)
  console.log('─'.repeat(70))

  const allExercises = await prisma.exercise.findMany({
    where: { isCustom: false },
    select: { name: true },
    orderBy: { name: 'asc' },
  })

  const exercises = args.newOnly
    ? allExercises.filter((e) => !SEED_V1_NAMES.has(e.name))
    : allExercises

  console.log(`Zvelt catalog: ${allExercises.length} exercises total`)
  console.log(`To check: ${exercises.length}`)
  if (exercises.length === 0) {
    console.log('Nothing to check. Did you run `npm run db:seed`?')
    await prisma.$disconnect()
    return
  }

  const cache: SearchCache = new Map()
  const results: CheckResult[] = []
  let apiCallsBefore = 0

  let i = 0
  for (const e of exercises) {
    i++
    apiCallsBefore = cache.size
    process.stdout.write(`\r[${i}/${exercises.length}] ${e.name.padEnd(40).slice(0, 40)}`)
    try {
      const r = await checkOne(e.name, key, cache, args.slowMs)
      results.push(r)
    } catch (err) {
      results.push({
        kind: 'error',
        zveltName: e.name,
        error: err instanceof Error ? err.message : String(err),
      })
    }
  }

  process.stdout.write('\r' + ' '.repeat(72) + '\r')

  const exact = results.filter((r): r is Extract<CheckResult, { kind: 'exact' }> => r.kind === 'exact')
  const partial = results.filter(
    (r): r is Extract<CheckResult, { kind: 'partial' }> => r.kind === 'partial',
  )
  const suggestions = results.filter(
    (r): r is Extract<CheckResult, { kind: 'suggestions' }> => r.kind === 'suggestions',
  )
  const none = results.filter((r): r is Extract<CheckResult, { kind: 'none' }> => r.kind === 'none')
  const errors = results.filter(
    (r): r is Extract<CheckResult, { kind: 'error' }> => r.kind === 'error',
  )

  // Tier breakdown — which variant strategy did the work?
  const tierCounts = new Map<number, number>()
  for (const r of [...exact, ...partial]) {
    tierCounts.set(r.tier, (tierCounts.get(r.tier) ?? 0) + 1)
  }

  console.log('')
  console.log(`✓ Exact match    : ${exact.length}`)
  console.log(`~ Partial match  : ${partial.length}  (got hits, name differs — usually fine)`)
  console.log(`? Suggestions    : ${suggestions.length}  (no variant matched; review shortlist)`)
  console.log(`✗ No results     : ${none.length}  (no GIF available — rename or create manually)`)
  if (errors.length > 0) console.log(`! API errors     : ${errors.length}`)
  console.log(`  API calls (deduped via cache): ${cache.size}`)
  console.log('')
  console.log('Tier breakdown (which variant worked):')
  console.log(`  Tier 1 (as-is)            : ${tierCounts.get(1) ?? 0}`)
  console.log(`  Tier 2 (normalized)       : ${tierCounts.get(2) ?? 0}`)
  console.log(`  Tier 3 (stripped prefix)  : ${tierCounts.get(3) ?? 0}`)

  if (partial.length > 0) {
    console.log('\nPartial matches (first hit shown — usually still the right GIF):')
    for (const r of partial) {
      console.log(
        `  ${r.zveltName.padEnd(36)} → "${r.hit.name ?? '?'}"  (variant: "${r.usedVariant}", ${r.hitsTotal} hits)`,
      )
    }
  }

  if (suggestions.length > 0) {
    console.log('\nSuggestions (no variant matched — pick one or rename in seed):')
    for (const r of suggestions) {
      console.log(`  ${r.zveltName}`)
      for (const s of r.suggestions.slice(0, 3)) {
        console.log(`      → "${s.name ?? '?'}"  [${s.bodyPart ?? '?'} / ${s.equipment ?? '?'}]`)
      }
    }
  }

  if (none.length > 0) {
    console.log('\nNo results at all (need manual GIF or seed rename):')
    for (const r of none) {
      console.log(`  ${r.zveltName}  (tried: ${r.triedVariants.join(', ')})`)
    }
  }

  if (errors.length > 0) {
    console.log('\nAPI errors:')
    for (const r of errors) {
      console.log(`  ${r.zveltName}: ${r.error}`)
    }
  }

  const matched = exact.length + partial.length
  const coverage = results.length > 0 ? Math.round((matched / results.length) * 1000) / 10 : 0
  const coverageWithSuggestions =
    results.length > 0
      ? Math.round(((matched + suggestions.length) / results.length) * 1000) / 10
      : 0

  if (args.jsonPath) {
    const report = {
      checkedAt: new Date().toISOString(),
      mode: args.newOnly ? 'new-only' : 'all',
      totals: {
        checked: results.length,
        exact: exact.length,
        partial: partial.length,
        suggestions: suggestions.length,
        none: none.length,
        errors: errors.length,
        apiCalls: cache.size,
      },
      coverage,
      coverageWithSuggestions,
      tierBreakdown: {
        tier1_as_is: tierCounts.get(1) ?? 0,
        tier2_normalized: tierCounts.get(2) ?? 0,
        tier3_stripped_prefix: tierCounts.get(3) ?? 0,
      },
      results,
    }
    await writeFile(args.jsonPath, JSON.stringify(report, null, 2), 'utf8')
    console.log(`\nReport written: ${args.jsonPath}`)
  }

  console.log(`\nCoverage (auto-matched): ${coverage}% (${matched}/${results.length})`)
  console.log(
    `Coverage incl. suggestions: ${coverageWithSuggestions}% (${matched + suggestions.length}/${results.length})`,
  )

  await prisma.$disconnect()
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
