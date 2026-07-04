import { prisma } from './prisma'

/// Accepted-friend user IDs for `me` (the other side of each accepted
/// friendship row, regardless of direction). Shared by feed/discovery
/// queries across challenges, friends, stories, and posts.
export async function acceptedFriendIds(me: string): Promise<string[]> {
  const rows = await prisma.friendship.findMany({
    where: {
      status: 'accepted',
      OR: [{ userId: me }, { friendUserId: me }],
    },
  })
  return rows.map((r) => (r.userId === me ? r.friendUserId : r.userId))
}

/// True if `userA` and `userB` have an accepted friendship (either direction).
export async function areFriends(userA: string, userB: string): Promise<boolean> {
  const f = await prisma.friendship.findFirst({
    where: {
      status: 'accepted',
      OR: [
        { userId: userA, friendUserId: userB },
        { userId: userB, friendUserId: userA },
      ],
    },
  })
  return !!f
}

/// User IDs blocked in EITHER direction relative to `me` (I blocked them OR they
/// blocked me). Enforcement severs content both ways, so callers exclude all of
/// these from feed/gallery/comments/DMs/stories. Deduped array ready for `notIn`.
export async function blockedUserIds(me: string): Promise<string[]> {
  const rows = await prisma.userBlock.findMany({
    where: { OR: [{ blockerId: me }, { blockedId: me }] },
    select: { blockerId: true, blockedId: true },
  })
  const ids = new Set<string>()
  for (const r of rows) ids.add(r.blockerId === me ? r.blockedId : r.blockerId)
  return [...ids]
}

/// True if a block exists in EITHER direction between `a` and `b`.
export async function isBlockedEitherWay(a: string, b: string): Promise<boolean> {
  const row = await prisma.userBlock.findFirst({
    where: {
      OR: [
        { blockerId: a, blockedId: b },
        { blockerId: b, blockedId: a },
      ],
    },
    select: { id: true },
  })
  return !!row
}

/// Accepted-friend IDs plus the viewer's hidden post IDs AND blocked user IDs —
/// all needed by the feed/gallery post listings. Returns plain arrays ready for
/// `in`/`notIn`.
export async function getFriendIdsAndHidden(
  me: string,
): Promise<{ friendIds: string[]; hiddenIds: string[]; blockedIds: string[] }> {
  const [friendIds, hides, blockedIds] = await Promise.all([
    acceptedFriendIds(me),
    prisma.postHide.findMany({
      where: { userId: me },
      select: { postId: true },
    }),
    blockedUserIds(me),
  ])
  return { friendIds, hiddenIds: hides.map((h) => h.postId), blockedIds }
}
