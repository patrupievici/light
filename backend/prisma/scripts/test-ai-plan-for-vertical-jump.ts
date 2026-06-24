/**
 * One-off test: ask the same DeepSeek planner the production app uses,
 * with a fixed goal text "I want to increase my high jump so I can dunk",
 * and print every exercise it returns so we can judge relevance.
 *
 * Mirrors `weekly-plan.service.ts` prompt shape closely (without DB writes
 * or progression context — pure plan generation). Profile values are set
 * to a plausible default basketball-player-ish profile.
 *
 * Run: npx tsx prisma/scripts/test-ai-plan-for-vertical-jump.ts
 * Requires: DEEPSEEK_API_KEY in env.
 */

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { buildGoalGuidance } from '../../src/lib/goal-guidance'
// Minimal .env loader — backend doesn't depend on dotenv at runtime.
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

const GOAL_TEXT = 'I want to increase my high jump so I can dunk'

const PROFILE = {
  daysPerWeek: 4,
  sessionMinutes: 60,
  trainingLevel: 'intermediate',
  equipmentList: ['full_commercial_gym'],
  bodyweightKg: 80,
  heightCm: 185,
  sex: 'male',
  age: 26,
}

const SYSTEM_PROMPT = `You return strict JSON only, no markdown. No explanations.

For THIS endpoint, ALL human-readable strings in the JSON MUST be English only.`

function buildPrompt(): string {
  const goalBlock = `USER'S GOAL (their own words — top priority):
"${GOAL_TEXT}"
Goal category (hint): explosive_power`

  const goalGuidance = buildGoalGuidance(GOAL_TEXT)

  return `You are a fitness AI planner for the Zvelt mobile app.
Create a 7-day workout and nutrition plan tailored to the user's own goal.
Return strict JSON only with this EXACT structure:
{
  "weekPlan": [
    {
      "dayOfWeek": 1-7,
      "date": "YYYY-MM-DD",
      "workout": {
        "name": "string",
        "focus": "string",
        "durationMinutes": number,
        "exercises": [
          {
            "name": "string",
            "sets": number,
            "reps": number,
            "restSeconds": number,
            "notes": "string (form cue / modification, optional)",
            "whyThisExercise": "TWO short sentences (max 45 words total). Sentence 1: what this exercise primarily builds (muscle/system/skill). Sentence 2: why it fits the user's stated goal explicitly."
          }
        ]
      },
      "nutrition": { "targetCalories": number, "proteinG": number, "carbsG": number, "fatG": number }
    }
  ],
  "dailyTargets": { "calories": number, "proteinG": number, "carbsG": number, "fatG": number },
  "dailyCalorieTarget": number,
  "weeklyCalorieTarget": number,
  "notes": ["string"]
}

${goalBlock}
${goalGuidance ? `${goalGuidance}\n` : ''}
User Profile:
- Days per week: ${PROFILE.daysPerWeek}
- Session duration: ${PROFILE.sessionMinutes} minutes
- Training level: ${PROFILE.trainingLevel}
- Equipment: ${PROFILE.equipmentList.join(', ')}
- Bodyweight: ${PROFILE.bodyweightKg} kg
- Height: ${PROFILE.heightCm} cm
- Sex: ${PROFILE.sex}
- Age: ${PROFILE.age}

Rules:
- Make every exercise pick consistent with the USER'S GOAL above (priority over enum)
- EVERY exercise MUST have a non-empty "whyThisExercise" with TWO sentences: (1) what it builds physiologically, (2) why it fits the user's stated goal. Mandatory.
- Create workouts for the specified days, rest on other days
- Vary muscle groups each day
- Include warmup and cooldown suggestions
- "dailyTargets" must be the BASELINE daily nutrition for the user
- Calculate calories using Mifflin-St Jeor + activity multiplier; adjust for the user's goal
- Protein: 1.6–2.2 g/kg for muscle/strength goals, 1.8–2.4 g/kg for fat loss
- Keep exercises practical and specific; favor compound movements when goal is strength/hypertrophy
- Equipment: **full_commercial_gym** = use barbell/dumbbell/machine/cable exercises as appropriate
- Return EXACTLY 7 days (some can be rest days)
- **Language:** all exercise names, workout titles, focuses, suggestions, notes and every string inside "notes" MUST be **English only**.`
}

async function deepSeekChat(systemPrompt: string, userPrompt: string) {
  const apiKey = process.env.DEEPSEEK_API_KEY
  if (!apiKey) throw new Error('DEEPSEEK_API_KEY not set')
  const base = process.env.DEEPSEEK_API_URL?.replace(/\/$/, '') ?? 'https://api.deepseek.com'
  const model = process.env.DEEPSEEK_MODEL ?? 'deepseek-chat'
  const res = await fetch(`${base}/v1/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: 3000,
      temperature: 0.3,
    }),
  })
  if (!res.ok) throw new Error(`AI upstream ${res.status}: ${await res.text()}`)
  const data = (await res.json()) as any
  return { text: String(data.choices?.[0]?.message?.content ?? '').trim(), model }
}

function parseJsonFromModel(text: string): any {
  const cleaned = text.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```$/i, '').trim()
  try {
    return JSON.parse(cleaned)
  } catch {
    const firstBrace = cleaned.indexOf('{')
    const lastBrace = cleaned.lastIndexOf('}')
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return JSON.parse(cleaned.slice(firstBrace, lastBrace + 1))
    }
    throw new Error('Could not parse JSON from model')
  }
}

async function main() {
  console.log('═'.repeat(70))
  console.log(`Goal text: "${GOAL_TEXT}"`)
  console.log(`Profile: ${PROFILE.bodyweightKg}kg, ${PROFILE.heightCm}cm, ${PROFILE.sex}, ${PROFILE.age}y, ${PROFILE.trainingLevel}`)
  console.log(`Equipment: ${PROFILE.equipmentList.join(', ')}`)
  console.log('═'.repeat(70))
  console.log('Calling DeepSeek...')

  const out = await deepSeekChat(SYSTEM_PROMPT, buildPrompt())
  const plan = parseJsonFromModel(out.text)

  console.log(`Model: ${out.model}`)
  console.log('')

  if (!plan?.weekPlan || !Array.isArray(plan.weekPlan)) {
    console.log('UNEXPECTED RESPONSE STRUCTURE:')
    console.log(JSON.stringify(plan, null, 2))
    return
  }

  const allExercises: string[] = []
  for (const day of plan.weekPlan) {
    const dayLabel = `Day ${day.dayOfWeek}`
    if (!day.workout || !day.workout.exercises || day.workout.exercises.length === 0) {
      console.log(`${dayLabel}: REST`)
      console.log('')
      continue
    }
    console.log(`${dayLabel}: ${day.workout.name}`)
    console.log(`  Focus: ${day.workout.focus}`)
    console.log(`  Duration: ${day.workout.durationMinutes}min`)
    for (const ex of day.workout.exercises) {
      const line = `    • ${ex.name}  ${ex.sets}×${ex.reps}, rest ${ex.restSeconds}s`
      console.log(line)
      if (ex.notes) console.log(`         note: ${ex.notes}`)
      if (ex.whyThisExercise) console.log(`         💡 ${ex.whyThisExercise}`)
      allExercises.push(ex.name)
    }
    console.log('')
  }

  // Quick sanity tally — count exercises by relevance category for vertical jump.
  const categories = {
    plyometric: [/jump/i, /bound/i, /hop/i, /plyo/i, /box/i, /sprint/i, /skater/i, /broad/i],
    posteriorChain: [/deadlift/i, /squat/i, /hip thrust/i, /good morning/i, /romanian/i, /glute/i, /hamstring/i],
    olympic: [/clean/i, /snatch/i, /jerk/i, /power /i],
    calf: [/calf/i, /toe raise/i],
    core: [/plank/i, /sit.?up/i, /crunch/i, /russian/i, /pallof/i, /dead bug/i, /hollow/i, /ab /i],
    upperBody: [/bench/i, /press/i, /row/i, /pull.?up/i, /chin/i, /curl/i, /dip/i, /tricep/i, /lateral raise/i, /shoulder/i],
    other: [] as RegExp[],
  }

  const counts: Record<string, string[]> = {
    plyometric: [],
    posteriorChain: [],
    olympic: [],
    calf: [],
    core: [],
    upperBody: [],
    other: [],
  }

  for (const ex of allExercises) {
    let matched = false
    for (const [cat, patterns] of Object.entries(categories)) {
      if (patterns.some((p) => p.test(ex))) {
        counts[cat].push(ex)
        matched = true
        break
      }
    }
    if (!matched) counts.other.push(ex)
  }

  console.log('═'.repeat(70))
  console.log('Exercise tally by category (relevance to vertical jump):')
  console.log('═'.repeat(70))
  for (const [cat, list] of Object.entries(counts)) {
    if (list.length === 0) continue
    const label = ({
      plyometric: '★ Plyometric (DIRECT carryover)',
      olympic: '★ Olympic lifts (RFD / power)',
      posteriorChain: '★ Posterior chain (squat/hinge — primary force)',
      calf: '○ Calves (small contribution)',
      core: '○ Core (stabilization)',
      upperBody: '? Upper body (low relevance for jump)',
      other: '? Other / uncategorized',
    } as Record<string, string>)[cat]
    console.log(`\n${label}  (${list.length})`)
    for (const ex of list) console.log(`    ${ex}`)
  }

  console.log('\n═'.repeat(70))
  console.log('Notes from AI:')
  if (Array.isArray(plan.notes)) for (const n of plan.notes) console.log(`  • ${n}`)
  console.log(`\nDaily targets: ${plan.dailyTargets?.calories ?? plan.dailyCalorieTarget} kcal, ${plan.dailyTargets?.proteinG}g protein`)
}

main().catch((err) => {
  console.error('FAILED:', err)
  process.exit(1)
})
