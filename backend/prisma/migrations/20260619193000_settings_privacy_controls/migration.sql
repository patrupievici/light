-- Idempotent (IF NOT EXISTS) so this migration is safe to re-apply after the
-- 2026-06-21 failed run that left it blocking the queue (Prisma P3009).
ALTER TABLE "user_profiles"
  ADD COLUMN IF NOT EXISTS "feed_friends_only" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "discovery_opt_in" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "dm_friends_only" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "show_body_stats" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "show_activity_feed" BOOLEAN NOT NULL DEFAULT true;
