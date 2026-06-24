export type SlotPrescription = {
  pattern: string
  pick: number
  sets: number
  repRange: string
  restSeconds: number
}

export type ProgramBlueprint = {
  id: string
  title: string
  description: string
  /** `*` matches any primary goal */
  primaryGoals: string[]
  splitPreferences: string[]
  minDays: number
  maxDays: number
  slots: SlotPrescription[]
}

export const PROGRAM_BLUEPRINTS: ProgramBlueprint[] = [
  {
    id: 'fat_loss_full_body',
    title: 'Full body — fat loss',
    description: 'Compounds + conditioning bias; maintain strength while dieting.',
    primaryGoals: ['fat_loss'],
    splitPreferences: ['auto', 'full_body'],
    minDays: 2,
    maxDays: 5,
    slots: [
      { pattern: 'squat', pick: 1, sets: 3, repRange: '8–12', restSeconds: 90 },
      { pattern: 'hinge', pick: 1, sets: 3, repRange: '8–12', restSeconds: 90 },
      { pattern: 'horizontal_push', pick: 1, sets: 3, repRange: '8–15', restSeconds: 75 },
      { pattern: 'horizontal_pull', pick: 1, sets: 3, repRange: '10–15', restSeconds: 75 },
      { pattern: 'vertical_pull', pick: 1, sets: 2, repRange: '6–12', restSeconds: 90 },
      { pattern: 'locomotion_conditioning', pick: 1, sets: 3, repRange: '40m / rounds', restSeconds: 60 },
    ],
  },
  {
    id: 'hypertrophy_full_body',
    title: 'Full body — muscle gain',
    description: 'Balanced patterns, moderate volume.',
    primaryGoals: ['hypertrophy', 'maintenance'],
    splitPreferences: ['auto', 'full_body'],
    minDays: 2,
    maxDays: 6,
    slots: [
      { pattern: 'squat', pick: 1, sets: 3, repRange: '8–12', restSeconds: 120 },
      { pattern: 'hinge', pick: 1, sets: 3, repRange: '8–12', restSeconds: 120 },
      { pattern: 'horizontal_push', pick: 1, sets: 3, repRange: '8–12', restSeconds: 90 },
      { pattern: 'vertical_push', pick: 1, sets: 2, repRange: '8–12', restSeconds: 90 },
      { pattern: 'horizontal_pull', pick: 1, sets: 3, repRange: '10–12', restSeconds: 90 },
      { pattern: 'vertical_pull', pick: 1, sets: 2, repRange: '8–12', restSeconds: 90 },
    ],
  },
  {
    id: 'strength_main_lifts',
    title: 'Strength — main patterns',
    description: 'Fewer exercises, heavier intent, longer rest.',
    primaryGoals: ['strength'],
    splitPreferences: ['auto', 'upper_lower', 'push_pull_legs', 'full_body'],
    minDays: 2,
    maxDays: 6,
    slots: [
      { pattern: 'squat', pick: 1, sets: 4, repRange: '3–6', restSeconds: 180 },
      { pattern: 'hinge', pick: 1, sets: 4, repRange: '3–6', restSeconds: 180 },
      { pattern: 'horizontal_push', pick: 1, sets: 4, repRange: '4–8', restSeconds: 150 },
      { pattern: 'vertical_push', pick: 1, sets: 3, repRange: '4–8', restSeconds: 150 },
      { pattern: 'horizontal_pull', pick: 1, sets: 4, repRange: '5–8', restSeconds: 120 },
    ],
  },
  {
    id: 'calisthenics_skill',
    title: 'Calisthenics — push / pull / legs',
    description: 'Relative strength and skill-friendly patterns.',
    primaryGoals: ['calisthenics', 'hypertrophy', 'maintenance', 'strength'],
    splitPreferences: ['auto', 'skill_based', 'push_pull_legs'],
    minDays: 3,
    maxDays: 6,
    slots: [
      { pattern: 'vertical_pull', pick: 1, sets: 4, repRange: '5–12', restSeconds: 120 },
      { pattern: 'horizontal_push', pick: 1, sets: 4, repRange: '8–15', restSeconds: 90 },
      { pattern: 'vertical_push', pick: 1, sets: 3, repRange: '6–12', restSeconds: 90 },
      { pattern: 'lunge_unilateral_lower', pick: 1, sets: 3, repRange: '8–12 / leg', restSeconds: 90 },
      { pattern: 'core_anti_extension', pick: 1, sets: 3, repRange: '30–60s hold', restSeconds: 60 },
    ],
  },
  {
    id: 'explosive_power_session',
    title: 'Power & plyometrics',
    description: 'Low rep, high quality; pair with strength patterns.',
    primaryGoals: ['explosive_power', 'vertical_jump'],
    splitPreferences: ['auto', 'skill_based', 'full_body'],
    minDays: 2,
    maxDays: 5,
    slots: [
      { pattern: 'jump_throw_sprint', pick: 2, sets: 4, repRange: '3–5', restSeconds: 120 },
      { pattern: 'squat', pick: 1, sets: 3, repRange: '3–6', restSeconds: 180 },
      { pattern: 'hinge', pick: 1, sets: 3, repRange: '3–6', restSeconds: 180 },
      { pattern: 'lunge_unilateral_lower', pick: 1, sets: 2, repRange: '6–8 / leg', restSeconds: 90 },
    ],
  },
  {
    id: 'fallback_full_body',
    title: 'Full body — balanced',
    description: 'Default when no specific blueprint matches.',
    primaryGoals: ['*'],
    splitPreferences: ['auto', 'full_body', 'upper_lower', 'push_pull_legs', 'skill_based'],
    minDays: 1,
    maxDays: 7,
    slots: [
      { pattern: 'squat', pick: 1, sets: 3, repRange: '8–12', restSeconds: 120 },
      { pattern: 'hinge', pick: 1, sets: 3, repRange: '8–12', restSeconds: 120 },
      { pattern: 'horizontal_push', pick: 1, sets: 3, repRange: '8–12', restSeconds: 90 },
      { pattern: 'horizontal_pull', pick: 1, sets: 3, repRange: '10–12', restSeconds: 90 },
      { pattern: 'vertical_pull', pick: 1, sets: 2, repRange: '8–12', restSeconds: 90 },
    ],
  },
]

export const DEFAULT_BLUEPRINT = PROGRAM_BLUEPRINTS.find((b) => b.id === 'fallback_full_body')!

export function selectBlueprint(input: {
  primaryGoal: string | null
  daysPerWeek: number | null
  splitPreference: string | null
  /** Din `userTrainingProfile.equipment` — influențează alegerea șablonului (ex. bodyweight_only). */
  equipmentTags?: string[]
}): ProgramBlueprint {
  const goal = input.primaryGoal ?? 'hypertrophy'
  const days = Math.min(7, Math.max(1, input.daysPerWeek ?? 3))
  const split = input.splitPreference ?? 'auto'
  const tags = input.equipmentTags ?? []
  const bwOnly =
    tags.includes('bodyweight_only') && !tags.includes('full_commercial_gym')

  const scored = PROGRAM_BLUEPRINTS.map((b) => {
    let score = 0
    const goalMatch = b.primaryGoals.includes('*') || b.primaryGoals.includes(goal)
    if (goalMatch) score += 10
    else score -= 100

    if (b.primaryGoals.includes('*')) score -= 1

    if (days >= b.minDays && days <= b.maxDays) score += 5
    else score -= 2

    if (b.splitPreferences.includes(split) || b.splitPreferences.includes('auto')) score += 3
    if (split !== 'auto' && b.splitPreferences.includes(split)) score += 5

    // Acasă doar cu greutatea corpului: preferă șablonul fără sloturi strict „sală”.
    if (bwOnly && b.id === 'calisthenics_skill') {
      score += 14
    }

    return { b, score }
  })

  scored.sort((a, z) => {
    if (z.score !== a.score) return z.score - a.score
    const aw = a.b.primaryGoals.includes('*') ? 1 : 0
    const zw = z.b.primaryGoals.includes('*') ? 1 : 0
    return aw - zw
  })
  const best = scored[0]
  if (!best || best.score < 0) return DEFAULT_BLUEPRINT
  return best.b
}
