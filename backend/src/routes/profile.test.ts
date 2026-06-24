import { describe, it, expect } from 'vitest'
import { buildExportManifest } from './profile'

describe('buildExportManifest — GDPR export media + routes', () => {
  it('lists the avatar, post/story images and GPS routes; skips image-less rows', () => {
    const manifest = buildExportManifest({
      id: 'u1',
      profile: { photoUrl: '/uploads/avatars/u1.jpg' },
      posts: [
        { id: 'p1', imageUrl: '/uploads/posts/p1.jpg', caption: 'PR day', createdAt: '2026-01-01' },
        { id: 'p2', imageUrl: null, caption: 'text only' }, // skipped: no media on disk
      ],
      stories: [
        { id: 's1', imageUrl: '/uploads/stories/s1.jpg', caption: 'gym', location: 'London' },
        { id: 's2', imageUrl: null }, // skipped
      ],
      gpsActivities: [
        {
          id: 'g1',
          routePoints: [{ lat: 1, lng: 2 }],
          distanceM: 5000,
          durationS: 1800,
          visibility: 'private',
          startedAt: '2026-01-02',
          endedAt: '2026-01-02',
        },
      ],
    })

    // 1 avatar + 1 post + 1 story = 3 media; 1 route.
    expect(manifest.mediaCount).toBe(3)
    expect(manifest.routeCount).toBe(1)
    expect(manifest.entries).toHaveLength(4)

    const kinds = manifest.entries.map((e) => e.kind)
    expect(kinds).toEqual(['avatar', 'post_image', 'story_image', 'gps_route'])

    const avatar = manifest.entries.find((e) => e.kind === 'avatar')!
    expect(avatar.url).toBe('/uploads/avatars/u1.jpg')
    expect(avatar.refId).toBe('u1')

    // GPS routes carry geometry inline (the only place the path exists) and no URL.
    const route = manifest.entries.find((e) => e.kind === 'gps_route')!
    expect(route.url).toBeNull()
    expect(route.routePoints).toEqual([{ lat: 1, lng: 2 }])
    expect(route.meta).toMatchObject({ distanceM: 5000, visibility: 'private' })
  })

  it('produces an empty-but-valid manifest when the account owns no media', () => {
    const manifest = buildExportManifest({ id: 'u1', profile: null, posts: [], stories: [], gpsActivities: [] })
    expect(manifest.mediaCount).toBe(0)
    expect(manifest.routeCount).toBe(0)
    expect(manifest.entries).toEqual([])
  })

  it('tolerates missing collections (undefined relations)', () => {
    const manifest = buildExportManifest({ id: 'u1' })
    expect(manifest.entries).toEqual([])
    expect(manifest.mediaCount).toBe(0)
  })
})
