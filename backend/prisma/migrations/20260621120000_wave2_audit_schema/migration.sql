-- ════════════════════════════════════════════════════════════════════════════
-- Wave 2 audit schema: secondary muscles, GPS metrics+privacy, body measurements,
-- webhook inbox. Idempotent + atomic — paste the whole file into Supabase SQL
-- editor and Run. Safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════
BEGIN;

-- #13 structured secondary muscles on exercises
ALTER TABLE "exercises"
  ADD COLUMN IF NOT EXISTS "secondary_muscles" JSONB NOT NULL DEFAULT '[]';

-- #8/#9 server-computed GPS metrics + per-activity privacy
ALTER TABLE "activities"
  ADD COLUMN IF NOT EXISTS "elev_gain_m" DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "avg_speed_ms" DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "visibility" TEXT NOT NULL DEFAULT 'private';

-- #11 backend-persisted body measurements
CREATE TABLE IF NOT EXISTS "user_body_measurements" (
  "id"          TEXT NOT NULL,
  "user_id"     TEXT NOT NULL,
  "type"        VARCHAR(32) NOT NULL,
  "value_num"   DECIMAL(10,3) NOT NULL,
  "unit"        VARCHAR(12) NOT NULL,
  "measured_at" TIMESTAMP(3) NOT NULL,
  "source"      VARCHAR(24),
  "created_at"  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at"  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_body_measurements_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "user_body_measurements_user_id_type_measured_at_idx"
  ON "user_body_measurements" ("user_id", "type", "measured_at" DESC);

-- #6 follow-up: durable webhook envelope inbox
CREATE TABLE IF NOT EXISTS "webhook_inbox" (
  "id"           TEXT NOT NULL,
  "provider"     VARCHAR(40) NOT NULL,
  "source_path"  VARCHAR(40),
  "event_type"   VARCHAR(64),
  "external_id"  VARCHAR(240),
  "payload"      JSONB NOT NULL,
  "status"       VARCHAR(16) NOT NULL DEFAULT 'received',
  "attempts"     INTEGER NOT NULL DEFAULT 0,
  "error"        TEXT,
  "received_at"  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "processed_at" TIMESTAMP(3),
  CONSTRAINT "webhook_inbox_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "webhook_inbox_status_received_at_idx"
  ON "webhook_inbox" ("status", "received_at");

COMMIT;
