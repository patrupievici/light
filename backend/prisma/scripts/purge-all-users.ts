/**
 * Șterge TOȚI utilizatorii și rândurile care depind de ei.
 * NU atinge: exercises din catalog (seed), seasons, achievements (catalog), shop_items.
 * Șterge exercițiile custom (`is_custom`). Evenimente analytics cu `user_id` null rămân.
 *
 * Rulare (obligatoriu confirmare):
 *   set PURGE_USERS_CONFIRM=1 && npm run db:purge-users
 * PowerShell:
 *   $env:PURGE_USERS_CONFIRM=1; npm run db:purge-users
 */
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()

function isMissingTableError(e: unknown): boolean {
  return (
    typeof e === 'object' &&
    e !== null &&
    'code' in e &&
    (e as { code: string }).code === 'P2021'
  )
}

/** DB-uri fără migrări complete — ignoră doar lipsa tabelului (P2021). */
async function deleteManyIfTable(label: string, fn: () => Promise<unknown>): Promise<void> {
  try {
    await fn()
  } catch (e: unknown) {
    if (isMissingTableError(e)) {
      console.warn(`[purge] omit ${label} (tabel inexistent — rulează migrările dacă ai nevoie de aceste date).`)
      return
    }
    throw e
  }
}

async function main() {
  if (process.env.PURGE_USERS_CONFIRM !== '1') {
    console.error(
      'Refuz: setează PURGE_USERS_CONFIRM=1 în mediu ca să confirmi ștergerea tuturor userilor.',
    )
    process.exit(1)
  }

  const n = await prisma.user.count()
  console.log(`Users in DB: ${n}`)
  if (n === 0) {
    console.log('Nothing to delete.')
    return
  }

  // În afara tranzacției: dacă tabelul lipsește, Postgres nu poate continua în aceeași tranzacție după eroare.
  await deleteManyIfTable('challenges', () => prisma.challenge.deleteMany({}))
  await deleteManyIfTable('notifications', () => prisma.notification.deleteMany({}))
  await deleteManyIfTable('direct_messages', () => prisma.directMessage.deleteMany({}))
  await deleteManyIfTable('direct_conversations', () => prisma.directConversation.deleteMany({}))
  await deleteManyIfTable('user_push_tokens', () => prisma.userPushToken.deleteMany({}))
  await deleteManyIfTable('planned_workouts', () => prisma.plannedWorkout.deleteMany({}))
  await deleteManyIfTable('nutrition_log_days', () => prisma.nutritionLogDay.deleteMany({}))
  await deleteManyIfTable('nutrition_plan_days', () => prisma.nutritionPlanDay.deleteMany({}))

  await prisma.$transaction(async (tx) => {
    await tx.postPrivacySetting.deleteMany({})
    await tx.postLike.deleteMany({})
    await tx.postComment.deleteMany({})
    await tx.post.deleteMany({})

    await tx.workoutSet.deleteMany({})
    await tx.workoutExercise.deleteMany({})
    await tx.workout.deleteMany({})

    await tx.userExerciseRank.deleteMany({})
    await tx.userSeasonStat.deleteMany({})

    await tx.walletTransaction.deleteMany({})
    await tx.wallet.deleteMany({})

    await tx.userAchievement.deleteMany({})

    await tx.analyticsEvent.deleteMany({ where: { userId: { not: null } } })

    await tx.refreshToken.deleteMany({})

    await tx.friendship.deleteMany({})

    await tx.authIdentity.deleteMany({})

    await tx.userTrainingProfile.deleteMany({})

    await tx.userProfile.deleteMany({})

    await tx.exercise.deleteMany({ where: { isCustom: true } })

    const deleted = await tx.user.deleteMany({})
    console.log(`Deleted ${deleted.count} users (and dependent rows).`)
  })
}

main()
  .catch((e) => {
    console.error(e)
    process.exit(1)
  })
  .finally(() => prisma.$disconnect())
