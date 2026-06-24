-- ════════════════════════════════════════════════════════════════════════════
-- Combined apply of Razvan's 3 new migrations, in order.
-- Idempotent (IF NOT EXISTS / guarded FKs) + atomic (single transaction).
-- Paste the WHOLE file into the Supabase SQL editor and Run. Safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════
BEGIN;

-- ─── 1) health_wearable_ingestion ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "wearable_connections" (
    "id" TEXT NOT NULL DEFAULT gen_random_uuid(),
    "user_id" TEXT NOT NULL,
    "provider" VARCHAR(40) NOT NULL,
    "source_path" VARCHAR(40) NOT NULL,
    "external_user_id" VARCHAR(160),
    "status" VARCHAR(32) NOT NULL DEFAULT 'link_required',
    "scopes" JSONB NOT NULL DEFAULT '[]',
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "connected_at" TIMESTAMP(3),
    "last_sync_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "wearable_connections_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "user_health_imports" (
    "id" TEXT NOT NULL DEFAULT gen_random_uuid(),
    "user_id" TEXT NOT NULL,
    "metric_type" VARCHAR(48) NOT NULL,
    "source_path" VARCHAR(40) NOT NULL,
    "provider" VARCHAR(64) NOT NULL,
    "source_app" VARCHAR(120),
    "source_device" VARCHAR(120),
    "external_id" VARCHAR(240) NOT NULL,
    "start_at" TIMESTAMP(3) NOT NULL,
    "end_at" TIMESTAMP(3) NOT NULL,
    "value" DECIMAL(14,4),
    "unit" VARCHAR(32),
    "payload" JSONB NOT NULL DEFAULT '{}',
    "imported_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "user_health_imports_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "user_health_daily_metrics" (
    "id" TEXT NOT NULL DEFAULT gen_random_uuid(),
    "user_id" TEXT NOT NULL,
    "day" VARCHAR(10) NOT NULL,
    "source_path" VARCHAR(40) NOT NULL,
    "provider" VARCHAR(64) NOT NULL,
    "steps" INTEGER,
    "distance_m" DECIMAL(14,2),
    "active_kcal" DECIMAL(14,2),
    "resting_hr" DECIMAL(6,2),
    "avg_hr" DECIMAL(6,2),
    "hrv_ms" DECIMAL(8,2),
    "sleep_min" INTEGER,
    "spo2_pct" DECIMAL(6,2),
    "payload" JSONB NOT NULL DEFAULT '{}',
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "user_health_daily_metrics_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "wearable_connections_user_id_provider_idx"
    ON "wearable_connections"("user_id", "provider");
CREATE INDEX IF NOT EXISTS "wearable_connections_provider_status_idx"
    ON "wearable_connections"("provider", "status");
CREATE UNIQUE INDEX IF NOT EXISTS "wearable_connections_user_id_provider_source_path_key"
    ON "wearable_connections"("user_id", "provider", "source_path");
CREATE UNIQUE INDEX IF NOT EXISTS "user_health_imports_user_id_source_path_provider_metric_type_external_id_key"
    ON "user_health_imports"("user_id", "source_path", "provider", "metric_type", "external_id");
CREATE INDEX IF NOT EXISTS "user_health_imports_user_id_metric_type_start_at_idx"
    ON "user_health_imports"("user_id", "metric_type", "start_at");
CREATE INDEX IF NOT EXISTS "user_health_imports_user_id_source_path_provider_idx"
    ON "user_health_imports"("user_id", "source_path", "provider");
CREATE UNIQUE INDEX IF NOT EXISTS "user_health_daily_metrics_user_id_day_source_path_provider_key"
    ON "user_health_daily_metrics"("user_id", "day", "source_path", "provider");
CREATE INDEX IF NOT EXISTS "user_health_daily_metrics_user_id_day_idx"
    ON "user_health_daily_metrics"("user_id", "day");

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'wearable_connections_user_id_fkey') THEN
    ALTER TABLE "wearable_connections" ADD CONSTRAINT "wearable_connections_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_health_imports_user_id_fkey') THEN
    ALTER TABLE "user_health_imports" ADD CONSTRAINT "user_health_imports_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_health_daily_metrics_user_id_fkey') THEN
    ALTER TABLE "user_health_daily_metrics" ADD CONSTRAINT "user_health_daily_metrics_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

-- ─── 2) settings_privacy_controls (the critical one — user_profiles columns) ──
ALTER TABLE "user_profiles"
  ADD COLUMN IF NOT EXISTS "feed_friends_only" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "discovery_opt_in" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "dm_friends_only" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "show_body_stats" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "show_activity_feed" BOOLEAN NOT NULL DEFAULT true;

-- ─── 3) anti_cheat_health_consent ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "set_edit_audits" (
    "id" TEXT NOT NULL,
    "set_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "workout_id" TEXT NOT NULL,
    "before" JSONB NOT NULL,
    "after" JSONB NOT NULL,
    "note" VARCHAR(500),
    "flagged" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "set_edit_audits_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "set_edit_audits_user_id_created_at_idx" ON "set_edit_audits"("user_id", "created_at" DESC);
CREATE INDEX IF NOT EXISTS "set_edit_audits_set_id_idx" ON "set_edit_audits"("set_id");

CREATE TABLE IF NOT EXISTS "health_consents" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "consent_type" VARCHAR(64) NOT NULL,
    "granted" BOOLEAN NOT NULL DEFAULT true,
    "consent_version" VARCHAR(16) NOT NULL DEFAULT '1',
    "source" VARCHAR(32),
    "granted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMP(3),
    CONSTRAINT "health_consents_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "health_consents_user_id_consent_type_key" ON "health_consents"("user_id", "consent_type");
CREATE INDEX IF NOT EXISTS "health_consents_user_id_idx" ON "health_consents"("user_id");

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'set_edit_audits_set_id_fkey') THEN
    ALTER TABLE "set_edit_audits" ADD CONSTRAINT "set_edit_audits_set_id_fkey"
      FOREIGN KEY ("set_id") REFERENCES "workout_sets"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'health_consents_user_id_fkey') THEN
    ALTER TABLE "health_consents" ADD CONSTRAINT "health_consents_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

COMMIT;
