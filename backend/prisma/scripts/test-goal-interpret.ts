/**
 * One-off test for the /v1/ai/goal-interpret endpoint: skips the HTTP layer
 * and calls deepSeekChat directly with the same prompt, so we can iterate on
 * prompt quality without spinning up Fastify.
 *
 * Run: npx tsx prisma/scripts/test-goal-interpret.ts ["goal text"]
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

import { deepSeekChat } from '../../src/services/deepseek.service'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../../src/ai/app-context'
import { sanitizePromptInput, parseJsonFromModel } from '../../src/lib/ai-helpers'
import { buildGoalGuidance } from '../../src/lib/goal-guidance'

const GOALS_TO_TEST = process.argv[2]
  ? [process.argv[2]]
  : [
      'I want to dunk a basketball',
      'Increase my sprint speed for soccer matches',
      'Get a one-arm pull-up',
      'Lose 8 kg without losing strength',
      'Better leg work in boxing — last 3 rounds I lose footwork',
      'Build muscle while keeping bjj 3x/week',
    ]

async function interpret(goalText: string) {
  const guidance = buildGoalGuidance(goalText)
  const prompt = `The user just wrote this fitness goal:
"${sanitizePromptInput(goalText)}"

${guidance ? `Detected focus areas — use them to shape your priorities:${guidance}\n` : ''}
Return strict JSON only with this exact shape:
{
  "paraphrase": "1-2 sentences confirming you understood the goal — second-person, warm but not saccharine, NEVER restate the goal verbatim",
  "priorities": ["3-5 short bullets describing what the plan will focus on, each max 10 words, specific to this goal"]
}

Rules:
- Paraphrase must show comprehension, not parroting. E.g. if goal is "I want to dunk", say "You want to develop explosive lower-body power for vertical jumping in basketball", not "You want to dunk".
- Priorities are skills/categories/training principles, NOT specific exercises. E.g. "Single-leg plyometric work" not "Box jumps 4×6".
- English only. No emojis. No markdown.`

  const t0 = Date.now()
  const out = await deepSeekChat(
    [
      {
        role: 'system',
        content: `${ZVELT_APP_CONTEXT_FOR_AI}

You return strict JSON only, no markdown. Be specific and warm without being saccharine.`,
      },
      { role: 'user', content: prompt },
    ],
    { maxTokens: 300, temperature: 0.45 },
  )
  const elapsed = Date.now() - t0
  const json = parseJsonFromModel<{ paraphrase?: string; priorities?: string[] }>(out.text)
  return { elapsed, json, raw: out.text }
}

async function main() {
  for (const goal of GOALS_TO_TEST) {
    console.log('═'.repeat(74))
    console.log(`Goal: "${goal}"`)
    console.log('─'.repeat(74))
    const { elapsed, json } = await interpret(goal)
    if (!json) {
      console.log('FAILED to parse JSON')
      continue
    }
    console.log(`⏱  ${elapsed}ms`)
    console.log('')
    console.log(`📖  ${json.paraphrase ?? '(no paraphrase)'}`)
    console.log('')
    console.log('Priorities:')
    for (const p of json.priorities ?? []) console.log(`   •  ${p}`)
    console.log('')
  }
}

main().catch((err) => {
  console.error('FAILED:', err)
  process.exit(1)
})
