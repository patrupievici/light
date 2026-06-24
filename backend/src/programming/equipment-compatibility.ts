/**
 * Maps onboarding equipment tags → allowed `Exercise.equipment` values.
 * User can select multiple tags; union of capabilities applies.
 */
export function exerciseFitsUserEquipment(
  exerciseEquipment: string | null | undefined,
  userEquipmentTags: string[],
): boolean {
  if (!userEquipmentTags.length) return true

  const exEq = (exerciseEquipment ?? 'bodyweight').toLowerCase()

  if (userEquipmentTags.includes('full_commercial_gym')) return true

  if (userEquipmentTags.includes('bodyweight_only')) {
    return exEq === 'bodyweight'
  }

  const allowed = new Set<string>()
  for (const tag of userEquipmentTags) {
    switch (tag) {
      case 'barbell_rack':
        allowed.add('barbell')
        break
      case 'dumbbells':
        allowed.add('dumbbell')
        break
      case 'cables':
        allowed.add('cable')
        break
      case 'machines':
        allowed.add('machine')
        break
      case 'pullup_bar':
        allowed.add('bodyweight')
        break
      case 'kettlebells':
        allowed.add('dumbbell')
        break
      case 'resistance_bands':
        allowed.add('bodyweight')
        allowed.add('cable')
        break
      default:
        break
    }
  }

  // Any non–bodyweight-only setup can still use bodyweight movements.
  allowed.add('bodyweight')

  return allowed.has(exEq)
}

export function exerciseMatchesPrimaryGoal(goalTags: unknown, primaryGoal: string | null): boolean {
  if (!primaryGoal) return true
  const tags = Array.isArray(goalTags) ? (goalTags as string[]) : []
  if (tags.length === 0) return true
  return tags.includes(primaryGoal)
}
