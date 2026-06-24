/**
 * End-to-end OUTPUT QA. For ~12 goals it actually GENERATES a session against
 * the real exercise catalog (read-only) — deterministic for common goals, the
 * LLM-decomposition path for niche/compound/injury goals — and prints the
 * exercises so we can eyeball whether the output is good.
 *
 * Read-only on the DB (loads the catalog; no writes). Makes a few DeepSeek calls
 * for the niche goals. Run: npx tsx prisma/scripts/test-goal-output.ts
 */
import './load-env'
import { prisma } from '../../src/lib/prisma'
import {
  routeWorkoutGoal,
  pickBlueprint,
  resolveGoalComponents,
  composeSession,
  decomposeGoalToSlots,
} from '../../src/services/deterministic-workout.service'

const GOALS: Array<{ text: string; enum?: string | null; level?: string }> = [
  { text: 'I want to dunk a basketball', enum: 'strength' },
  { text: 'get stronger' },
  { text: 'build muscle' },
  { text: 'lose fat' }, // B: should pick a real compound squat, NOT Wall Sit
  { text: 'calisthenics planche' },
  // A: beginner gating — these must avoid Olympic lifts / advanced skills
  { text: 'I want to dunk a basketball', level: 'beginner' },
  { text: 'get stronger', level: 'beginner' },
  { text: 'lose fat', level: 'beginner' },
  { text: 'train for table tennis', enum: 'strength' }, // LLM decompose
  { text: 'boxing training' },
  { text: 'run a marathon' },
  { text: 'get stronger after ACL surgery' },
  { text: 'volleyball' },
]

async function main() {
  const catalog = await prisma.exercise.findMany({ where: { isCustom: false }, take: 500 })
  console.log(`Catalog loaded: ${catalog.length} exercises (full-gym + bodyweight assumed)\n`)

  const mkCtx = (level: string) =>
    ({
      catalog,
      userEquipment: ['full_commercial_gym'],
      bodyweightKg: 80,
      trainingLevel: level,
    }) as never

  for (const g of GOALS) {
    const ctx = mkCtx(g.level ?? 'intermediate')
    const route = routeWorkoutGoal({ primaryGoal: g.enum ?? null, onboardingGoalText: g.text })
    let path = ''
    let session = null
    try {
      if (!route.defer) {
        const bp = pickBlueprint(route.blueprintGoals, 4)
        if (bp) {
          path = `deterministic · ${bp.id}`
          const goals = resolveGoalComponents({ primaryGoal: g.enum ?? null, onboardingGoalText: g.text })
          session = await composeSession('qa-no-user', ctx, bp.slots, goals, {
            blueprintId: bp.id,
            title: bp.title,
            description: bp.description,
          })
        }
      } else {
        const spec = await decomposeGoalToSlots(g.text)
        if (spec) {
          path = `LLM-decompose · [${spec.components.join(', ')}]`
          const goals = resolveGoalComponents({ primaryGoal: g.enum ?? null, onboardingGoalText: g.text, extra: spec.components })
          session = await composeSession('qa-no-user', ctx, spec.slots, goals, {
            blueprintId: 'llm_decomposed',
            title: spec.title,
            description: '',
          })
        } else {
          path = 'LLM-decompose · (no spec returned)'
        }
      }
    } catch (e) {
      path = `ERROR: ${(e as Error).message}`
    }

    const head = `"${g.text}"${g.enum ? ` [enum:${g.enum}]` : ''}${g.level ? ` [${g.level}]` : ''}`
    console.log(`\n━━━━ ${head}`)
    console.log(`     → ${path}`)
    if (session) {
      console.log(`     ${session.title}`)
      for (const ex of session.exercises) {
        console.log(
          `       • ${ex.name.padEnd(26)} ${String(ex.sets)}×${ex.repRange.padEnd(9)} rest ${ex.restSeconds}s  [${ex.movementPattern}]`,
        )
      }
    } else {
      console.log('     (no session)')
    }
  }

  await prisma.$disconnect()
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
