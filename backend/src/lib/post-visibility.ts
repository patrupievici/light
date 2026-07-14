/**
 * Pure visibility decision for a post, given the viewer, the post owner +
 * visibility, and whether the two are accepted friends. Kept DB-free so it is
 * directly unit-testable; routes resolve `areFriends` and pass it in.
 *
 * Rules (CLAUDE.md → "Privacy by default — feed doar prieteni"):
 *   - owner always sees their own post
 *   - private  → only owner
 *   - public   → everyone
 *   - friends  → owner + accepted friends only
 */
export function canViewerSeePostPure(args: {
  viewerId: string
  ownerId: string
  visibility: string
  areFriends: boolean
}): boolean {
  const { viewerId, ownerId, visibility, areFriends } = args
  if (viewerId === ownerId) return true
  if (visibility === 'private') return false
  if (visibility === 'public') return true
  // 'friends' (and any unknown value defaults to the restrictive friends rule)
  return areFriends
}

/**
 * Canonical database-backed visibility gate for a post. Route handlers and
 * media delivery both call this so an image URL cannot bypass the same privacy
 * and block checks that protect its parent post.
 */
export async function canViewerSeePost(
  viewerId: string,
  post: { userId: string; visibility: string },
): Promise<boolean> {
  if (post.userId === viewerId) return true

  // An owner who hides their activity feed is invisible to everybody else,
  // even if an older post row still says "public".
  const sharing = await prisma.userProfile.findUnique({
    where: { userId: post.userId },
    select: { showActivityFeed: true },
  })
  if (sharing?.showActivityFeed === false) return false

  // A private post never becomes visible to another account. Avoiding a
  // relationship lookup here also keeps its existence gate cheap.
  if (post.visibility === 'private') return false

  // A block overrides public visibility and friendship. Keep it separate from
  // the accepted-friend query: friendship rows are directional and historical
  // data can contain a stale accepted row alongside a newer block row.
  if (await areUsersBlocked(viewerId, post.userId)) return false

  if (post.visibility === 'public') return true

  const friends = await areFriends(viewerId, post.userId)

  return canViewerSeePostPure({
    viewerId,
    ownerId: post.userId,
    visibility: post.visibility,
    areFriends: friends,
  })
}
import { prisma } from './prisma'
import { areFriends, areUsersBlocked } from './friendships'
