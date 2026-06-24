/**
 * Equipment tags for DeepSeek prompts (`/v1/ai/weekly-plan`, `/onboarding-plan`).
 *
 * Legacy bug: empty profile `equipment` JSON defaulted to `['bodyweight']`, so the model
 * only prescribed calisthenics. Real default should assume general gym access unless the user
 * explicitly chose **bodyweight_only** (or similar) in training profile.
 */
export const DEFAULT_AI_EQUIPMENT_TAGS = ['full_commercial_gym'] as const

/**
 * @param tags Raw strings from request body and/or `userTrainingProfile.equipment` JSON array.
 */
/**
 * Old clients stored `["bodyweight"]` when equipment was empty — that locked users to calisthenics only.
 */
export function migrateLegacyEquipmentTags(tags: string[]): string[] {
  const cleaned = tags.map((t) => String(t).trim()).filter((t) => t.length > 0)
  if (cleaned.length === 0) return []
  if (cleaned.length === 1 && cleaned[0].toLowerCase() === 'bodyweight') {
    return []
  }
  return cleaned
}

export function normalizeEquipmentTagsForAi(tags: string[]): string[] {
  const cleaned = migrateLegacyEquipmentTags(tags)
  if (cleaned.length === 0) {
    return [...DEFAULT_AI_EQUIPMENT_TAGS]
  }

  const out: string[] = []
  const seen = new Set<string>()
  const add = (s: string) => {
    if (!seen.has(s)) {
      seen.add(s)
      out.push(s)
    }
  }

  for (const t of cleaned) {
    const lower = t.toLowerCase()
    // Program builder & loose client labels
    if (lower === 'gym') {
      add('full_commercial_gym')
      continue
    }
    add(t)
  }

  return out.length > 0 ? out : [...DEFAULT_AI_EQUIPMENT_TAGS]
}
