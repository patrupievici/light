/**
 * Goal-routing QA bot. Runs 50 diverse goal entries through the REAL routing
 * logic (pure — no DB, no LLM) and reports which path each takes:
 *   - a deterministic blueprint id, OR
 *   - "LLM" (deferred to the LLM-decomposition path).
 *
 * Run: npx tsx prisma/scripts/test-goal-routing.ts
 */
import { detectGoalIntents } from '../../src/lib/goal-guidance'
import { routeWorkoutGoal, pickBlueprint } from '../../src/services/deterministic-workout.service'

type Entry = { text: string; enum?: string | null; expect?: string; tag: string }

const ENTRIES: Entry[] = [
  // ── Common, should be recognized → specific deterministic blueprint ────────
  { tag: 'common', text: 'I want to dunk a basketball', enum: 'strength', expect: 'explosive_power_session' },
  { tag: 'common', text: 'jump higher', expect: 'explosive_power_session' },
  { tag: 'common', text: 'increase my vertical leap', expect: 'explosive_power_session' },
  { tag: 'common', text: 'I want to get stronger', expect: 'strength_main_lifts' },
  { tag: 'common', text: 'powerlifting total PR', expect: 'strength_main_lifts' },
  { tag: 'common', text: 'build muscle', expect: 'hypertrophy_full_body' },
  { tag: 'common', text: 'get jacked and big', expect: 'hypertrophy_full_body' },
  { tag: 'common', text: 'lose fat', expect: 'fat_loss_full_body' },
  { tag: 'common', text: 'get lean and shredded', expect: 'fat_loss_full_body' },
  { tag: 'common', text: 'lose 10kg', expect: 'fat_loss_full_body' },
  { tag: 'common', text: 'sprint faster', expect: 'explosive_power_session' },
  { tag: 'common', text: 'calisthenics planche', expect: 'calisthenics_skill' },
  { tag: 'common', text: 'muscle up and front lever', expect: 'calisthenics_skill' },
  // ── Endurance (no proper blueprint — watch where it lands) ─────────────────
  { tag: 'endurance', text: 'run a marathon', expect: 'LLM' },
  { tag: 'endurance', text: '5k under 25 minutes', expect: 'LLM' },
  { tag: 'endurance', text: 'cycling endurance', expect: 'LLM' },
  // ── Niche sports → SHOULD defer to LLM ─────────────────────────────────────
  { tag: 'niche', text: 'train for table tennis', enum: 'strength', expect: 'LLM' },
  { tag: 'niche', text: 'get better at tennis', expect: 'LLM' },
  { tag: 'niche', text: 'boxing training', expect: 'LLM' },
  { tag: 'niche', text: 'volleyball', expect: 'LLM' },
  { tag: 'niche', text: 'soccer', expect: 'LLM' },
  { tag: 'niche', text: 'rock climbing', expect: 'LLM' },
  { tag: 'niche', text: 'swim faster', expect: 'LLM' }, // "faster" no longer hijacks this
  { tag: 'common', text: 'run faster', expect: 'explosive_power_session' }, // running context still works
  { tag: 'niche', text: 'MMA conditioning', expect: 'LLM' },
  { tag: 'niche', text: 'rowing performance', expect: 'LLM' },
  { tag: 'niche', text: 'golf swing power', expect: 'LLM' },
  { tag: 'niche', text: 'get better at skiing', expect: 'LLM' },
  { tag: 'niche', text: 'rugby strength and speed' },
  { tag: 'niche', text: 'badminton footwork', expect: 'LLM' },
  { tag: 'niche', text: 'CrossFit', expect: 'LLM' },
  { tag: 'niche', text: 'handball', expect: 'LLM' },
  // ── Compound (recognized) ──────────────────────────────────────────────────
  { tag: 'compound', text: 'dunk and run a marathon', expect: 'LLM' },
  { tag: 'compound', text: 'lose fat and build muscle', expect: 'LLM' },
  { tag: 'compound', text: 'get stronger and lose fat', expect: 'LLM' },
  { tag: 'compound', text: 'dunk and get better at tennis' }, // recognized+niche: still jump (known gap)
  // ── Fuzzy / functional → SHOULD defer to LLM ───────────────────────────────
  { tag: 'fuzzy', text: 'carry my kids up the stairs without getting winded', expect: 'LLM' },
  { tag: 'fuzzy', text: 'look good for my wedding in 3 months', expect: 'LLM' },
  { tag: 'fuzzy', text: 'be more athletic', expect: 'LLM' },
  { tag: 'fuzzy', text: 'feel healthier', expect: 'LLM' },
  { tag: 'fuzzy', text: 'train like a viking', expect: 'LLM' },
  { tag: 'fuzzy', text: 'get a six pack', expect: 'LLM' },
  { tag: 'fuzzy', text: 'tone up', expect: 'LLM' },
  { tag: 'fuzzy', text: 'improve my posture', expect: 'LLM' },
  { tag: 'fuzzy', text: 'general fitness', expect: 'LLM' },
  // ── Other languages (keyword layer is English-only) ────────────────────────
  { tag: 'lang', text: 'vreau sa slabesc' }, // RO: lose weight
  { tag: 'lang', text: 'ich will Muskeln aufbauen' }, // DE: build muscle
  // ── Edge cases ─────────────────────────────────────────────────────────────
  { tag: 'edge', text: '', enum: 'strength', expect: 'strength_main_lifts' },
  { tag: 'edge', text: '', enum: null, expect: 'LLM' },
  { tag: 'edge', text: 'asdfqwer zzz', expect: 'LLM' },
  { tag: 'edge', text: 'fitness', expect: 'LLM' },
  { tag: 'edge', text: '💪🏀', expect: 'LLM' },

  // ── Other languages (keyword is English-only → LLM fallback) ───────────────
  { tag: 'lang', text: 'vreau sa dau dunk', expect: 'explosive_power_session' }, // RO but "dunk" is a loanword → correctly jump
  { tag: 'lang', text: 'vreau sa fiu mai puternic', expect: 'LLM' }, // RO: stronger
  { tag: 'lang', text: 'masa musculara', expect: 'LLM' }, // RO: muscle mass
  { tag: 'lang', text: 'quiero saltar mas alto', expect: 'LLM' }, // ES: jump higher
  { tag: 'lang', text: 'je veux courir plus vite', expect: 'LLM' }, // FR: run faster
  { tag: 'lang', text: 'voglio perdere grasso', expect: 'LLM' }, // IT: lose fat

  // ── Typos / misspellings (ideally recognized; currently → LLM) ─────────────
  { tag: 'typo', text: 'dunkk a basketbal', expect: 'LLM' }, // typos miss the keyword → LLM fallback (acceptable)
  { tag: 'typo', text: 'get stronger pls', expect: 'strength_main_lifts' },
  { tag: 'typo', text: 'loose weight', expect: 'LLM' }, // 'loose' != 'lose'
  { tag: 'typo', text: 'build musle', expect: 'LLM' },
  { tag: 'typo', text: 'vertical jmp', expect: 'LLM' },

  // ── Negations / avoidance (keyword has no notion of negation) ──────────────
  { tag: 'negation', text: "I don't want to lose muscle", expect: 'LLM' },
  { tag: 'negation', text: 'stop getting weaker', expect: 'LLM' },
  { tag: 'negation', text: 'avoid getting fat', expect: 'LLM' }, // beware: 'fat' phrasing
  { tag: 'negation', text: 'not interested in bulking', expect: 'LLM' },

  // ── Injuries / constraints (DANGER: keyword may ignore the injury) ─────────
  { tag: 'injury', text: 'get stronger after ACL surgery', expect: 'LLM' },
  { tag: 'injury', text: 'build muscle with a bad shoulder', expect: 'LLM' },
  { tag: 'injury', text: 'lose fat with knee pain', expect: 'LLM' },
  { tag: 'injury', text: 'dunk again but my achilles is fragile', expect: 'LLM' },

  // ── Sports with an embedded keyword (over-claim risk) ──────────────────────
  { tag: 'sport-embed', text: 'basketball conditioning', expect: 'LLM' }, // 'basketball' -> jump over-claim?
  { tag: 'sport-embed', text: 'powerlifting and running', expect: 'LLM' }, // strength + endurance compound
  { tag: 'sport-embed', text: 'marathon swimmer', expect: 'LLM' },
  { tag: 'sport-embed', text: 'football lineman strength', expect: 'LLM' },
  { tag: 'sport-embed', text: 'triathlon', expect: 'LLM' },

  // ── Ambiguous single words ─────────────────────────────────────────────────
  { tag: 'ambiguous', text: 'power', expect: 'LLM' },
  { tag: 'ambiguous', text: 'speed', expect: 'LLM' },
  { tag: 'ambiguous', text: 'explosive', expect: 'LLM' }, // ideally explosive_power
  { tag: 'ambiguous', text: 'agility', expect: 'LLM' },
  { tag: 'ambiguous', text: 'mobility', expect: 'LLM' },
  { tag: 'ambiguous', text: 'flexibility', expect: 'LLM' },

  // ── Quantified / lift-target goals ─────────────────────────────────────────
  { tag: 'quantified', text: 'squat max', expect: 'strength_main_lifts' },
  { tag: 'quantified', text: 'bench 100kg', expect: 'LLM' },
  { tag: 'quantified', text: 'deadlift 2x bodyweight', expect: 'LLM' },
  { tag: 'quantified', text: '100 pushups', expect: 'LLM' },
  { tag: 'quantified', text: '10 pull ups', expect: 'LLM' },

  // ── Body-part / aesthetic (no keyword → LLM, fine) ─────────────────────────
  { tag: 'bodypart', text: 'bigger arms', expect: 'LLM' },
  { tag: 'bodypart', text: 'build my chest', expect: 'LLM' },
  { tag: 'bodypart', text: 'grow my glutes', expect: 'LLM' },
  { tag: 'bodypart', text: 'wider back', expect: 'LLM' },
  { tag: 'bodypart', text: 'visible abs', expect: 'LLM' },

  // ── Lifestyle / vague ──────────────────────────────────────────────────────
  { tag: 'lifestyle', text: 'longevity', expect: 'LLM' },
  { tag: 'lifestyle', text: 'more energy', expect: 'LLM' },
  { tag: 'lifestyle', text: 'sleep better', expect: 'LLM' },
  { tag: 'lifestyle', text: 'reduce stress', expect: 'LLM' },
  { tag: 'lifestyle', text: 'be healthy', expect: 'LLM' },

  // ── Conflicting / weird ────────────────────────────────────────────────────
  { tag: 'conflict', text: 'bulk and cut at the same time', expect: 'LLM' }, // 'cut' only -> fat_loss?
  { tag: 'conflict', text: 'lose fat gain muscle and get stronger', expect: 'LLM' }, // 3 intents
  { tag: 'caps', text: 'I WANT TO DUNK', expect: 'explosive_power_session' },
  { tag: 'weird', text: '123', expect: 'LLM' },
  { tag: 'weird', text: 'workout', expect: 'LLM' },
]

function routeOf(e: Entry): { path: string; intents: string[]; blueprintGoals: string[] } {
  const intents = detectGoalIntents(e.text)
  const r = routeWorkoutGoal({ primaryGoal: e.enum ?? null, onboardingGoalText: e.text })
  if (r.defer) return { path: 'LLM', intents, blueprintGoals: r.blueprintGoals }
  const bp = pickBlueprint(r.blueprintGoals, 4)
  return { path: bp?.id ?? 'NONE', intents, blueprintGoals: r.blueprintGoals }
}

const pad = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + '…' : s.padEnd(n))

let pass = 0
let fail = 0
let checked = 0
const byPath: Record<string, number> = {}
const issues: string[] = []

console.log('\n  GOAL  '.padEnd(46) + 'INTENTS'.padEnd(18) + 'ROUTE'.padEnd(24) + 'VERDICT')
console.log('─'.repeat(100))
for (const e of ENTRIES) {
  const { path, intents } = routeOf(e)
  byPath[path] = (byPath[path] ?? 0) + 1
  let verdict = ''
  if (e.expect) {
    checked++
    if (path === e.expect) {
      pass++
      verdict = '✓'
    } else {
      fail++
      verdict = `✗ expected ${e.expect}`
      issues.push(`[${e.tag}] "${e.text || '(empty)'}"  →  ${path}  (expected ${e.expect})`)
    }
  } else {
    verdict = '·' // observe-only
  }
  const label = (e.text || '(empty)') + (e.enum ? ` [enum:${e.enum}]` : '')
  console.log('  ' + pad(label, 44) + pad(intents.join(',') || '—', 18) + pad(path, 24) + verdict)
}

console.log('─'.repeat(100))
console.log(`\nChecked verdicts: ${pass}/${checked} pass, ${fail} fail.`)
console.log('\nRoute distribution:')
for (const [p, n] of Object.entries(byPath).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${pad(p, 28)} ${n}`)
}
if (issues.length) {
  console.log('\n⚠️  Mismatches / things to look at:')
  for (const i of issues) console.log('  - ' + i)
}
console.log('')
