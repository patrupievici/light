import { prisma } from './prisma'

export type UserDisplayHint = {
  username: string | null
  displayName: string | null
  /** Ex. `jo•••@gmail.com` când nu există nume în profil */
  emailHint: string | null
}

function maskEmailHint(email: string): string | null {
  const t = email.trim().toLowerCase()
  const at = t.indexOf('@')
  if (at < 1) return null
  const local = t.slice(0, at)
  const domain = t.slice(at + 1)
  if (!domain) return null
  const show = local.length <= 2 ? local : local.slice(0, 2)
  return `${show}•••@${domain}`
}

/** Rezumat afișare pentru listă prieteni / notificări / cereri. */
export async function getUserDisplayHints(userIds: string[]): Promise<Map<string, UserDisplayHint>> {
  const unique = [...new Set(userIds.filter(Boolean))]
  const out = new Map<string, UserDisplayHint>()

  if (unique.length === 0) return out

  const profiles = await prisma.userProfile.findMany({
    where: { userId: { in: unique } },
    select: { userId: true, username: true, displayName: true },
  })

  for (const p of profiles) {
    out.set(p.userId, {
      username: p.username,
      displayName: p.displayName,
      emailHint: null,
    })
  }

  const needEmail = unique.filter((id) => {
    const h = out.get(id)
    if (!h) return true
    const hasName = !!(h.displayName?.trim() || h.username?.trim())
    return !hasName
  })

  const identities = await prisma.authIdentity.findMany({
    where: {
      userId: { in: needEmail },
      provider: 'email',
      email: { not: null },
    },
    select: { userId: true, email: true },
    orderBy: { createdAt: 'asc' },
  })

  const emailByUser = new Map<string, string>()
  for (const row of identities) {
    if (!row.email) continue
    if (!emailByUser.has(row.userId)) emailByUser.set(row.userId, row.email)
  }

  for (const id of unique) {
    const base = out.get(id) ?? { username: null, displayName: null, emailHint: null }
    const hasName = !!(base.displayName?.trim() || base.username?.trim())
    const email = emailByUser.get(id)
    const emailHint = !hasName && email ? maskEmailHint(email) : null
    out.set(id, { ...base, emailHint })
  }

  return out
}
