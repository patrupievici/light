-- Hotfix 2026-06-06 — create 5 tables present in schema.prisma but missing from
-- prod (added via `prisma db push` locally, never migrated). Surfaced as
-- P2021 "table public.post_hides does not exist" on GET /v1/posts/feed.
--
-- Purely additive (CREATE ... IF NOT EXISTS) — safe to run on prod, no data loss.
-- Apply with:  npx prisma db execute --file prisma/scripts/hotfix_add_social_tables.sql --schema prisma/schema.prisma
-- (DATABASE_URL must point at the prod DB.)  Or just `npx prisma db push`.

-- ── post_hides (the one breaking the feed) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS "post_hides" (
  "post_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "post_hides_pkey" PRIMARY KEY ("post_id", "user_id"),
  CONSTRAINT "post_hides_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "post_hides_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "post_hides_user_id_idx" ON "post_hides"("user_id");

-- ── post_bookmarks ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "post_bookmarks" (
  "post_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "post_bookmarks_pkey" PRIMARY KEY ("post_id", "user_id"),
  CONSTRAINT "post_bookmarks_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "post_bookmarks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "post_bookmarks_user_id_created_at_idx" ON "post_bookmarks"("user_id", "created_at" DESC);

-- ── post_reports ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "post_reports" (
  "id" TEXT NOT NULL,
  "post_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "reason" VARCHAR(200),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "post_reports_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "post_reports_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "post_reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "post_reports_post_id_user_id_key" ON "post_reports"("post_id", "user_id");
CREATE INDEX IF NOT EXISTS "post_reports_post_id_idx" ON "post_reports"("post_id");

-- ── stories ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "stories" (
  "id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "caption" VARCHAR(500),
  "image_url" VARCHAR(512),
  "location" VARCHAR(200),
  "expires_at" TIMESTAMP(3) NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "stories_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "stories_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "stories_user_id_expires_at_idx" ON "stories"("user_id", "expires_at");
CREATE INDEX IF NOT EXISTS "stories_expires_at_idx" ON "stories"("expires_at");

-- ── challenge_participants ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "challenge_participants" (
  "challenge_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "challenge_participants_pkey" PRIMARY KEY ("challenge_id", "user_id"),
  CONSTRAINT "challenge_participants_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "challenges"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "challenge_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "challenge_participants_challenge_id_idx" ON "challenge_participants"("challenge_id");
CREATE INDEX IF NOT EXISTS "challenge_participants_user_id_idx" ON "challenge_participants"("user_id");
