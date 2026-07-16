export const MAX_PRESET_SETS_PER_EXERCISE = 5

/** Keep the whole prescription when possible; otherwise sample it in order,
 * including both the first and final set. This preserves ramp shape and AMRAP
 * finishers without sending an oversized tracker card to the client. */
export function takeRepresentativeSets<T>(sets: readonly T[], limit: number): T[] {
  const safeLimit = Math.max(0, Math.floor(limit))
  if (safeLimit === 0) return []
  if (sets.length <= safeLimit) return [...sets]
  if (safeLimit === 1) return [sets[sets.length - 1]]

  const selected: T[] = []
  for (let index = 0; index < safeLimit; index++) {
    const sourceIndex = Math.round((index * (sets.length - 1)) / (safeLimit - 1))
    selected.push(sets[sourceIndex])
  }
  return selected
}

/** Working sets have priority. Warm-ups use only the remaining slots so a
 * generated exercise never exceeds the five-row tracker budget. */
export function capPresetSets<TWork, TWarmup>(
  workSets: readonly TWork[],
  warmups: readonly TWarmup[],
): { workSets: TWork[]; warmups: TWarmup[] } {
  const limitedWork = takeRepresentativeSets(workSets, MAX_PRESET_SETS_PER_EXERCISE)
  const warmupSlots = MAX_PRESET_SETS_PER_EXERCISE - limitedWork.length
  return {
    workSets: limitedWork,
    warmups: takeRepresentativeSets(warmups, warmupSlots),
  }
}
