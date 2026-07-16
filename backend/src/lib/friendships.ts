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

/**
 * A block is directional in the row but bilateral in its effect: neither side
 * should be able to use a direct URL to inspect the other person's content.
 * Keep this in the shared relationship helper so every privacy gate applies
 * the same rule.
 */
export async function areUsersBlocked(userA: string, userB: string): Promise<boolean> {
  const block = await prisma.friendship.findFirst({
    where: {
      status: 'blocked',
      OR: [
        { userId: userA, friendUserId: userB },
        { userId: userB, friendUserId: userA },
      ],
    },
  })
  return block?.status === 'blocked'
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

/** Feed-specific relationship read that applies each friend's activity opt-out. */
export async function getVisibleFriendIdsAndHidden(
  me: string,
): Promise<{ friendIds: string[]; hiddenIds: string[] }> {
  const [rows, hides] = await Promise.all([
    prisma.friendship.findMany({
      where: {
        status: 'accepted',
        OR: [{ userId: me }, { friendUserId: me }],
      },
      select: {
        userId: true,
        friendUserId: true,
        user: { select: { profile: { select: { showActivityFeed: true } } } },
        friend: { select: { profile: { select: { showActivityFeed: true } } } },
      },
    }),
    prisma.postHide.findMany({
      where: { userId: me },
      select: { postId: true },
    }),
  ])

  const friendIds = rows.flatMap((row) => {
    const otherIsFriend = row.userId === me
    const profile = otherIsFriend ? row.friend.profile : row.user.profile
    const id = otherIsFriend ? row.friendUserId : row.userId
    return profile?.showActivityFeed === false ? [] : [id]
  })
  return { friendIds, hiddenIds: hides.map((hide) => hide.postId) }
}
