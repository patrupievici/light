// One-off: backdate Guradeaur's already-seeded workouts/sets/posts across
// the past week (the seed script's raw SQL had a text=uuid cast bug; the
// API half had already succeeded, so we only fix timestamps here).
//
// Run from backend/:  npx tsx prisma/scripts/backdate-guradeaur.ts

import './load-env'
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()
const EMAIL = 'guradeaur.bot@zvelt.app'

// Same plan as seed-guradeaur.ts WEEK, in creation order.
const PLAN = [
  { dayOffset: 6, startHourUtc: 17, durationMin: 68 },
  { dayOffset: 5, startHourUtc: 16, durationMin: 74 },
  { dayOffset: 3, startHourUtc: 17, durationMin: 71 },
  { dayOffset: 1, startHourUtc: 17, durationMin: 65 },
  { dayOffset: 0, startHourUtc: 9, durationMin: 52 },
]

async function main() {
  const identity = await prisma.authIdentity.findFirst({
    where: { provider: 'email', email: EMAIL },
  })
  if (!identity) throw new Error(`no auth identity for ${EMAIL}`)
  const userId = identity.userId

  const workouts = await prisma.workout.findMany({
    where: { userId },
    orderBy: { startedAt: 'asc' },
  })
  console.log(`found ${workouts.length} workouts for Guradeaur`)
  if (workouts.length !== PLAN.length) {
    console.log(
      `! expected ${PLAN.length} — mapping the first ${Math.min(workouts.length, PLAN.length)} in order`,
    )
  }

  for (let i = 0; i < Math.min(workouts.length, PLAN.length); i++) {
    const w = workouts[i]
    const p = PLAN[i]
    const start = new Date()
    start.setUTCDate(start.getUTCDate() - p.dayOffset)
    start.setUTCHours(p.startHourUtc, 12, 0, 0)
    const end = new Date(start.getTime() + p.durationMin * 60_000)

    await prisma.workout.update({
      where: { id: w.id },
      data: { startedAt: start, endedAt: end },
    })
    await prisma.workoutSet.updateMany({
      where: { workoutExercise: { workoutId: w.id } },
      data: { createdAt: start },
    })
    const postAt = new Date(end.getTime() + 5 * 60_000)
    await prisma.post.updateMany({
      where: { workoutId: w.id },
      data: { createdAt: postAt, updatedAt: postAt },
    })
    console.log(`✔ workout ${i + 1}/${PLAN.length} → D-${p.dayOffset} (${start.toISOString()})`)
  }

  console.log('done — heatmap/streak/feed should now show a lived-in week')
}

main()
  .catch((e) => {
    console.error('BACKDATE FAILED:', e)
    process.exitCode = 1
  })
  .finally(() => prisma.$disconnect())
