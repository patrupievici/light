import { describe, it, expect, vi, beforeEach } from 'vitest'

const unlink = vi.fn(async (..._a: unknown[]) => {})
vi.mock('node:fs/promises', () => ({
  default: { unlink: (...a: unknown[]) => unlink(...a), mkdir: vi.fn(), writeFile: vi.fn() },
}))

import { deleteStoryPhoto } from './post-photo'

beforeEach(() => unlink.mockReset())

describe('deleteStoryPhoto — path-containment guard', () => {
  it('unlinks a well-formed /uploads/stories/<id> path', async () => {
    await deleteStoryPhoto('/uploads/stories/abc.jpg')
    expect(unlink).toHaveBeenCalledOnce()
  })

  it('ignores a url outside the stories prefix', async () => {
    await deleteStoryPhoto('/uploads/posts/abc.jpg')
    expect(unlink).not.toHaveBeenCalled()
  })

  it('refuses a traversal filename that escapes the uploads root', async () => {
    await deleteStoryPhoto('/uploads/stories/../../etc/passwd')
    expect(unlink).not.toHaveBeenCalled()
  })
})
