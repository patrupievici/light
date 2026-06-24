import { PrismaClient } from '@prisma/client'
import bcrypt from 'bcryptjs'

const prisma = new PrismaClient()

async function main() {
  console.log('🚀 Creating demo user with 1 month of workout data...\n')

  // 1. Create demo user
  const email = 'demo@zvelt.app'
  const password = 'demo123456'
  const hashedPassword = await bcrypt.hash(password, 10)

  // Check if user already exists
  const existingIdentity = await prisma.authIdentity.findFirst({
    where: { provider: 'email', email },
  })

  let userId: string

  if (existingIdentity) {
    console.log('✅ User already exists, using existing ID')
    userId = existingIdentity.userId
  } else {
    // Create user with profile first
    const user = await prisma.user.create({
      data: {
        status: 'active',
        profile: {
          create: {
            username: 'demouser',
            displayName: 'Demo User',
            bodyweightKg: 80,
            heightCm: 180,
            birthYear: 1995,
            sex: 'male',
            unitSystem: 'metric',
          },
        },
      },
    })
    userId = user.id

    // Then create auth identity separately
    await prisma.authIdentity.create({
      data: {
        userId,
        provider: 'email',
        providerSubject: email, // Must be unique per provider
        email,
        passwordHash: hashedPassword,
      },
    })

    console.log('✅ Created demo user:', email)
  }

  // 2. Get exercises
  const benchPress = await prisma.exercise.findFirst({ where: { name: 'Bench Press' } })
  const squat = await prisma.exercise.findFirst({ where: { name: 'Squat' } })
  const deadlift = await prisma.exercise.findFirst({ where: { name: 'Deadlift' } })
  const overheadPress = await prisma.exercise.findFirst({ where: { name: 'Overhead Press' } })
  const barbellRow = await prisma.exercise.findFirst({ where: { name: 'Barbell Row' } })

  if (!benchPress || !squat || !deadlift || !overheadPress || !barbellRow) {
    console.error('❌ Exercises not found. Run seed.ts first!')
    // eslint-disable-next-line n/no-process-exit
    process.exit(1)
  }

  console.log('✅ Found exercises\n')

  // 3. Generate 1 month of workouts (4 weeks, 3-4 days per week)
  const workouts = [
    // Week 1
    {
      dayOffset: 0,
      exercises: [
        { exerciseId: benchPress!.id, weight: 60, reps: 8, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 40, reps: 10, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 50, reps: 8, sets: 3 },
      ],
    },
    {
      dayOffset: 2,
      exercises: [
        { exerciseId: squat!.id, weight: 80, reps: 8, sets: 3 },
        { exerciseId: deadlift!.id, weight: 100, reps: 6, sets: 3 },
      ],
    },
    {
      dayOffset: 4,
      exercises: [
        { exerciseId: benchPress!.id, weight: 62.5, reps: 8, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 40, reps: 10, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 52.5, reps: 8, sets: 3 },
      ],
    },
    // Week 2
    {
      dayOffset: 7,
      exercises: [
        { exerciseId: benchPress!.id, weight: 65, reps: 8, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 42.5, reps: 8, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 55, reps: 8, sets: 3 },
      ],
    },
    {
      dayOffset: 9,
      exercises: [
        { exerciseId: squat!.id, weight: 85, reps: 8, sets: 3 },
        { exerciseId: deadlift!.id, weight: 105, reps: 6, sets: 3 },
      ],
    },
    {
      dayOffset: 11,
      exercises: [
        { exerciseId: benchPress!.id, weight: 67.5, reps: 7, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 42.5, reps: 8, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 55, reps: 8, sets: 3 },
      ],
    },
    // Week 3
    {
      dayOffset: 14,
      exercises: [
        { exerciseId: benchPress!.id, weight: 70, reps: 7, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 45, reps: 8, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 57.5, reps: 8, sets: 3 },
      ],
    },
    {
      dayOffset: 16,
      exercises: [
        { exerciseId: squat!.id, weight: 90, reps: 7, sets: 3 },
        { exerciseId: deadlift!.id, weight: 110, reps: 6, sets: 3 },
      ],
    },
    {
      dayOffset: 18,
      exercises: [
        { exerciseId: benchPress!.id, weight: 70, reps: 7, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 45, reps: 8, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 60, reps: 7, sets: 3 },
      ],
    },
    // Week 4
    {
      dayOffset: 21,
      exercises: [
        { exerciseId: benchPress!.id, weight: 72.5, reps: 6, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 47.5, reps: 7, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 60, reps: 7, sets: 3 },
      ],
    },
    {
      dayOffset: 23,
      exercises: [
        { exerciseId: squat!.id, weight: 92.5, reps: 7, sets: 3 },
        { exerciseId: deadlift!.id, weight: 115, reps: 5, sets: 3 },
      ],
    },
    {
      dayOffset: 25,
      exercises: [
        { exerciseId: benchPress!.id, weight: 72.5, reps: 6, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 47.5, reps: 7, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 62.5, reps: 7, sets: 3 },
      ],
    },
    {
      dayOffset: 28,
      exercises: [
        { exerciseId: benchPress!.id, weight: 75, reps: 6, sets: 3 },
        { exerciseId: overheadPress!.id, weight: 50, reps: 6, sets: 3 },
        { exerciseId: barbellRow!.id, weight: 62.5, reps: 7, sets: 3 },
      ],
    },
    {
      dayOffset: 30,
      exercises: [
        { exerciseId: squat!.id, weight: 95, reps: 6, sets: 3 },
        { exerciseId: deadlift!.id, weight: 120, reps: 5, sets: 3 },
      ],
    },
  ]

  console.log(`📅 Creating ${workouts.length} workouts over 1 month...\n`)

  const now = new Date()

  for (const workout of workouts) {
    const startedAt = new Date(now.getTime() - (workout.dayOffset * 24 * 60 * 60 * 1000))

    // Create workout
    const createdWorkout = await prisma.workout.create({
      data: {
        userId,
        status: 'posted', // Must be posted for progression to count
        startedAt,
        endedAt: new Date(startedAt.getTime() + 60 * 60 * 1000), // 1 hour later
        timezone: 'Europe/Bucharest',
        exercises: {
          create: workout.exercises.map((ex, exIdx) => ({
            exerciseId: ex.exerciseId,
            position: exIdx,
            restSecondsDefault: 90,
            sets: {
              create: Array.from({ length: ex.sets }, (_, setIdx) => ({
                setIndex: setIdx,
                weightKg: ex.weight,
                reps: ex.reps,
                tag: 'WORK',
                isCompleted: true,
              })),
            },
          })),
        },
      },
      include: {
        exercises: true,
      },
    })

    console.log(`  ✅ Workout on ${startedAt.toISOString().split('T')[0]}: ${createdWorkout.exercises.length} exercises`)
  }

  console.log('\n🎉 Demo user created successfully!')
  console.log('\n📊 Progression Summary:')
  console.log('   Bench Press: 60 kg → 75 kg (+25%)')
  console.log('   Squat: 80 kg → 95 kg (+19%)')
  console.log('   Deadlift: 100 kg → 120 kg (+20%)')
  console.log('   Overhead Press: 40 kg → 50 kg (+25%)')
  console.log('\n📈 This should show nice progression charts!')
  console.log('\n🔐 Login credentials:')
  console.log(`   Email: ${email}`)
  console.log(`   Password: ${password}`)
}

main()
  .catch((err) => {
    console.error('❌ Error:', err)
    process.exit(1)
  })
  .finally(() => prisma.$disconnect())
