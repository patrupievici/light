/**
 * One-off test: call generateGoalAdvice with a goal text and print the result
 * so we can judge coach-quality vs. generic AI slop.
 *
 * Run: npx tsx prisma/scripts/test-goal-advice.ts [goalText]
 * Requires: DEEPSEEK_API_KEY in env.
 */

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

try {
  const envPath = resolve(process.cwd(), '.env')
  for (const line of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eq = trimmed.indexOf('=')
    if (eq < 0) continue
    const k = trimmed.slice(0, eq).trim()
    let v = trimmed.slice(eq + 1).trim()
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1)
    }
    if (!process.env[k]) process.env[k] = v
  }
} catch {
  /* .env optional */
}

import { generateGoalAdvice } from '../../src/lib/ai-helpers'

const GOAL = process.argv[2] || 'I want to increase my high jump so I can dunk a basketball. I am 185cm, 80kg, train 4 days a week with full gym access.'
const EXPERIENCE = 'Recreational lifter, 3 years of training, played basketball in high school.'

const BANNED = [
  'be consistent',
  'consistency is key',
  'trust the process',
  'small steps',
  'listen to your body',
  'stay hydrated',
  'rest is important',
  'recovery is important',
  'eat enough protein',
  'enjoy the journey',
  'work hard',
  'no pain no gain',
]

async function main() {
  console.log('═'.repeat(74))
  console.log(`Goal: "${GOAL}"`)
  console.log(`Experience: "${EXPERIENCE}"`)
  console.log('═'.repeat(74))
  console.log('Generating advice...\n')

  const advice = await generateGoalAdvice(GOAL, EXPERIENCE)
  if (!advice) {
    console.log('(empty — AI call failed)')
    return
  }

  console.log(advice)
  console.log('')
  console.log('═'.repeat(74))

  // Quality checks
  const lower = advice.toLowerCase()
  const bullets = advice.split('\n').filter((l) => l.trim().startsWith('•')).length
  const sectionLabels = (advice.match(/\*\*[^*]+\*\*/g) || []).length
  const wordCount = advice.split(/\s+/).filter(Boolean).length
  const bannedFound = BANNED.filter((p) => lower.includes(p))
  const hasNumbers = /\b\d+\s*(g|kg|min|sec|s|m|reps?|sets?|%|times?|x|×|hours?)\b/i.test(advice)

  console.log('Quality checks:')
  console.log(`  Bullets       : ${bullets}`)
  console.log(`  Section labels: ${sectionLabels} (recreational target: 6)`)
  console.log(`  Word count    : ${wordCount} (target: <280 for recreational, <450 elite)`)
  console.log(`  Has numbers   : ${hasNumbers ? 'yes ✓' : 'no ✗'}`)
  console.log(`  Banned phrases: ${bannedFound.length === 0 ? 'none ✓' : `FOUND ${bannedFound.length}: ${bannedFound.join(', ')} ✗`}`)
}

main().catch((err) => {
  console.error('FAILED:', err)
  process.exit(1)
})
