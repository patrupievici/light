import { beforeEach, describe, expect, it, vi } from 'vitest'

const { storedMediaUpsert, storedMediaDeleteMany, unlink } = vi.hoisted(() => ({
  storedMediaUpsert: vi.fn(),
  storedMediaDeleteMany: vi.fn(),
  unlink: vi.fn(),
}))

vi.mock('./prisma', () => ({
  prisma: {
    storedMedia: {
      upsert: (...args: unknown[]) => storedMediaUpsert(...args),
      deleteMany: (...args: unknown[]) => storedMediaDeleteMany(...args),
    },
  },
}))

vi.mock('node:fs/promises', () => ({
  default: {
    unlink: (...args: unknown[]) => unlink(...args),
  },
}))

import {
  decodePostPhotoBase64,
  deleteUploadByUrl,
  saveAvatarPhoto,
  savePostPhoto,
} from './post-photo'

const PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6f0sAAAAASUVORK5CYII='
const POST_ID = '11111111-1111-1111-1111-111111111111'
const OWNER_ID = '22222222-2222-2222-2222-222222222222'

beforeEach(() => {
  storedMediaUpsert.mockReset().mockResolvedValue({})
  storedMediaDeleteMany.mockReset().mockResolvedValue({ count: 0 })
  unlink.mockReset().mockResolvedValue(undefined)
})

describe('durable user media storage', () => {
  it('validates a PNG data URL and stores post bytes under the stable URL', async () => {
    const bytes = decodePostPhotoBase64(`data:image/png;base64,${PNG_BASE64}`)
    const url = await savePostPhoto(POST_ID, OWNER_ID, bytes)

    expect(url).toBe(`/uploads/posts/${POST_ID}.png`)
    expect(storedMediaUpsert).toHaveBeenCalledWith({
      where: { key: url },
      create: {
        key: url,
        ownerUserId: OWNER_ID,
        kind: 'posts',
        contentType: 'image/png',
        data: bytes,
      },
      update: {
        ownerUserId: OWNER_ID,
        kind: 'posts',
        contentType: 'image/png',
        data: bytes,
      },
    })
  })

  it('replaces older avatar variants only after the new bytes are stored', async () => {
    const bytes = decodePostPhotoBase64(PNG_BASE64)
    const url = await saveAvatarPhoto(OWNER_ID, bytes)

    expect(url).toBe(`/uploads/avatars/${OWNER_ID}.png`)
    expect(storedMediaUpsert).toHaveBeenCalledTimes(1)
    expect(storedMediaDeleteMany).toHaveBeenCalledWith({
      where: {
        ownerUserId: OWNER_ID,
        kind: 'avatars',
        NOT: { key: url },
      },
    })
  })

  it('deletes the durable row and attempts legacy disk cleanup', async () => {
    const url = `/uploads/posts/${POST_ID}.png`
    await deleteUploadByUrl(url)

    expect(storedMediaDeleteMany).toHaveBeenCalledWith({ where: { key: url } })
    expect(unlink).toHaveBeenCalledTimes(1)
  })

  it('ignores non-upload URLs', async () => {
    await deleteUploadByUrl('https://cdn.example.com/image.png')
    expect(storedMediaDeleteMany).not.toHaveBeenCalled()
    expect(unlink).not.toHaveBeenCalled()
  })
})
