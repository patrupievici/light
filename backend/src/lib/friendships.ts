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

/// Accepted-friend IDs plus the viewer's hidden post IDs — both needed by the
/// feed/gallery post listings. Returns plain arrays ready for `in`/`notIn`.
export async function getFriendIdsAndHidden(
  me: string,
): Promise<{ friendIds: string[]; hiddenIds: string[] }> {
  const [friendIds, hides] = await Promise.all([
    acceptedFriendIds(me),
    prisma.postHide.findMany({
      where: { userId: me },
      select: { postId: true },
    }),
  ])
  return { friendIds, hiddenIds: hides.map((h) => h.postId) }
}
