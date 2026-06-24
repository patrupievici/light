/** Primary movement taxonomy for program generation (matches product spec). */
export const MOVEMENT_PATTERNS = [
  'squat',
  'hinge',
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
  'lunge_unilateral_lower',
  'core_anti_extension',
  'core_anti_rotation',
  'loaded_carry',
  'locomotion_conditioning',
  'jump_throw_sprint',
  'skill_stability',
] as const

export type MovementPattern = (typeof MOVEMENT_PATTERNS)[number]

export const GOAL_TAGS = [
  'fat_loss',
  'maintenance',
  'hypertrophy',
  'strength',
  'calisthenics',
  'explosive_power',
  'vertical_jump',
  'conditioning',
] as const

export type GoalTag = (typeof GOAL_TAGS)[number]
