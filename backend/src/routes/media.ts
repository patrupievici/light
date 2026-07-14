import fs from 'node:fs'
import path from 'node:path'
import type { FastifyInstance, FastifyReply } from 'fastify'
import { prisma } from '../lib/prisma'
import { areFriends, areUsersBlocked } from '../lib/friendships'
import { uploadsRoot } from '../lib/post-photo'
import { canViewerSeePost } from '../lib/post-visibility'
import { authenticate } from '../middleware/auth'

type MediaKind = 'posts' | 'avatars' | 'stories'

const mimeByExtension: Record<string, string> = {
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
}

const mediaFilenamePattern =
  /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(jpg|png|webp)$/i

function notFound(reply: FastifyReply, requestId: string) {
  return reply.code(404).send({
    error: 'NOT_FOUND',
    message: 'Media not found',
    requestId,
  })
}

function isMediaKind(value: string): value is MediaKind {
  return value === 'posts' || value === 'avatars' || value === 'stories'
}

function relativeUrl(kind: MediaKind, filename: string): string {
  return `/uploads/${kind}/${filename}`
}

async function ownerIsActive(userId: string): Promise<boolean> {
  const owner = await prisma.user.findUnique({
    where: { id: userId },
    select: { status: true },
  })
  return owner?.status === 'active'
}

async function canViewerSeeAvatar(viewerId: string, ownerId: string, privacy: string): Promise<boolean> {
  if (viewerId === ownerId) return true
  if (await areUsersBlocked(viewerId, ownerId)) return false
  if (privacy === 'public') return true
  if (privacy === 'private') return false
  return areFriends(viewerId, ownerId)
}

async function canViewerSeeStory(viewerId: string, ownerId: string): Promise<boolean> {
  if (viewerId === ownerId) return true
  if (await areUsersBlocked(viewerId, ownerId)) return false
  return areFriends(viewerId, ownerId)
}

/**
 * Authenticated delivery for user-controlled media. Files are deliberately not
 * mounted through @fastify/static: that would make a guessed `/uploads/...`
 * URL bypass the privacy rules of posts, avatars, and stories.
 */
export async function mediaRoutes(app: FastifyInstance) {
  app.get('/:kind/:filename', { preHandler: authenticate }, async (request, reply) => {
    const { userId: viewerId } = request.user
    const { kind, filename } = request.params as { kind: string; filename: string }
    const parsed = mediaFilenamePattern.exec(filename)

    if (!isMediaKind(kind) || !parsed) return notFound(reply, request.id)

    const [, entityId, extension] = parsed
    const expectedUrl = relativeUrl(kind, filename)
    let authorized = false

    if (kind === 'posts') {
      const post = await prisma.post.findUnique({
        where: { id: entityId },
        select: { userId: true, visibility: true, imageUrl: true },
      })
      if (post?.imageUrl === expectedUrl) {
        authorized =
          (await ownerIsActive(post.userId)) &&
          (await canViewerSeePost(viewerId, post))
      }
    } else if (kind === 'avatars') {
      const profile = await prisma.userProfile.findUnique({
        where: { userId: entityId },
        select: { userId: true, photoUrl: true, privacyDefault: true },
      })
      if (profile?.photoUrl === expectedUrl) {
        authorized =
          (await ownerIsActive(entityId)) &&
          (await canViewerSeeAvatar(viewerId, entityId, profile.privacyDefault))
      }
    } else {
      const story = await prisma.story.findUnique({
        where: { id: entityId },
        select: { userId: true, imageUrl: true, expiresAt: true },
      })
      if (story?.imageUrl === expectedUrl) {
        authorized =
          story.expiresAt > new Date() &&
          (await ownerIsActive(story.userId)) &&
          (await canViewerSeeStory(viewerId, story.userId))
      }
    }

    // Deliberately return 404 for both forbidden and absent content. This does
    // not disclose whether a guessed UUID belongs to a private asset.
    if (!authorized) return notFound(reply, request.id)

    const kindRoot = path.resolve(uploadsRoot(), kind)
    const filePath = path.resolve(kindRoot, filename)
    if (!filePath.startsWith(`${kindRoot}${path.sep}`)) return notFound(reply, request.id)

    try {
      const stat = await fs.promises.stat(filePath)
      if (!stat.isFile()) return notFound(reply, request.id)
    } catch {
      return notFound(reply, request.id)
    }

    reply
      .header('Cache-Control', 'private, no-store, max-age=0')
      .header('Pragma', 'no-cache')
      .header('Vary', 'Authorization')
      .header('X-Content-Type-Options', 'nosniff')
      .type(mimeByExtension[extension.toLowerCase()])

    return reply.send(fs.createReadStream(filePath))
  })
}
