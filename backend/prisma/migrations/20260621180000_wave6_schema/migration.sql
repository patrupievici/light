-- ════════════════════════════════════════════════════════════════════════════
-- Wave 6 schema: progression scheme + plate inventory on training profile;
-- saved meal templates; append-only health-consent ledger.
-- Idempotent + atomic — paste into Supabase SQL editor and Run. Safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE "user_training_profiles"
  ADD COLUMN IF NOT EXISTS "progression_scheme" TEXT NOT NULL DEFAULT 'auto',
  ADD COLUMN IF NOT EXISTS "plate_inventory_kg" JSONB,
  ADD COLUMN IF NOT EXISTS "barbell_kg" DOUBLE PRECISION;

CREATE TABLE IF NOT EXISTS "nutrition_meal_templates" (
  "id"         TEXT NOT NULL,
  "user_id"    TEXT NOT NULL,
  "name"       VARCHAR(80) NOT NULL,
  "items_json" JSONB NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "nutrition_meal_templates_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "nutrition_meal_templates_user_id_idx"
  ON "nutrition_meal_templates" ("user_id");

CREATE TABLE IF NOT EXISTS "health_consent_events" (
  "id"              TEXT NOT NULL,
  "user_id"         TEXT NOT NULL,
  "consent_type"    VARCHAR(64) NOT NULL,
  "granted"         BOOLEAN NOT NULL,
  "consent_version" VARCHAR(16) NOT NULL DEFAULT '1',
  "source"          VARCHAR(32),
  "created_at"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "health_consent_events_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "health_consent_events_user_id_created_at_idx"
  ON "health_consent_events" ("user_id", "created_at");

COMMIT;
