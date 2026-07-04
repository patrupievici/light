-- User-level block + report (Apple §1.2 / Play UGC). Additive + idempotent so
-- it's safe to (re)apply on prod. UserBlock is directional (blocker → blocked);
-- enforcement severs content both ways. Distinct from friendships so a block
-- survives unfriend and can't be self-removed by the blocked party.

CREATE TABLE IF NOT EXISTS "user_blocks" (
  "id" TEXT NOT NULL,
  "blocker_id" TEXT NOT NULL,
  "blocked_id" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_blocks_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "user_blocks_blocker_id_blocked_id_key"
  ON "user_blocks" ("blocker_id", "blocked_id");
CREATE INDEX IF NOT EXISTS "user_blocks_blocked_id_idx"
  ON "user_blocks" ("blocked_id");

CREATE TABLE IF NOT EXISTS "user_reports" (
  "id" TEXT NOT NULL,
  "reporter_id" TEXT NOT NULL,
  "reported_id" TEXT NOT NULL,
  "category" TEXT NOT NULL,
  "note" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_reports_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "user_reports_reported_id_created_at_idx"
  ON "user_reports" ("reported_id", "created_at");

-- FKs (guarded: add only if missing). ON DELETE CASCADE so erasing a user
-- clears their blocks/reports.
DO $$ BEGIN
  ALTER TABLE "user_blocks"
    ADD CONSTRAINT "user_blocks_blocker_id_fkey"
    FOREIGN KEY ("blocker_id") REFERENCES "users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE "user_blocks"
    ADD CONSTRAINT "user_blocks_blocked_id_fkey"
    FOREIGN KEY ("blocked_id") REFERENCES "users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE "user_reports"
    ADD CONSTRAINT "user_reports_reporter_id_fkey"
    FOREIGN KEY ("reporter_id") REFERENCES "users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE "user_reports"
    ADD CONSTRAINT "user_reports_reported_id_fkey"
    FOREIGN KEY ("reported_id") REFERENCES "users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
