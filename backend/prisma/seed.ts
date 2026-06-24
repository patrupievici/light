import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()

type SeedExercise = {
  name: string
  primaryMuscle: string
  equipment: string
  rankModel: string
  category: string
  movementPattern: string
  secondaryPatterns: string[]
  fatigueScore: number
  goalTags: string[]
  contraindications: string[]
  beginnerSuitable: boolean
  bwStrengthFraction?: number
}

function ex(
  name: string,
  primaryMuscle: string,
  equipment: string,
  movementPattern: string,
  goalTags: string[],
  opts: Partial<
    Omit<SeedExercise, 'name' | 'primaryMuscle' | 'equipment' | 'movementPattern' | 'goalTags'>
  > = {},
): SeedExercise {
  return {
    name,
    primaryMuscle,
    equipment,
    movementPattern,
    goalTags,
    rankModel: opts.rankModel ?? 'WEIGHTED',
    category: opts.category ?? 'strength',
    secondaryPatterns: opts.secondaryPatterns ?? [],
    fatigueScore: opts.fatigueScore ?? 3,
    contraindications: opts.contraindications ?? [],
    beginnerSuitable: opts.beginnerSuitable ?? true,
    bwStrengthFraction: opts.bwStrengthFraction,
  }
}

const exercises: SeedExercise[] = [
  // ── Compound barbell ─────────────────────────────────────────────────────
  ex('Squat', 'quads', 'barbell', 'squat', ['strength', 'hypertrophy', 'vertical_jump'], {
    fatigueScore: 5,
  }),
  ex('Bench Press', 'chest', 'barbell', 'horizontal_push', [
    'strength',
    'hypertrophy',
    'maintenance',
    'fat_loss',
  ]),
  ex('Deadlift', 'back', 'barbell', 'hinge', ['strength', 'hypertrophy', 'fat_loss'], {
    fatigueScore: 5,
  }),
  ex('Overhead Press', 'shoulders', 'barbell', 'vertical_push', ['strength', 'hypertrophy']),
  ex('Barbell Row', 'back', 'barbell', 'horizontal_pull', ['strength', 'hypertrophy']),
  ex('Romanian Deadlift', 'hamstrings', 'barbell', 'hinge', ['hypertrophy', 'strength', 'fat_loss']),
  ex('Front Squat', 'quads', 'barbell', 'squat', ['strength', 'hypertrophy'], { fatigueScore: 4 }),
  // ── Dumbbell ───────────────────────────────────────────────────────────────
  ex('Dumbbell Press', 'chest', 'dumbbell', 'horizontal_push', ['hypertrophy', 'strength']),
  ex('Dumbbell Row', 'back', 'dumbbell', 'horizontal_pull', ['hypertrophy', 'strength']),
  ex('Dumbbell Curl', 'biceps', 'dumbbell', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Lateral Raise', 'shoulders', 'dumbbell', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Dumbbell Lunge', 'quads', 'dumbbell', 'lunge_unilateral_lower', [
    'hypertrophy',
    'strength',
    'vertical_jump',
    'fat_loss',
  ]),
  // ── Machine / cable ──────────────────────────────────────────────────────
  ex('Leg Press', 'quads', 'machine', 'squat', ['hypertrophy', 'strength', 'vertical_jump'], {
    fatigueScore: 4,
  }),
  ex('Lat Pulldown', 'back', 'machine', 'vertical_pull', ['hypertrophy', 'strength', 'calisthenics']),
  ex('Cable Row', 'back', 'cable', 'horizontal_pull', ['hypertrophy', 'strength']),
  ex('Chest Fly', 'chest', 'cable', 'horizontal_push', ['hypertrophy', 'maintenance']),
  ex('Tricep Pushdown', 'triceps', 'cable', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Leg Curl', 'hamstrings', 'machine', 'hinge', ['hypertrophy', 'maintenance'], {
    fatigueScore: 2,
  }),
  ex('Leg Extension', 'quads', 'machine', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Hip Thrust', 'glutes', 'barbell', 'hinge', ['hypertrophy', 'strength', 'vertical_jump']),
  // ── Bodyweight ───────────────────────────────────────────────────────────
  // Tag-uri primGoal largi ca generatorul (hypertrophy/maintenance/fat_loss etc.) să găsească mereu variante BW.
  ex('Pull-up', 'back', 'bodyweight', 'vertical_pull', [
    'calisthenics',
    'strength',
    'hypertrophy',
    'maintenance',
    'fat_loss',
    'explosive_power',
    'vertical_jump',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 4,
    bwStrengthFraction: 1.0,
  }),
  ex('Inverted Row', 'back', 'bodyweight', 'horizontal_pull', [
    'calisthenics',
    'strength',
    'hypertrophy',
    'maintenance',
    'fat_loss',
    'explosive_power',
    'vertical_jump',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 3,
    bwStrengthFraction: 0.65,
  }),
  ex('Push-up', 'chest', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'strength',
    'hypertrophy',
    'fat_loss',
    'maintenance',
    'explosive_power',
    'vertical_jump',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.64 }),
  ex('Dip', 'triceps', 'bodyweight', 'vertical_push', [
    'calisthenics',
    'strength',
    'hypertrophy',
    'maintenance',
    'fat_loss',
    'explosive_power',
    'vertical_jump',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 3,
    bwStrengthFraction: 0.95,
  }),
  ex('Plank', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
    'fat_loss',
    'strength',
  ], {
    rankModel: 'TIME',
    category: 'bodyweight',
    fatigueScore: 2,
    beginnerSuitable: true,
  }),
  // Fundamentale bodyweight — sloturi squat/hinge/lunge la utilizatori bodyweight_only
  ex('Bodyweight Squat', 'quads', 'bodyweight', 'squat', [
    'strength',
    'hypertrophy',
    'fat_loss',
    'maintenance',
    'calisthenics',
    'vertical_jump',
    'explosive_power',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 1.0 }),
  ex('Bodyweight Good Morning', 'hamstrings', 'bodyweight', 'hinge', [
    'strength',
    'hypertrophy',
    'fat_loss',
    'maintenance',
    'calisthenics',
    'vertical_jump',
    'explosive_power',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.45 }),
  ex('Reverse Lunge', 'quads', 'bodyweight', 'lunge_unilateral_lower', [
    'strength',
    'hypertrophy',
    'fat_loss',
    'maintenance',
    'calisthenics',
    'vertical_jump',
    'explosive_power',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, bwStrengthFraction: 0.88 }),
  // ── Explosive / plyo / Olympic ───────────────────────────────────────────
  ex('Box Jump', 'quads', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS',
    category: 'explosive',
    fatigueScore: 2,
    bwStrengthFraction: 1.0,
  }),
  ex('Vertical Jump', 'quads', 'bodyweight', 'jump_throw_sprint', ['vertical_jump', 'explosive_power'], {
    rankModel: 'BW_REPS',
    category: 'explosive',
    fatigueScore: 2,
    bwStrengthFraction: 1.0,
  }),
  ex('Broad Jump', 'quads', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS',
    category: 'explosive',
    bwStrengthFraction: 1.0,
  }),
  ex('Jump Squat', 'quads', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS',
    category: 'explosive',
    fatigueScore: 3,
    secondaryPatterns: ['squat'],
    bwStrengthFraction: 1.0,
  }),
  ex('Burpee', 'fullBody', 'bodyweight', 'locomotion_conditioning', [
    'fat_loss',
    'conditioning',
    'explosive_power',
  ], { rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 4, bwStrengthFraction: 0.72 }),
  ex('Depth Jump', 'quads', 'bodyweight', 'jump_throw_sprint', ['vertical_jump', 'explosive_power'], {
    rankModel: 'BW_REPS',
    category: 'explosive',
    beginnerSuitable: false,
    contraindications: ['knee_impact', 'achilles_caution'],
    fatigueScore: 4,
    bwStrengthFraction: 1.0,
  }),
  ex('Lateral Bound', 'glutes', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'conditioning'], {
    rankModel: 'BW_REPS',
    category: 'explosive',
    bwStrengthFraction: 1.0,
  }),
  ex('Clap Push-up', 'chest', 'bodyweight', 'horizontal_push', ['explosive_power', 'calisthenics'], {
    rankModel: 'BW_REPS',
    category: 'explosive',
    secondaryPatterns: ['jump_throw_sprint'],
    beginnerSuitable: false,
    fatigueScore: 3,
    bwStrengthFraction: 0.64,
  }),
  ex('Power Clean', 'back', 'barbell', 'jump_throw_sprint', ['explosive_power', 'strength'], {
    category: 'explosive',
    beginnerSuitable: false,
    fatigueScore: 5,
  }),
  ex('Hang Clean', 'back', 'barbell', 'jump_throw_sprint', ['explosive_power', 'strength'], {
    category: 'explosive',
    beginnerSuitable: false,
    fatigueScore: 4,
  }),
  ex('Power Snatch', 'shoulders', 'barbell', 'jump_throw_sprint', ['explosive_power', 'strength'], {
    category: 'explosive',
    beginnerSuitable: false,
    fatigueScore: 5,
  }),
  ex('Push Press', 'shoulders', 'barbell', 'vertical_push', ['strength', 'explosive_power'], {
    category: 'explosive',
    fatigueScore: 4,
  }),
  ex('Sprint 40m', 'quads', 'bodyweight', 'locomotion_conditioning', [
    'conditioning',
    'explosive_power',
    'vertical_jump',
    'fat_loss',
  ], { rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 3, bwStrengthFraction: 0.85 }),
  ex('Sled Push', 'quads', 'machine', 'loaded_carry', ['conditioning', 'strength', 'hypertrophy'], {
    category: 'explosive',
    fatigueScore: 4,
  }),

  // ── Compound barbell — variations & accessories ──────────────────────────
  ex('Sumo Deadlift', 'back', 'barbell', 'hinge', ['strength', 'hypertrophy'], { fatigueScore: 5 }),
  ex('Trap Bar Deadlift', 'back', 'barbell', 'hinge', ['strength', 'hypertrophy', 'fat_loss'], {
    fatigueScore: 4,
  }),
  ex('Snatch-Grip Deadlift', 'back', 'barbell', 'hinge', ['strength', 'hypertrophy'], {
    fatigueScore: 5,
    beginnerSuitable: false,
  }),
  ex('Incline Bench Press', 'chest', 'barbell', 'horizontal_push', ['hypertrophy', 'strength']),
  ex('Decline Bench Press', 'chest', 'barbell', 'horizontal_push', ['hypertrophy']),
  ex('Close-Grip Bench Press', 'triceps', 'barbell', 'horizontal_push', ['hypertrophy', 'strength']),
  ex('Pendlay Row', 'back', 'barbell', 'horizontal_pull', ['strength', 'hypertrophy']),
  ex('T-Bar Row', 'back', 'barbell', 'horizontal_pull', ['hypertrophy', 'strength']),
  ex('Good Morning', 'hamstrings', 'barbell', 'hinge', ['hypertrophy', 'strength'], {
    fatigueScore: 3,
    beginnerSuitable: false,
  }),
  ex('Box Squat', 'quads', 'barbell', 'squat', ['strength', 'hypertrophy'], { fatigueScore: 4 }),
  ex('Pause Squat', 'quads', 'barbell', 'squat', ['strength', 'hypertrophy'], { fatigueScore: 5 }),
  ex('Zercher Squat', 'quads', 'barbell', 'squat', ['strength', 'hypertrophy'], {
    fatigueScore: 4,
    beginnerSuitable: false,
  }),
  ex('Barbell Bulgarian Split Squat', 'quads', 'barbell', 'lunge_unilateral_lower', [
    'hypertrophy',
    'strength',
    'vertical_jump',
  ], { fatigueScore: 4 }),
  ex('Behind-the-Neck Press', 'shoulders', 'barbell', 'vertical_push', ['hypertrophy', 'strength'], {
    beginnerSuitable: false,
    contraindications: ['shoulder_impingement'],
  }),
  ex('Barbell Shrug', 'back', 'barbell', 'skill_stability', ['hypertrophy', 'maintenance'], {
    fatigueScore: 2,
  }),

  // ── Dumbbell — missing essentials ────────────────────────────────────────
  ex('Incline Dumbbell Press', 'chest', 'dumbbell', 'horizontal_push', ['hypertrophy', 'strength']),
  ex('Dumbbell Shoulder Press', 'shoulders', 'dumbbell', 'vertical_push', ['hypertrophy', 'strength']),
  ex('Arnold Press', 'shoulders', 'dumbbell', 'vertical_push', ['hypertrophy']),
  ex('Dumbbell Romanian Deadlift', 'hamstrings', 'dumbbell', 'hinge', ['hypertrophy', 'strength']),
  ex('Dumbbell Bulgarian Split Squat', 'quads', 'dumbbell', 'lunge_unilateral_lower', [
    'hypertrophy',
    'strength',
    'vertical_jump',
    'fat_loss',
  ], { fatigueScore: 3 }),
  ex('Goblet Squat', 'quads', 'dumbbell', 'squat', ['hypertrophy', 'strength', 'maintenance']),
  ex('Hammer Curl', 'biceps', 'dumbbell', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Concentration Curl', 'biceps', 'dumbbell', 'skill_stability', ['hypertrophy']),
  ex('Dumbbell Skull Crusher', 'triceps', 'dumbbell', 'skill_stability', ['hypertrophy']),
  ex('Tricep Kickback', 'triceps', 'dumbbell', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Rear Delt Fly', 'shoulders', 'dumbbell', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Front Raise', 'shoulders', 'dumbbell', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Dumbbell Shrug', 'back', 'dumbbell', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Renegade Row', 'back', 'dumbbell', 'horizontal_pull', [
    'hypertrophy',
    'strength',
    'conditioning',
  ], { fatigueScore: 3, secondaryPatterns: ['core_anti_extension'] }),
  ex('Dumbbell Pullover', 'chest', 'dumbbell', 'horizontal_push', ['hypertrophy'], {
    secondaryPatterns: ['vertical_pull'],
  }),
  ex('Dumbbell Step-up', 'quads', 'dumbbell', 'lunge_unilateral_lower', [
    'hypertrophy',
    'strength',
    'fat_loss',
  ]),

  // ── Machine / cable — missing essentials ─────────────────────────────────
  ex('Hack Squat', 'quads', 'machine', 'squat', ['hypertrophy', 'strength'], { fatigueScore: 4 }),
  ex('Smith Machine Squat', 'quads', 'machine', 'squat', ['hypertrophy', 'strength'], {
    fatigueScore: 4,
  }),
  ex('Pec Deck', 'chest', 'machine', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Cable Crossover', 'chest', 'cable', 'horizontal_push', ['hypertrophy', 'maintenance']),
  ex('Face Pull', 'shoulders', 'cable', 'horizontal_pull', ['hypertrophy', 'maintenance'], {
    fatigueScore: 1,
  }),
  ex('Cable Lateral Raise', 'shoulders', 'cable', 'skill_stability', ['hypertrophy']),
  ex('Cable Bicep Curl', 'biceps', 'cable', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Seated Cable Row', 'back', 'cable', 'horizontal_pull', ['hypertrophy', 'strength']),
  ex('Standing Calf Raise', 'calves', 'machine', 'skill_stability', ['hypertrophy', 'vertical_jump'], {
    fatigueScore: 2,
  }),
  ex('Seated Calf Raise', 'calves', 'machine', 'skill_stability', ['hypertrophy', 'maintenance'], {
    fatigueScore: 1,
  }),
  ex('Glute-Ham Raise', 'hamstrings', 'machine', 'hinge', ['hypertrophy', 'strength'], {
    fatigueScore: 4,
    beginnerSuitable: false,
  }),
  ex('Hip Abduction Machine', 'glutes', 'machine', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Hip Adduction Machine', 'glutes', 'machine', 'skill_stability', ['hypertrophy', 'maintenance']),
  ex('Preacher Curl', 'biceps', 'machine', 'skill_stability', ['hypertrophy']),
  ex('Cable Pull-Through', 'glutes', 'cable', 'hinge', ['hypertrophy', 'strength']),
  ex('Cable Reverse Fly', 'shoulders', 'cable', 'skill_stability', ['hypertrophy', 'maintenance']),

  // ── Bodyweight / Calisthenics — extended progressions ────────────────────
  // Beginner regressions (start here before standard variants)
  ex('Knee Push-up', 'chest', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
    'fat_loss',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 1, bwStrengthFraction: 0.49 }),
  ex('Incline Push-up', 'chest', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
    'fat_loss',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 1, bwStrengthFraction: 0.41 }),
  ex('Negative Pull-up', 'back', 'bodyweight', 'vertical_pull', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, bwStrengthFraction: 1.0 }),
  ex('Band-Assisted Pull-up', 'back', 'bodyweight', 'vertical_pull', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, bwStrengthFraction: 0.7 }),
  // Standard variants of common patterns
  ex('Chin-up', 'back', 'bodyweight', 'vertical_pull', [
    'calisthenics',
    'strength',
    'hypertrophy',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 4, bwStrengthFraction: 1.0 }),
  ex('Wide-Grip Pull-up', 'back', 'bodyweight', 'vertical_pull', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 4, bwStrengthFraction: 1.0 }),
  ex('Close-Grip Pull-up', 'back', 'bodyweight', 'vertical_pull', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 4, bwStrengthFraction: 1.0 }),
  ex('Diamond Push-up', 'triceps', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'hypertrophy',
    'strength',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.66 }),
  ex('Decline Push-up', 'chest', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'hypertrophy',
    'strength',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.74 }),
  ex('Wide Push-up', 'chest', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.66 }),
  ex('Archer Push-up', 'chest', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 3,
    bwStrengthFraction: 0.80,
    beginnerSuitable: false,
  }),
  ex('Pike Push-up', 'shoulders', 'bodyweight', 'vertical_push', [
    'calisthenics',
    'hypertrophy',
    'strength',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, bwStrengthFraction: 0.74 }),
  ex('Pseudo Planche Push-up', 'shoulders', 'bodyweight', 'horizontal_push', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 3,
    bwStrengthFraction: 0.85,
    beginnerSuitable: false,
  }),
  // Advanced calisthenics
  ex('Handstand Push-up', 'shoulders', 'bodyweight', 'vertical_push', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 5,
    bwStrengthFraction: 1.0,
    beginnerSuitable: false,
  }),
  ex('Muscle-up', 'back', 'bodyweight', 'vertical_pull', [
    'calisthenics',
    'strength',
    'explosive_power',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 5,
    bwStrengthFraction: 1.0,
    beginnerSuitable: false,
    secondaryPatterns: ['vertical_push'],
  }),
  ex('Ring Dip', 'triceps', 'bodyweight', 'vertical_push', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 4,
    bwStrengthFraction: 1.0,
    beginnerSuitable: false,
  }),
  ex('Pistol Squat', 'quads', 'bodyweight', 'lunge_unilateral_lower', [
    'calisthenics',
    'strength',
    'hypertrophy',
    'vertical_jump',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 4,
    bwStrengthFraction: 0.85,
    beginnerSuitable: false,
  }),
  ex('Cossack Squat', 'quads', 'bodyweight', 'lunge_unilateral_lower', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, bwStrengthFraction: 0.75 }),
  ex('Single-leg Romanian Deadlift', 'hamstrings', 'bodyweight', 'hinge', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.50 }),
  ex('Glute Bridge', 'glutes', 'bodyweight', 'hinge', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 1, bwStrengthFraction: 0.35 }),
  ex('Single-leg Glute Bridge', 'glutes', 'bodyweight', 'hinge', [
    'calisthenics',
    'hypertrophy',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.55 }),
  ex('Nordic Curl', 'hamstrings', 'bodyweight', 'hinge', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 4,
    bwStrengthFraction: 0.85,
    beginnerSuitable: false,
  }),
  ex('Step-up', 'quads', 'bodyweight', 'lunge_unilateral_lower', [
    'calisthenics',
    'hypertrophy',
    'fat_loss',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.55 }),
  ex('Bear Crawl', 'fullBody', 'bodyweight', 'locomotion_conditioning', [
    'calisthenics',
    'conditioning',
    'fat_loss',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, bwStrengthFraction: 0.55 }),
  // Time-based holds (use TIME rankModel — fraction not used)
  ex('Wall Sit', 'quads', 'bodyweight', 'squat', ['calisthenics', 'maintenance', 'fat_loss'], {
    rankModel: 'TIME',
    category: 'bodyweight',
    fatigueScore: 2,
  }),
  ex('L-sit', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], {
    rankModel: 'TIME',
    category: 'bodyweight',
    fatigueScore: 3,
    beginnerSuitable: false,
  }),
  ex('Hollow Hold', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], { rankModel: 'TIME', category: 'bodyweight', fatigueScore: 2 }),
  ex('Side Plank', 'core', 'bodyweight', 'core_anti_lateral_flexion', [
    'calisthenics',
    'maintenance',
    'hypertrophy',
  ], { rankModel: 'TIME', category: 'bodyweight', fatigueScore: 2 }),
  ex('Front Lever Hold', 'back', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'strength',
  ], {
    rankModel: 'TIME',
    category: 'bodyweight',
    fatigueScore: 5,
    beginnerSuitable: false,
    secondaryPatterns: ['vertical_pull'],
  }),
  ex('Back Lever Hold', 'back', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'strength',
  ], {
    rankModel: 'TIME',
    category: 'bodyweight',
    fatigueScore: 5,
    beginnerSuitable: false,
  }),
  ex('Hanging Leg Raise', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'hypertrophy',
    'strength',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, bwStrengthFraction: 0.40 }),
  ex('Toes to Bar', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'strength',
    'conditioning',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 4,
    bwStrengthFraction: 0.50,
    beginnerSuitable: false,
  }),
  ex('V-Up', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.30 }),

  // ── Core (weighted + dedicated) ──────────────────────────────────────────
  ex('Crunch', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 1, bwStrengthFraction: 0.20 }),
  ex('Sit-up', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'hypertrophy',
    'maintenance',
    'fat_loss',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.30 }),
  ex('Russian Twist', 'core', 'dumbbell', 'core_anti_lateral_flexion', [
    'hypertrophy',
    'maintenance',
    'fat_loss',
  ], { fatigueScore: 2 }),
  ex('Bicycle Crunch', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'hypertrophy',
    'fat_loss',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.25 }),
  ex('Dead Bug', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 1, bwStrengthFraction: 0.25 }),
  ex('Bird Dog', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'maintenance',
  ], { rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 1, bwStrengthFraction: 0.30 }),
  ex('Pallof Press', 'core', 'cable', 'core_anti_rotation', ['hypertrophy', 'maintenance'], {
    fatigueScore: 2,
  }),
  ex('Cable Wood Chop', 'core', 'cable', 'core_anti_rotation', ['hypertrophy', 'maintenance']),
  ex('Ab Wheel Rollout', 'core', 'bodyweight', 'core_anti_extension', [
    'calisthenics',
    'strength',
    'hypertrophy',
  ], {
    rankModel: 'BW_REPS',
    category: 'bodyweight',
    fatigueScore: 3,
    bwStrengthFraction: 0.70,
    beginnerSuitable: false,
  }),
  ex('Cable Crunch', 'core', 'cable', 'core_anti_extension', ['hypertrophy']),

  // ── Kettlebell ───────────────────────────────────────────────────────────
  ex('Kettlebell Swing', 'glutes', 'kettlebell', 'hinge', [
    'hypertrophy',
    'strength',
    'fat_loss',
    'conditioning',
    'explosive_power',
  ], { fatigueScore: 3 }),
  ex('Kettlebell Goblet Squat', 'quads', 'kettlebell', 'squat', [
    'hypertrophy',
    'strength',
    'maintenance',
  ]),
  ex('Turkish Get-up', 'fullBody', 'kettlebell', 'locomotion_conditioning', [
    'strength',
    'conditioning',
    'maintenance',
  ], { fatigueScore: 3, beginnerSuitable: false }),
  ex('Kettlebell Snatch', 'shoulders', 'kettlebell', 'jump_throw_sprint', [
    'explosive_power',
    'conditioning',
    'strength',
  ], { category: 'explosive', fatigueScore: 4, beginnerSuitable: false }),
  ex('Kettlebell Clean', 'back', 'kettlebell', 'jump_throw_sprint', [
    'explosive_power',
    'strength',
  ], { category: 'explosive', fatigueScore: 3, beginnerSuitable: false }),
  ex('Single-arm Kettlebell Press', 'shoulders', 'kettlebell', 'vertical_push', [
    'strength',
    'hypertrophy',
  ]),

  // ── Loaded carries (uses existing 'loaded_carry' pattern) ────────────────
  ex("Farmer's Walk", 'fullBody', 'dumbbell', 'loaded_carry', [
    'strength',
    'conditioning',
    'hypertrophy',
  ], { fatigueScore: 3 }),
  ex('Suitcase Carry', 'core', 'dumbbell', 'loaded_carry', [
    'strength',
    'maintenance',
    'hypertrophy',
  ], { fatigueScore: 2, secondaryPatterns: ['core_anti_lateral_flexion'] }),
  ex('Overhead Carry', 'shoulders', 'dumbbell', 'loaded_carry', [
    'strength',
    'maintenance',
  ], { fatigueScore: 3 }),
  ex('Sandbag Carry', 'fullBody', 'machine', 'loaded_carry', [
    'strength',
    'conditioning',
  ], { fatigueScore: 4 }),

  // ── Conditioning / hybrid ────────────────────────────────────────────────
  ex('Battle Ropes', 'shoulders', 'machine', 'locomotion_conditioning', [
    'conditioning',
    'fat_loss',
  ], { rankModel: 'TIME', category: 'explosive', fatigueScore: 3 }),
  ex('Wall Ball', 'quads', 'machine', 'jump_throw_sprint', [
    'conditioning',
    'fat_loss',
    'explosive_power',
  ], { category: 'explosive', fatigueScore: 3, secondaryPatterns: ['squat', 'vertical_push'] }),
  ex('Thruster', 'shoulders', 'barbell', 'vertical_push', [
    'strength',
    'conditioning',
    'fat_loss',
    'explosive_power',
  ], { category: 'explosive', fatigueScore: 4, secondaryPatterns: ['squat'] }),
  ex('Devil Press', 'fullBody', 'dumbbell', 'locomotion_conditioning', [
    'conditioning',
    'fat_loss',
  ], { category: 'explosive', fatigueScore: 4, beginnerSuitable: false }),
  ex('Jump Rope', 'calves', 'bodyweight', 'locomotion_conditioning', [
    'conditioning',
    'fat_loss',
    'vertical_jump',
  ], { rankModel: 'TIME', category: 'explosive', fatigueScore: 2 }),
  ex('Rowing Machine', 'back', 'machine', 'locomotion_conditioning', [
    'conditioning',
    'fat_loss',
    'maintenance',
  ], { rankModel: 'TIME', category: 'cardio', fatigueScore: 3 }),
  ex('Assault Bike', 'quads', 'machine', 'locomotion_conditioning', [
    'conditioning',
    'fat_loss',
  ], { rankModel: 'TIME', category: 'cardio', fatigueScore: 3 }),

  // ── Olympic — full versions ──────────────────────────────────────────────
  ex('Clean & Jerk', 'fullBody', 'barbell', 'jump_throw_sprint', [
    'explosive_power',
    'strength',
  ], {
    category: 'explosive',
    fatigueScore: 5,
    beginnerSuitable: false,
    secondaryPatterns: ['vertical_push'],
  }),
  ex('Full Snatch', 'shoulders', 'barbell', 'jump_throw_sprint', [
    'explosive_power',
    'strength',
  ], { category: 'explosive', fatigueScore: 5, beginnerSuitable: false }),
  ex('Split Jerk', 'shoulders', 'barbell', 'vertical_push', [
    'explosive_power',
    'strength',
  ], { category: 'explosive', fatigueScore: 4, beginnerSuitable: false }),

  // ── Athletic / jump expansion (single-leg + reactive plyos for jump/sprint
  //    goals like dunking, where the catalog was thinnest) ───────────────────
  ex('Single-Leg Box Jump', 'quads', 'bodyweight', 'jump_throw_sprint', ['vertical_jump', 'explosive_power'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 3, beginnerSuitable: false, bwStrengthFraction: 1.0,
  }),
  ex('Single-Leg Broad Jump', 'glutes', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 3, beginnerSuitable: false, bwStrengthFraction: 1.0,
  }),
  ex('Tuck Jump', 'quads', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 3, bwStrengthFraction: 1.0,
  }),
  ex('Pogo Hop', 'calves', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 2, bwStrengthFraction: 1.0,
  }),
  ex('Skater Jump', 'glutes', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 2, bwStrengthFraction: 1.0,
  }),
  ex('Hurdle Hops', 'quads', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 3, beginnerSuitable: false,
    contraindications: ['knee_impact'], bwStrengthFraction: 1.0,
  }),
  ex('Bounding', 'glutes', 'bodyweight', 'jump_throw_sprint', ['explosive_power', 'conditioning'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 3, bwStrengthFraction: 1.0,
  }),
  ex('Step-Up Jump', 'quads', 'bodyweight', 'lunge_unilateral_lower', ['explosive_power', 'vertical_jump'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 3, secondaryPatterns: ['jump_throw_sprint'], bwStrengthFraction: 1.0,
  }),
  ex('Seated Box Jump', 'quads', 'bodyweight', 'jump_throw_sprint', ['vertical_jump', 'explosive_power'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 2, bwStrengthFraction: 1.0,
  }),
  ex('Trap Bar Jump', 'quads', 'barbell', 'jump_throw_sprint', ['explosive_power', 'vertical_jump'], {
    category: 'explosive', fatigueScore: 4, beginnerSuitable: false,
  }),
  ex('Hang High Pull', 'back', 'barbell', 'jump_throw_sprint', ['explosive_power', 'strength'], {
    category: 'explosive', fatigueScore: 4, beginnerSuitable: false,
  }),
  ex('Single-Leg Romanian Deadlift', 'hamstrings', 'dumbbell', 'hinge', ['strength', 'hypertrophy', 'vertical_jump'], {
    fatigueScore: 3,
  }),
  ex('Single-Leg Hip Thrust', 'glutes', 'bodyweight', 'hinge', ['hypertrophy', 'vertical_jump', 'strength'], {
    rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 2, bwStrengthFraction: 0.6,
  }),
  ex('Single-Leg Calf Raise', 'calves', 'bodyweight', 'skill_stability', ['vertical_jump', 'hypertrophy'], {
    rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 1, bwStrengthFraction: 0.9,
  }),
  ex('A-Skip', 'quads', 'bodyweight', 'locomotion_conditioning', ['explosive_power', 'conditioning'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 2, bwStrengthFraction: 1.0,
  }),
  ex('Sled Pull', 'back', 'machine', 'loaded_carry', ['conditioning', 'strength', 'hypertrophy'], {
    fatigueScore: 4,
  }),
  ex('Hill Sprint', 'quads', 'bodyweight', 'locomotion_conditioning', ['explosive_power', 'conditioning', 'fat_loss'], {
    rankModel: 'BW_REPS', category: 'explosive', fatigueScore: 4, bwStrengthFraction: 1.0,
  }),
  ex('Medicine Ball Slam', 'fullBody', 'dumbbell', 'jump_throw_sprint', ['explosive_power', 'conditioning', 'fat_loss'], {
    category: 'explosive', fatigueScore: 3,
  }),
  ex('Medicine Ball Chest Pass', 'chest', 'dumbbell', 'horizontal_push', ['explosive_power', 'strength'], {
    category: 'explosive', fatigueScore: 2,
  }),
  // ── Calisthenics skill expansion ───────────────────────────────────────────
  ex('Muscle-Up', 'back', 'bodyweight', 'vertical_pull', ['calisthenics', 'strength'], {
    rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 4, beginnerSuitable: false, bwStrengthFraction: 1.2,
  }),
  ex('Archer Pull-up', 'back', 'bodyweight', 'vertical_pull', ['calisthenics', 'strength'], {
    rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, beginnerSuitable: false, bwStrengthFraction: 1.1,
  }),
  ex('Pseudo Planche Push-up', 'chest', 'bodyweight', 'horizontal_push', ['calisthenics', 'strength'], {
    rankModel: 'BW_REPS', category: 'bodyweight', fatigueScore: 3, beginnerSuitable: false, bwStrengthFraction: 0.85,
  }),
]

async function main() {
  console.log('Seeding...')

  for (const row of exercises) {
    const existing = await prisma.exercise.findFirst({ where: { name: row.name } })
    const data = {
      name: row.name,
      primaryMuscle: row.primaryMuscle,
      equipment: row.equipment,
      rankModel: row.rankModel,
      category: row.category,
      movementPattern: row.movementPattern,
      secondaryPatterns: row.secondaryPatterns,
      fatigueScore: row.fatigueScore,
      goalTags: row.goalTags,
      contraindications: row.contraindications,
      beginnerSuitable: row.beginnerSuitable,
      isRanked: true,
      isCustom: false,
      bwStrengthFraction: row.bwStrengthFraction ?? null,
    }
    if (existing) {
      await prisma.exercise.update({ where: { id: existing.id }, data })
    } else {
      await prisma.exercise.create({ data })
    }
  }

  await prisma.season.upsert({
    where: { id: 'season-1' },
    update: {},
    create: {
      id: 'season-1',
      label: 'Sezon 1 — 2026',
      startsAt: new Date('2026-06-10'),
      endsAt: new Date('2026-10-10'),
    },
  })

  const achievementsSeed = [
    { key: 'first_workout', title: 'First Blood', description: 'Complete your first workout.', tier: 'bronze', xpReward: 50, iconName: 'fitness_center' },
    { key: 'first_rank', title: 'Ranked Up', description: 'Earn your first rank on any exercise.', tier: 'bronze', xpReward: 75, iconName: 'leaderboard' },
    { key: 'streak_3', title: 'Warming Up', description: 'Maintain a 3-day workout streak.', tier: 'bronze', xpReward: 50, iconName: 'local_fire_department' },
    { key: 'sets_10', title: 'Getting Started', description: 'Log 10 sets total.', tier: 'bronze', xpReward: 30, iconName: 'bar_chart' },
    { key: 'exercises_5', title: 'Variety Pack', description: 'Log 5 different exercises.', tier: 'bronze', xpReward: 40, iconName: 'shuffle' },
    { key: 'streak_7', title: 'One Week Warrior', description: 'Maintain a 7-day workout streak.', tier: 'silver', xpReward: 150, iconName: 'local_fire_department' },
    { key: 'workouts_10', title: 'Double Digits', description: 'Complete 10 workouts.', tier: 'silver', xpReward: 100, iconName: 'fitness_center' },
    { key: 'rank_bronze', title: 'Bronze Lifter', description: 'Reach Bronze tier on any exercise.', tier: 'silver', xpReward: 120, iconName: 'emoji_events' },
    { key: 'sets_100', title: 'Century', description: 'Log 100 sets total.', tier: 'silver', xpReward: 150, iconName: 'bar_chart' },
    { key: 'steps_10k', title: '10K Club', description: 'Hit 10,000 steps in a single day.', tier: 'silver', xpReward: 100, iconName: 'directions_walk' },
    { key: 'streak_30', title: 'Iron Will', description: 'Maintain a 30-day workout streak.', tier: 'gold', xpReward: 500, iconName: 'local_fire_department' },
    { key: 'workouts_50', title: 'Dedicated', description: 'Complete 50 workouts.', tier: 'gold', xpReward: 300, iconName: 'fitness_center' },
    { key: 'rank_gold', title: 'Gold Standard', description: 'Reach Gold tier on any exercise.', tier: 'gold', xpReward: 400, iconName: 'emoji_events' },
    { key: 'rank_top10', title: 'Elite', description: 'Appear in the top 10 on the seasonal leaderboard.', tier: 'gold', xpReward: 500, iconName: 'leaderboard' },
    { key: 'sets_500', title: 'Volume King', description: 'Log 500 sets total.', tier: 'gold', xpReward: 400, iconName: 'bar_chart' },
    { key: 'rank_diamond', title: 'Diamond Hands', description: 'Reach Diamond tier on any exercise.', tier: 'platinum', xpReward: 1000, iconName: 'diamond' },
    { key: 'streak_100', title: 'Unbreakable', description: 'Maintain a 100-day workout streak.', tier: 'platinum', xpReward: 1500, iconName: 'local_fire_department' },
    { key: 'workouts_200', title: 'Legendary', description: 'Complete 200 workouts.', tier: 'platinum', xpReward: 1000, iconName: 'fitness_center' },
  ]

  await prisma.achievement.createMany({
    data: achievementsSeed,
    skipDuplicates: true,
  })

  console.log(`Done: ${exercises.length} exercises + 1 season + ${achievementsSeed.length} achievements`)
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect())
