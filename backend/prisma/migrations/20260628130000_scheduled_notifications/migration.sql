-- Scheduled-notification idempotency ledger (streak-risk + challenge ending/ended).
-- Additive + idempotent: safe to re-run on prod (Render free tier applies at deploy).

CREATE TABLE IF NOT EXISTS "notification_sent_logs" (
  "id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "type" VARCHAR(40) NOT NULL,
  "dedupe_key" VARCHAR(120) NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notification_sent_logs_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "notification_sent_logs_user_id_type_dedupe_key_key"
  ON "notification_sent_logs" ("user_id", "type", "dedupe_key");

CREATE INDEX IF NOT EXISTS "notification_sent_logs_created_at_idx"
  ON "notification_sent_logs" ("created_at");
