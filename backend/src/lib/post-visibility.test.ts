import { describe, it, expect } from 'vitest'
import { canViewerSeePostPure } from './post-visibility'

const OWNER = 'owner-1'
const STRANGER = 'stranger-1'
const FRIEND = 'friend-1'

describe('canViewerSeePostPure — friends-only privacy gate', () => {
  it('owner always sees their own post regardless of visibility', () => {
    for (const visibility of ['private', 'friends', 'public']) {
      expect(
        canViewerSeePostPure({ viewerId: OWNER, ownerId: OWNER, visibility, areFriends: false }),
      ).toBe(true)
    }
  })

  it('private posts are visible only to the owner', () => {
    expect(
      canViewerSeePostPure({ viewerId: STRANGER, ownerId: OWNER, visibility: 'private', areFriends: true }),
    ).toBe(false)
  })

  it('public posts are visible to everyone', () => {
    expect(
      canViewerSeePostPure({ viewerId: STRANGER, ownerId: OWNER, visibility: 'public', areFriends: false }),
    ).toBe(true)
  })

  it('FRIENDS posts are hidden from non-friends', () => {
    expect(
      canViewerSeePostPure({ viewerId: STRANGER, ownerId: OWNER, visibility: 'friends', areFriends: false }),
    ).toBe(false)
  })

  it('FRIENDS posts are visible to accepted friends', () => {
    expect(
      canViewerSeePostPure({ viewerId: FRIEND, ownerId: OWNER, visibility: 'friends', areFriends: true }),
    ).toBe(true)
  })

  it('unknown visibility defaults to the restrictive friends rule', () => {
    expect(
      canViewerSeePostPure({ viewerId: STRANGER, ownerId: OWNER, visibility: 'weird', areFriends: false }),
    ).toBe(false)
    expect(
      canViewerSeePostPure({ viewerId: FRIEND, ownerId: OWNER, visibility: 'weird', areFriends: true }),
    ).toBe(true)
  })
})
