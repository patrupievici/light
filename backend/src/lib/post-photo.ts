import fs from 'node:fs/promises'
import path from 'node:path'

const MAX_BYTES = 1_800_000 // ~1.8 MB

function extFromMagic(buf: Buffer): 'jpg' | 'png' | 'webp' | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpg'
  if (buf.length >= 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return 'png'
  if (buf.length >= 12 && buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50) return 'webp'
  return null
}

/** Acceptă data URL sau base64 brut; returnează buffer sau aruncă. */
export function decodePostPhotoBase64(input: string): Buffer {
  let b64 = input.trim()
  const m = b64.match(/^data:image\/(?:jpeg|jpg|png|webp);base64,(.+)$/i)
  if (m) b64 = m[1].replace(/\s/g, '')

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

export function uploadsRoot(): string {
  return path.join(process.cwd(), 'uploads')
}

export async function savePostPhoto(postId: string, buf: Buffer): Promise<string> {
  const ext = extFromMagic(buf)
  if (ext == null) throw new Error('PHOTO_UNSUPPORTED_FORMAT')
  const dir = path.join(uploadsRoot(), 'posts')
  await fs.mkdir(dir, { recursive: true })
  const filename = `${postId}.${ext}`
  const full = path.join(dir, filename)
  await fs.writeFile(full, buf)
  return `/uploads/posts/${filename}`
}

/**
 * One file per story id — stories are immutable post-creation, so we never
 * overwrite. Cleanup cron deletes the file when the row is pruned at TTL.
 */
export async function saveStoryPhoto(storyId: string, buf: Buffer): Promise<string> {
  const ext = extFromMagic(buf)
  if (ext == null) throw new Error('PHOTO_UNSUPPORTED_FORMAT')
  const dir = path.join(uploadsRoot(), 'stories')
  await fs.mkdir(dir, { recursive: true })
  const filename = `${storyId}.${ext}`
  await fs.writeFile(path.join(dir, filename), buf)
  return `/uploads/stories/${filename}`
}

/** Best-effort filesystem cleanup. Tolerates missing files. */
export async function deleteStoryPhoto(imageUrl: string): Promise<void> {
  // imageUrl is `/uploads/stories/<id>.<ext>` — strip the leading slash to
  // get a path relative to `uploadsRoot/..`.
  if (!imageUrl.startsWith('/uploads/stories/')) return
  const filename = imageUrl.replace('/uploads/stories/', '')
  const full = path.join(uploadsRoot(), 'stories', filename)
  await fs.unlink(full).catch(() => {})
}

/**
 * Best-effort delete of ANY `/uploads/...` file (posts, stories, avatars).
 * Tolerates missing files and refuses paths that escape the uploads root
 * (path-traversal guard). Used by account erasure to clean up on-disk media.
 */
export async function deleteUploadByUrl(url: string | null | undefined): Promise<void> {
  if (!url || !url.startsWith('/uploads/')) return
  const rel = url.replace(/^\/uploads\//, '')
  const root = uploadsRoot()
  const full = path.resolve(root, rel)
  if (full !== root && !full.startsWith(root + path.sep)) return
  await fs.unlink(full).catch(() => {})
}

/** Same size/format constraints as posts; one file per user (overwrites). */
export async function saveAvatarPhoto(userId: string, buf: Buffer): Promise<string> {
  const ext = extFromMagic(buf)
  if (ext == null) throw new Error('PHOTO_UNSUPPORTED_FORMAT')
  const dir = path.join(uploadsRoot(), 'avatars')
  await fs.mkdir(dir, { recursive: true })
  // There is one current avatar per account. Removing all old extensions keeps
  // a JPG -> PNG replacement from leaving a private orphan on disk.
  await Promise.all(
    ['jpg', 'png', 'webp'].map(async (candidate) => {
      if (candidate === ext) return
      await fs.unlink(path.join(dir, `${userId}.${candidate}`)).catch(() => undefined)
    }),
  )
  const filename = `${userId}.${ext}`
  await fs.writeFile(path.join(dir, filename), buf)
  return `/uploads/avatars/${filename}`
}

/** Remove every possible avatar variant for an erased account. */
export async function deleteAvatarPhotos(userId: string): Promise<void> {
  const dir = path.join(uploadsRoot(), 'avatars')
  await Promise.all(
    ['jpg', 'png', 'webp'].map((ext) =>
      fs.unlink(path.join(dir, `${userId}.${ext}`)).catch(() => undefined),
    ),
  )
}
