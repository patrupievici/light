/**
 * Default reps for placeholder WorkoutSet rows from a human-readable prescription.
 * Time-based / conditioning strings → 1 (actual duration lives in repRangeHint on parent).
 */
export function defaultRepsFromRepRange(repRange: string): number {
  const lower = repRange.toLowerCase()
  if (
    /\d+\s*s\b/.test(lower) ||
    lower.includes('hold') ||
    lower.includes('sec') ||
    lower.includes('round') ||
    lower.includes('m ') ||
    lower.includes('40m')
  ) {
    return 1
  }

  const normalized = repRange.replace(/–/g, '-')
  const rangeMatch = normalized.match(/(\d+)\s*-\s*(\d+)/)
  if (rangeMatch) {
    const a = parseInt(rangeMatch[1], 10)
    const b = parseInt(rangeMatch[2], 10)
    if (a >= 1 && b >= a) return Math.round((a + b) / 2)
  }

  const single = normalized.match(/(\d+)/)
  if (single) {
    const n = parseInt(single[1], 10)
    if (n >= 1 && n <= 50) return n
  }

  return 8
}
