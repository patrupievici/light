import { getWrMultiplier } from './gym-xp.service'

export type UserXpContext = {
  bodyweightKg: number
  ageYears: number
  sex: 'male' | 'female' | 'other' | null
}

export type XpBreakdownLine = {
  label: string
  pct: number
  mult: number
  xp: number
  detail?: string
}

const CARDIO_WR_SPEED_MS: Record<string, number> = {
  run: 5.86,
  bike: 13.89,
  cycle: 13.89,
  walk: 2.15,
  swim: 2.35,
}

const REF_BODYWEIGHT_MALE = 75
const REF_BODYWEIGHT_FEMALE = 62

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n))
}

export function resolveUserXpContext(input: {
  bodyweightKg?: number | null
  birthYear?: number | null
  sex?: string | null
}): UserXpContext {
  const bwRaw = input.bodyweightKg != null ? Number(input.bodyweightKg) : 80
  const bodyweightKg = bwRaw >= 30 && bwRaw <= 250 ? bwRaw : 80
  const year = new Date().getFullYear()
  const birthYear = input.birthYear != null ? Number(input.birthYear) : null
  const ageYears =
    birthYear != null && birthYear >= 1920 && birthYear <= year
      ? clamp(year - birthYear, 14, 90)
      : 30
  const s = (input.sex ?? '').toLowerCase()
  const sex: UserXpContext['sex'] =
    s === 'male' || s === 'female' || s === 'other' ? s : null
  return { bodyweightKg, ageYears, sex }
}

export function ageXpBonus(ageYears: number): number {
  if (ageYears <= 25) return 1.0
  if (ageYears <= 35) return 1.04
  if (ageYears <= 45) return 1.11
  if (ageYears <= 55) return 1.22
  if (ageYears <= 65) return 1.39
  if (ageYears <= 75) return 1.61
  return 1.92
}

function sexWrFactor(sex: UserXpContext['sex'], kind: 'cardio'): number {
  if (sex !== 'female') return 1
  return kind === 'cardio' ? 0.9 : 1
}

function referenceBodyweight(sex: UserXpContext['sex']): number {
  return sex === 'female' ? REF_BODYWEIGHT_FEMALE : REF_BODYWEIGHT_MALE
}

export function weightCardioFactor(bodyweightKg: number, sex: UserXpContext['sex']): number {
  const ref = referenceBodyweight(sex)
  return clamp(Math.sqrt(bodyweightKg / ref), 0.85, 1.18)
}

export type CardioMode = 'run' | 'bike' | 'cycle' | 'walk' | 'swim'

export function computeCardioGameXp(
  mode: CardioMode,
  distanceM: number,
  durationSec: number,
  user: UserXpContext,
): { sessionXp: number; breakdown: XpBreakdownLine[] } {
  if (durationSec < 30 || distanceM < 50) {
    return { sessionXp: 0, breakdown: [] }
  }

  const normalizedMode = mode === 'cycle' ? 'bike' : mode
  const wrSpeed = CARDIO_WR_SPEED_MS[normalizedMode] ?? CARDIO_WR_SPEED_MS.run
  const userSpeed = distanceM / durationSec
  const sexAdj = sexWrFactor(user.sex, 'cardio')
  const wtAdj = weightCardioFactor(user.bodyweightKg, user.sex)
  const adjustedSpeed = userSpeed * wtAdj
  const basePct = (adjustedSpeed / (wrSpeed * sexAdj)) * 100
  const pct = clamp(Math.round(basePct * ageXpBonus(user.ageYears)), 0, 110)
  const mult = getWrMultiplier(pct)

  const durationMin = durationSec / 60
  const distanceKm = distanceM / 1000
  const volume = Math.sqrt(Math.max(0.5, durationMin) * Math.max(0.05, distanceKm))
  const base = normalizedMode === 'bike' ? 12 : normalizedMode === 'walk' ? 6 : 10
  const sessionXp = Math.round(base * mult * volume * 2.2)

  const paceMinKm = durationSec / 60 / distanceKm
  const paceLabel = `${Math.floor(paceMinKm)}'${String(Math.round((paceMinKm % 1) * 60)).padStart(2, '0')}" /km`

  return {
    sessionXp,
    breakdown: [
      {
        label: normalizedMode === 'bike' ? 'Ride' : normalizedMode === 'walk' ? 'Walk' : 'Run',
        pct,
        mult,
        xp: sessionXp,
        detail: `${distanceKm.toFixed(2)} km · ${Math.round(durationMin)} min · ${paceLabel}`,
      },
    ],
  }
}
