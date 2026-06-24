type SportIntentProfile = {
  sport: string
  inferredPrimaryGoal: string | null
  preferredPatterns: string[]
}

const SPORT_KEYWORDS: Array<{
  sport: string
  keywords: string[]
  inferredPrimaryGoal: string | null
  preferredPatterns: string[]
}> = [
  {
    sport: 'boxing',
    keywords: ['boxing', 'box', 'kickboxing', 'muay thai', 'combat', 'striking'],
    inferredPrimaryGoal: 'explosive_power',
    preferredPatterns: [
      'jump_throw_sprint',
      'locomotion_conditioning',
      'core_anti_extension',
      'lunge_unilateral_lower',
      'horizontal_push',
      'horizontal_pull',
    ],
  },
  {
    sport: 'running',
    keywords: ['running', 'runner', 'marathon', 'half marathon', '5k', '10k', 'trail run'],
    inferredPrimaryGoal: 'maintenance',
    preferredPatterns: [
      'locomotion_conditioning',
      'lunge_unilateral_lower',
      'hinge',
      'core_anti_extension',
    ],
  },
  {
    sport: 'hybrid',
    keywords: ['hyrox', 'crossfit', 'functional fitness'],
    inferredPrimaryGoal: 'maintenance',
    preferredPatterns: [
      'locomotion_conditioning',
      'jump_throw_sprint',
      'hinge',
      'squat',
      'horizontal_push',
      'horizontal_pull',
    ],
  },
  {
    sport: 'martial_arts',
    keywords: ['mma', 'judo', 'wrestling', 'bjj', 'jiu jitsu', 'grappling'],
    inferredPrimaryGoal: 'strength',
    preferredPatterns: [
      'hinge',
      'squat',
      'horizontal_pull',
      'vertical_pull',
      'core_anti_extension',
      'locomotion_conditioning',
    ],
  },
]

function normalizeText(value: string | null | undefined): string {
  return (value ?? '').toLowerCase().trim()
}

export function inferSportIntentFromProfile(input: {
  gymExperience: string | null | undefined
  injuriesLimitations: string | null | undefined
}): SportIntentProfile | null {
  const text = `${normalizeText(input.gymExperience)} ${normalizeText(input.injuriesLimitations)}`
  if (!text.trim()) return null

  for (const candidate of SPORT_KEYWORDS) {
    if (candidate.keywords.some((keyword) => text.includes(keyword))) {
      return {
        sport: candidate.sport,
        inferredPrimaryGoal: candidate.inferredPrimaryGoal,
        preferredPatterns: candidate.preferredPatterns,
      }
    }
  }

  return null
}
