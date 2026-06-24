// Seed "Guradeaur" — a bot account that "used" the app for the past week.
//
// Strategy: everything goes through the REAL production API (signup,
// workouts, sets, complete, posts, nutrition, challenge), so XP / ranks /
// streak / validations run exactly like for a human. Then one Prisma pass
// backdates the timestamps (workouts.started_at drives the heatmap/volume
// stats, posts.created_at drives feed + streak). Nutrition needs no
// backdating — PUT /v1/nutrition/day takes the date directly.
//
// What it CANNOT seed (device-side, by design): wearable health data
// (sleep / HRV / RHR / steps) — the app reads those from Apple Health /
// Health Connect on the phone, not from the account.
//
// Run from backend/:  npx tsx prisma/scripts/seed-guradeaur.ts
// Optional: SEED_API=http://localhost:3000/v1 to hit a local server.

import './load-env'
import { PrismaClient } from '@prisma/client'
import { randomUUID } from 'node:crypto'

const API = process.env.SEED_API ?? 'https://zveltutzu.onrender.com/v1'
const EMAIL = 'guradeaur.bot@zvelt.app'
const PASSWORD = 'Guradeaur123!'
const DISPLAY_NAME = 'Guradeaur'

const prisma = new PrismaClient()

let token = ''

async function api(method: string, path: string, body?: unknown): Promise<any> {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await res.text()
  let json: any = null
  try {
    json = text ? JSON.parse(text) : null
  } catch {
    /* non-JSON */
  }
  if (!res.ok) {
    const msg = json?.message ?? json?.error ?? text.slice(0, 200)
    throw new Error(`${method} ${path} -> ${res.status}: ${msg}`)
  }
  return json
}

// ── Auth ─────────────────────────────────────────────────────────────────────

async function ensureAccount(): Promise<string> {
  try {
    const r = await api('POST', '/auth/signup', {
      email: EMAIL,
      password: PASSWORD,
      displayName: DISPLAY_NAME,
    })
    token = r.accessToken ?? r.tokens?.accessToken ?? r.access_token
    console.log('✔ account created')
    return r.user?.id
  } catch (e: any) {
    if (!/EMAIL|deja|409/i.test(String(e.message))) throw e
    const r = await api('POST', '/auth/login', {
      email: EMAIL,
      password: PASSWORD,
    })
    token = r.accessToken ?? r.tokens?.accessToken ?? r.access_token
    console.log('✔ account already existed — logged in')
    return r.user?.id
  }
}

// ── Exercise catalog ─────────────────────────────────────────────────────────

type Ex = { id: string; name: string }

async function loadExercises(): Promise<Ex[]> {
  const r = await api('GET', '/exercises?limit=500')
  const list: any[] = r.data ?? r.exercises ?? r
  return list.map((e) => ({ id: e.id, name: String(e.name) }))
}

function pick(catalog: Ex[], ...fragments: string[]): Ex | null {
  for (const f of fragments) {
    const hit = catalog.find((e) => e.name.toLowerCase().includes(f.toLowerCase()))
    if (hit) return hit
  }
  return null
}

// ── Workout week plan ────────────────────────────────────────────────────────

type SetSpec = { weightKg: number; reps: number; rpe?: number; tag?: string }
type ExSpec = { names: string[]; sets: SetSpec[] }
type DayPlan = {
  dayOffset: number // 0 = today, 6 = six days ago
  startHourUtc: number
  durationMin: number
  caption: string
  exercises: ExSpec[]
}

function work(weightKg: number, reps: number, rpe: number): SetSpec {
  return { weightKg, reps, rpe }
}
function warmup(weightKg: number, reps: number): SetSpec {
  return { weightKg, reps, tag: 'WARMUP' }
}

const WEEK: DayPlan[] = [
  {
    dayOffset: 6,
    startHourUtc: 17,
    durationMin: 68,
    caption: 'Push day to open the week. Bench felt smooth 💪',
    exercises: [
      { names: ['bench press'], sets: [warmup(40, 10), work(70, 8, 7.5), work(75, 6, 8), work(75, 6, 8.5)] },
      { names: ['overhead press', 'shoulder press'], sets: [warmup(25, 8), work(42.5, 8, 8), work(42.5, 7, 8.5), work(42.5, 6, 9)] },
      { names: ['incline', 'dumbbell press', 'chest press'], sets: [work(26, 10, 8), work(26, 10, 8.5), work(26, 8, 9)] },
      { names: ['triceps', 'pushdown', 'dip'], sets: [work(30, 12, 8), work(30, 12, 8.5), work(30, 10, 9)] },
    ],
  },
  {
    dayOffset: 5,
    startHourUtc: 16,
    durationMin: 74,
    caption: 'Pull day. Deadlift triples moving fast off the floor.',
    exercises: [
      { names: ['deadlift'], sets: [warmup(60, 6), warmup(90, 3), work(130, 3, 8), work(130, 3, 8.5), work(130, 3, 9)] },
      { names: ['barbell row', 'bent over row', 'row'], sets: [work(70, 8, 8), work(70, 8, 8.5), work(70, 7, 9)] },
      { names: ['lat pulldown', 'pull-up', 'pull up', 'pullup'], sets: [work(60, 10, 8), work(60, 9, 8.5), work(60, 8, 9)] },
      { names: ['bicep curl', 'biceps curl', 'curl'], sets: [work(14, 12, 8), work(14, 12, 8.5), work(14, 10, 9)] },
    ],
  },
  {
    dayOffset: 3,
    startHourUtc: 17,
    durationMin: 71,
    caption: 'Leg day. Squats heavy, legs gone 🦵',
    exercises: [
      { names: ['back squat', 'squat'], sets: [warmup(40, 8), warmup(70, 5), work(105, 5, 8), work(105, 5, 8.5), work(105, 5, 9)] },
      { names: ['leg press'], sets: [work(180, 10, 8), work(180, 10, 8.5), work(180, 9, 9)] },
      { names: ['lunge', 'split squat'], sets: [work(20, 10, 8), work(20, 10, 8.5)] },
      { names: ['leg curl', 'hamstring'], sets: [work(45, 12, 8), work(45, 12, 8.5), work(45, 10, 9)] },
    ],
  },
  {
    dayOffset: 1,
    startHourUtc: 17,
    durationMin: 65,
    caption: 'Upper day — bench PR attempt went UP. 80kg ✕ 5 🎉',
    exercises: [
      { names: ['bench press'], sets: [warmup(40, 10), warmup(60, 5), work(80, 5, 9), work(72.5, 6, 8.5), work(72.5, 6, 9)] },
      { names: ['barbell row', 'bent over row', 'row'], sets: [work(72.5, 8, 8), work(72.5, 8, 8.5), work(72.5, 7, 9)] },
      { names: ['overhead press', 'shoulder press'], sets: [work(45, 6, 8.5), work(45, 6, 9), work(42.5, 7, 9)] },
      { names: ['bicep curl', 'biceps curl', 'curl'], sets: [work(15, 12, 8), work(15, 11, 8.5), work(15, 10, 9)] },
    ],
  },
  {
    dayOffset: 0,
    startHourUtc: 9,
    durationMin: 52,
    caption: 'Light full-body to close the week. Recovery first.',
    exercises: [
      { names: ['back squat', 'squat'], sets: [warmup(40, 8), work(85, 6, 7), work(85, 6, 7.5)] },
      { names: ['bench press'], sets: [work(62.5, 8, 7), work(62.5, 8, 7.5)] },
      { names: ['lat pulldown', 'pull-up', 'pull up', 'pullup'], sets: [work(55, 10, 7.5), work(55, 10, 8)] },
      { names: ['plank', 'crunch', 'ab'], sets: [work(0, 30, 7), work(0, 30, 7.5)] },
    ],
  },
]

// ── Nutrition week ───────────────────────────────────────────────────────────

type Food = {
  id: string
  name: string
  brand: string
  caloriesPer100g: number
  proteinPer100g: number
  fatPer100g: number
  carbsPer100g: number
}

const FOODS: Record<string, Food> = {
  oats: { id: 'seed-oats', name: 'Oats (rolled)', brand: '', caloriesPer100g: 379, proteinPer100g: 13.2, fatPer100g: 6.5, carbsPer100g: 67.7 },
  eggs: { id: 'seed-eggs', name: 'Eggs (whole)', brand: '', caloriesPer100g: 143, proteinPer100g: 12.6, fatPer100g: 9.5, carbsPer100g: 0.7 },
  yogurt: { id: 'seed-yogurt', name: 'Greek yogurt 2%', brand: '', caloriesPer100g: 73, proteinPer100g: 9.9, fatPer100g: 1.9, carbsPer100g: 3.9 },
  banana: { id: 'seed-banana', name: 'Banana', brand: '', caloriesPer100g: 89, proteinPer100g: 1.1, fatPer100g: 0.3, carbsPer100g: 22.8 },
  chicken: { id: 'seed-chicken', name: 'Chicken breast (cooked)', brand: '', caloriesPer100g: 165, proteinPer100g: 31, fatPer100g: 3.6, carbsPer100g: 0 },
  rice: { id: 'seed-rice', name: 'White rice (cooked)', brand: '', caloriesPer100g: 130, proteinPer100g: 2.7, fatPer100g: 0.3, carbsPer100g: 28.2 },
  salmon: { id: 'seed-salmon', name: 'Salmon fillet (cooked)', brand: '', caloriesPer100g: 206, proteinPer100g: 22.1, fatPer100g: 12.4, carbsPer100g: 0 },
  potato: { id: 'seed-potato', name: 'Potatoes (boiled)', brand: '', caloriesPer100g: 87, proteinPer100g: 1.9, fatPer100g: 0.1, carbsPer100g: 20.1 },
  pasta: { id: 'seed-pasta', name: 'Pasta (cooked)', brand: '', caloriesPer100g: 158, proteinPer100g: 5.8, fatPer100g: 0.9, carbsPer100g: 30.9 },
  beef: { id: 'seed-beef', name: 'Beef mince 5% (cooked)', brand: '', caloriesPer100g: 174, proteinPer100g: 26.6, fatPer100g: 7.4, carbsPer100g: 0 },
  rice2: { id: 'seed-broccoli', name: 'Broccoli (steamed)', brand: '', caloriesPer100g: 35, proteinPer100g: 2.4, fatPer100g: 0.4, carbsPer100g: 7.2 },
  whey: { id: 'seed-whey', name: 'Whey protein shake', brand: '', caloriesPer100g: 400, proteinPer100g: 80, fatPer100g: 6, carbsPer100g: 8 },
  apple: { id: 'seed-apple', name: 'Apple', brand: '', caloriesPer100g: 52, proteinPer100g: 0.3, fatPer100g: 0.2, carbsPer100g: 13.8 },
  bread: { id: 'seed-bread', name: 'Wholegrain bread', brand: '', caloriesPer100g: 247, proteinPer100g: 13, fatPer100g: 3.5, carbsPer100g: 41 },
}

function entry(food: Food, grams: number, meal: string, dayIso: string, hour: number) {
  return {
    id: randomUUID(),
    food,
    grams,
    meal,
    loggedAt: `${dayIso}T${String(hour).padStart(2, '0')}:${String(10 + Math.floor(Math.random() * 40)).padStart(2, '0')}:00.000Z`,
  }
}

function nutritionDay(dayIso: string, dayOffset: number) {
  const e = (f: Food, g: number, meal: string, h: number) => entry(f, g, meal, dayIso, h)
  // Slight day-to-day variation; trained days eat a bit more.
  const trained = WEEK.some((w) => w.dayOffset === dayOffset)
  const entries = [
    e(FOODS.oats, 80, 'breakfast', 7),
    e(FOODS.eggs, 120, 'breakfast', 7),
    e(FOODS.banana, 118, 'breakfast', 7),
    e(FOODS.chicken, trained ? 220 : 180, 'lunch', 12),
    e(FOODS.rice, trained ? 250 : 200, 'lunch', 12),
    e(FOODS.rice2, 150, 'lunch', 12),
    dayOffset % 2 === 0
      ? e(FOODS.salmon, 180, 'dinner', 19)
      : e(FOODS.beef, 200, 'dinner', 19),
    dayOffset % 2 === 0 ? e(FOODS.potato, 300, 'dinner', 19) : e(FOODS.pasta, 280, 'dinner', 19),
    e(FOODS.yogurt, 170, 'snacks', 16),
    trained ? e(FOODS.whey, 35, 'snacks', 18) : e(FOODS.apple, 180, 'snacks', 16),
  ]
  const water = trained ? 2250 + (dayOffset % 3) * 250 : 1750 + (dayOffset % 3) * 250
  const weight = Math.round((82.6 - (6 - dayOffset) * 0.1) * 10) / 10 // 82.6 → 82.0 over the week
  return { entries, waterMl: water, weightKg: weight }
}

// ── Main ─────────────────────────────────────────────────────────────────────

function isoDay(offset: number): string {
  const d = new Date()
  d.setUTCDate(d.getUTCDate() - offset)
  return d.toISOString().slice(0, 10)
}

async function main() {
  console.log(`API: ${API}`)
  await ensureAccount()

  // Profile: bodyweight is REQUIRED for ranking (BW_REQUIRED otherwise).
  await api('PATCH', '/me/profile', {
    displayName: DISPLAY_NAME,
    username: 'guradeaur',
    bio: 'Bot de teste. Ridic fier virtual de o săptămână. 🤖',
    bodyweightKg: 82,
    heightCm: 178,
  }).catch((e) => console.log(`(profile patch partial: ${e.message})`))
  console.log('✔ profile set (BW 82kg / 178cm)')

  const catalog = await loadExercises()
  console.log(`✔ exercise catalog: ${catalog.length} exercises`)

  const created: { workoutId: string; plan: DayPlan }[] = []

  for (const plan of WEEK) {
    const w = await api('POST', '/workouts', {})
    const workoutId: string = w.workout.id

    for (const exSpec of plan.exercises) {
      const ex = pick(catalog, ...exSpec.names)
      if (!ex) {
        console.log(`  (skip — no catalog match for: ${exSpec.names[0]})`)
        continue
      }
      const we = await api('POST', `/workouts/${workoutId}/exercises`, {
        exerciseId: ex.id,
      })
      const weId: string = we.workoutExercise.id
      for (const s of exSpec.sets) {
        await api('POST', `/workouts/${workoutId}/exercises/${weId}/sets`, {
          weightKg: s.weightKg,
          reps: s.reps,
          ...(s.rpe ? { rpe: s.rpe } : {}),
          tag: s.tag ?? 'WORK',
          isCompleted: true,
          clientSetId: randomUUID(),
        })
      }
    }

    await api('POST', `/workouts/${workoutId}/complete`, {})
    await api('POST', '/posts', {
      workoutId,
      visibility: 'public',
      caption: plan.caption,
    })
    created.push({ workoutId, plan })
    console.log(`✔ workout D-${plan.dayOffset} created + completed + posted`)
  }

  // Nutrition — natively backdatable via the date field.
  for (let off = 6; off >= 0; off--) {
    const dayIso = isoDay(off)
    const d = nutritionDay(dayIso, off)
    await api('PUT', '/nutrition/day', { date: dayIso, ...d })
  }
  console.log('✔ nutrition: 7 days (meals + water + weight trend 82.6→82.0)')

  // Challenge — create a public one and make sure we're in it.
  try {
    const ch = await api('POST', '/challenges', {
      kind: 'benchPress',
      visibility: 'public',
      targetHint: 'Most bench volume in 7 days',
      durationDays: 7,
    })
    const chId = ch.data?.id
    if (chId) {
      await api('POST', `/challenges/${chId}/join`, {}).catch(() => {})
      console.log('✔ challenge created + joined (bench press, 7 days, public)')
    }
  } catch (e: any) {
    console.log(`(challenge skipped: ${e.message})`)
  }

  // ── Backdate via Prisma ────────────────────────────────────────────────────
  console.log('backdating timestamps…')
  for (const { workoutId, plan } of created) {
    const start = new Date()
    start.setUTCDate(start.getUTCDate() - plan.dayOffset)
    start.setUTCHours(plan.startHourUtc, 12, 0, 0)
    const end = new Date(start.getTime() + plan.durationMin * 60_000)

    await prisma.workout.update({
      where: { id: workoutId },
      data: { startedAt: start, endedAt: end },
    })
    // Sets logged across the session. (NB: ids are TEXT columns — do NOT
    // ::uuid-cast in raw SQL; Prisma relation filters sidestep it entirely.)
    await prisma.workoutSet.updateMany({
      where: { workoutExercise: { workoutId } },
      data: { createdAt: start },
    })
    // Post 5 minutes after the workout ended (drives feed order + streak).
    const postAt = new Date(end.getTime() + 5 * 60_000)
    await prisma.post.updateMany({
      where: { workoutId },
      data: { createdAt: postAt, updatedAt: postAt },
    })
  }
  console.log('✔ backdated: workouts, sets, posts spread across the past week')

  console.log('\n──────────────────────────────────────────')
  console.log('GURADEAUR IS ALIVE 🤖')
  console.log(`  email:    ${EMAIL}`)
  console.log(`  password: ${PASSWORD}`)
  console.log('  has: 5 workouts (push/pull/legs/upper/full) over 7 days,')
  console.log('       5 public posts (streak alive), ranks/XP from real e1RM,')
  console.log('       7 days nutrition (meals/water/weight 82.6→82.0),')
  console.log('       1 public bench-press challenge (joined).')
  console.log('  NOT seedable (device-side): sleep/HRV/RHR rings — those read')
  console.log('  from Health Connect on the phone you log in with.')
  console.log('──────────────────────────────────────────')
}

main()
  .catch((e) => {
    console.error('SEED FAILED:', e)
    process.exitCode = 1
  })
  .finally(() => prisma.$disconnect())
