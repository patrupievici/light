import fs from 'node:fs/promises'
import path from 'node:path'
import { prisma } from './prisma'

const MAX_BYTES = 1_800_000
type MediaKind = 'posts' | 'avatars' | 'stories'
type MediaExtension = 'jpg' | 'png' | 'webp'

function extFromMagic(buf: Buffer): MediaExtension | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpg'
  if (
    buf.length >= 8 &&
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47
  ) {
    return 'png'
  }
  if (
    buf.length >= 12 &&
    buf[8] === 0x57 &&
    buf[9] === 0x45 &&
    buf[10] === 0x42 &&
    buf[11] === 0x50
  ) {
    return 'webp'
  }
  return null
}

/** Accepts a data URL or raw base64 and returns a validated image buffer. */
export function decodePostPhotoBase64(input: string): Buffer {
  let b64 = input.trim()
  const match = b64.match(/^data:image\/(?:jpeg|jpg|png|webp);base64,(.+)$/i)
  if (match) b64 = match[1].replace(/\s/g, '')

  let buf: Buffer
  try {
    buf = Buffer.from(b64, 'base64')
  } catch {
    throw new Error('INVALID_BASE64')
  }

  if (buf.length < 32) throw new Error('PHOTO_TOO_SMALL')
  if (buf.length > MAX_BYTES) throw new Error('PHOTO_TOO_LARGE')
  if (extFromMagic(buf) == null) throw new Error('PHOTO_UNSUPPORTED_FORMAT')
  return buf
}

/** Legacy filesystem root retained only for reading/deleting pre-migration files. */
export function uploadsRoot(): string {
  return path.join(process.cwd(), 'uploads')
}

function contentTypeFor(ext: MediaExtension): string {
  return ext === 'jpg' ? 'image/jpeg' : `image/${ext}`
}

async function persistMedia(
  key: string,
  ownerUserId: string,
  kind: MediaKind,
  ext: MediaExtension,
  buf: Buffer,
): Promise<void> {
  await prisma.storedMedia.upsert({
    where: { key },
    create: {
      key,
      ownerUserId,
      kind,
      contentType: contentTypeFor(ext),
      data: buf,
    },
    update: {
      ownerUserId,
      kind,
      contentType: contentTypeFor(ext),
      data: buf,
    },
  })
}

export async function savePostPhoto(
  postId: string,
  ownerUserId: string,
  buf: Buffer,
): Promise<string> {
  const ext = extFromMagic(buf)
  if (ext == null) throw new Error('PHOTO_UNSUPPORTED_FORMAT')
  const url = `/uploads/posts/${postId}.${ext}`
  await persistMedia(url, ownerUserId, 'posts', ext, buf)
  return url
}

export async function saveStoryPhoto(
  storyId: string,
  ownerUserId: string,
  buf: Buffer,
): Promise<string> {
  const ext = extFromMagic(buf)
  if (ext == null) throw new Error('PHOTO_UNSUPPORTED_FORMAT')
  const url = `/uploads/stories/${storyId}.${ext}`
  await persistMedia(url, ownerUserId, 'stories', ext, buf)
  return url
}

export async function deleteStoryPhoto(imageUrl: string): Promise<void> {
  if (!imageUrl.startsWith('/uploads/stories/')) return
  await deleteUploadByUrl(imageUrl)
}

/** Best-effort durable and legacy-filesystem cleanup for an upload URL. */
export async function deleteUploadByUrl(url: string | null | undefined): Promise<void> {
  if (!url || !url.startsWith('/uploads/')) return
  await prisma.storedMedia.deleteMany({ where: { key: url } }).catch(() => undefined)

  const rel = url.replace(/^\/uploads\//, '')
  const root = uploadsRoot()
  const full = path.resolve(root, rel)
  if (full !== root && !full.startsWith(root + path.sep)) return
  await fs.unlink(full).catch(() => undefined)
}

export async function saveAvatarPhoto(userId: string, buf: Buffer): Promise<string> {
  const ext = extFromMagic(buf)
  if (ext == null) throw new Error('PHOTO_UNSUPPORTED_FORMAT')
  const url = `/uploads/avatars/${userId}.${ext}`

  await persistMedia(url, userId, 'avatars', ext, buf)
  await prisma.storedMedia.deleteMany({
    where: {
      ownerUserId: userId,
      kind: 'avatars',
      NOT: { key: url },
    },
  })

  const legacyDir = path.join(uploadsRoot(), 'avatars')
  await Promise.all(
    ['jpg', 'png', 'webp'].map((candidate) =>
      fs.unlink(path.join(legacyDir, `${userId}.${candidate}`)).catch(() => undefined),
    ),
  )
  return url
}

export async function deleteAvatarPhotos(userId: string): Promise<void> {
  await prisma.storedMedia
    .deleteMany({ where: { ownerUserId: userId, kind: 'avatars' } })
    .catch(() => undefined)

  const legacyDir = path.join(uploadsRoot(), 'avatars')
  await Promise.all(
    ['jpg', 'png', 'webp'].map((ext) =>
      fs.unlink(path.join(legacyDir, `${userId}.${ext}`)).catch(() => undefined),
    ),
  )
}
