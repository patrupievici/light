import { prisma } from '../lib/prisma'
import type { FastifyBaseLogger } from 'fastify'

/**
 * "Camere publice" — seeded official public rooms run by the Zvelt system
 * account. They are ordinary `Challenge` rows (so the whole join / progress /
 * leaderboard / chat engine is reused verbatim) flagged `isOfficial = true`,
 * `visibility = 'public'`, created by a synthetic system user that can never log
 * in (no AuthIdentity). The rooms are effectively permanent (far-future
 * `endsAt`) so the Discover surface always has them.
 *
 * Idempotent: re-running upserts the fixed ids, refreshing the display fields
 * without resetting `endsAt`/`createdAt` (so participant history is preserved).
 */

/** Fixed id for the synthetic Zvelt system account (never logs in). */
export const ZVELT_SYSTEM_USER_ID = '00000000-0000-4000-8000-000000000001'

/** Far-future end date — official rooms don't expire like user challenges. */
const ROOM_ENDS_AT = new Date('2099-12-31T00:00:00.000Z')

interface OfficialRoom {
  id: string
  kind: 'pullUps' | 'deadlift' | 'squat' | 'benchPress' | 'custom'
  customTitle: string | null
  targetHint: string
}

const OFFICIAL_ROOMS: OfficialRoom[] = [
  { id: '00000000-0000-4000-8000-000000000101', kind: 'pullUps', customTitle: null, targetHint: 'total repetări' },
  { id: '00000000-0000-4000-8000-000000000102', kind: 'deadlift', customTitle: null, targetHint: 'total kg ridicate' },
  { id: '00000000-0000-4000-8000-000000000103', kind: 'squat', customTitle: null, targetHint: 'total kg ridicate' },
  { id: '00000000-0000-4000-8000-000000000104', kind: 'benchPress', customTitle: null, targetHint: 'total kg ridicate' },
  { id: '00000000-0000-4000-8000-000000000105', kind: 'custom', customTitle: 'Zvelt Running Club', targetHint: 'total km alergați' },
]

/** Upsert the system account + the official rooms. Safe to call on every boot. */
export async function seedOfficialChallenges(): Promise<void> {
  await prisma.user.upsert({
    where: { id: ZVELT_SYSTEM_USER_ID },
    update: {},
    create: { id: ZVELT_SYSTEM_USER_ID, status: 'active' },
  })
  await prisma.userProfile.upsert({
    where: { userId: ZVELT_SYSTEM_USER_ID },
    update: { displayName: 'Zvelt', username: 'zvelt_official' },
    create: { userId: ZVELT_SYSTEM_USER_ID, displayName: 'Zvelt', username: 'zvelt_official' },
  })

  for (const r of OFFICIAL_ROOMS) {
    await prisma.challenge.upsert({
      where: { id: r.id },
      update: {
        kind: r.kind,
        customTitle: r.customTitle,
        targetHint: r.targetHint,
        visibility: 'public',
        isOfficial: true,
      },
      create: {
        id: r.id,
        creatorId: ZVELT_SYSTEM_USER_ID,
        kind: r.kind,
        customTitle: r.customTitle,
        visibility: 'public',
        isOfficial: true,
        targetHint: r.targetHint,
        durationDays: 3650,
        endsAt: ROOM_ENDS_AT,
      },
    })
  }
}

/**
 * Fire-and-forget boot hook: seed the official rooms without blocking startup,
 * logging (never throwing) on failure so a transient DB hiccup can't crash boot.
 */
export function startOfficialRoomsSeed(log: FastifyBaseLogger): void {
  seedOfficialChallenges()
    .then(() => log.info('Official public rooms seeded'))
    .catch((err) => log.error({ err }, 'Official rooms seed failed'))
}
