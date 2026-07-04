/**
 * Shared UTC day-key helpers. Previously `ymdFromUtcWithOffset` / `ymdLocal`
 * (and the `mondayOfWeek` / `buildWeekDays` / date-regex trio) were copy-pasted
 * across nutrition, activities, planned-workouts, workouts and weekly-coach
 * routes. Centralizing removes the drift risk between those copies.
 *
 * A "day key" is the local calendar day rendered as `YYYY-MM-DD`. `offsetMin` is
 * minutes east of UTC (e.g. +180 for UTC+3); omit it (or pass 0) for a pure-UTC
 * key.
 */

/** Local calendar day (`YYYY-MM-DD`) for `d`, shifted by `offsetMin` minutes east of UTC. */
export function ymdFromUtcWithOffset(d: Date, offsetMin = 0): string {
  const x = new Date(d.getTime() + offsetMin * 60 * 1000)
  const y = x.getUTCFullYear()
  const m = String(x.getUTCMonth() + 1).padStart(2, '0')
  const day = String(x.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/** Parse a `YYYY-MM-DD` day key to the Date at UTC midnight of that day. */
export function dateFromYmdUtc(ymd: string): Date {
  const [y, m, d] = ymd.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d, 0, 0, 0, 0))
}

/** Monday (`YYYY-MM-DD`) of the ISO week containing the given day key. */
export function mondayOfWeek(ymd: string): string {
  const d = dateFromYmdUtc(ymd)
  const wd = d.getUTCDay()
  const shift = wd === 0 ? 6 : wd - 1
  d.setUTCDate(d.getUTCDate() - shift)
  return ymdFromUtcWithOffset(d, 0)
}

/** The 7 day keys (Mon→Sun) starting at `weekStart` (a `YYYY-MM-DD` Monday). */
export function buildWeekDays(weekStart: string): string[] {
  const start = dateFromYmdUtc(weekStart)
  const out: string[] = []
  for (let i = 0; i < 7; i++) {
    const d = new Date(start.getTime())
    d.setUTCDate(start.getUTCDate() + i)
    out.push(ymdFromUtcWithOffset(d, 0))
  }
  return out
}

/** Matches a `YYYY-MM-DD` day key. */
export const DATE_YMD_RE = /^\d{4}-\d{2}-\d{2}$/
