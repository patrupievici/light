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
