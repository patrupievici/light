-- ════════════════════════════════════════════════════════════════════════════
-- Wave 7 (broad): soft-delete grace columns; exercise variation/provenance +
-- translations layer. Idempotent + atomic — paste into Supabase SQL editor.
-- ════════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE "users"
  ADD COLUMN IF NOT EXISTS "soft_deleted_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "scheduled_hard_erase_at" TIMESTAMP(3);

ALTER TABLE "exercises"
  ADD COLUMN IF NOT EXISTS "parent_exercise_id" TEXT,
  ADD COLUMN IF NOT EXISTS "provenance" VARCHAR(64),
  ADD COLUMN IF NOT EXISTS "source_license" VARCHAR(64),
  ADD COLUMN IF NOT EXISTS "review_status" VARCHAR(24);

CREATE TABLE IF NOT EXISTS "exercise_translations" (
  "id"          TEXT NOT NULL,
  "exercise_id" TEXT NOT NULL,
  "locale"      VARCHAR(8) NOT NULL,
  "name"        TEXT NOT NULL,
  "description" TEXT,
  "created_at"  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at"  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "exercise_translations_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "exercise_translations_exercise_id_locale_key"
  ON "exercise_translations" ("exercise_id", "locale");
CREATE INDEX IF NOT EXISTS "exercise_translations_locale_idx"
  ON "exercise_translations" ("locale");

COMMIT;
