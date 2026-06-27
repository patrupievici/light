-- "Camere publice" / public rooms: mark seeded official challenges run by the
-- Zvelt system account so Discover can surface them first. Additive boolean with
-- a default, so it is backfill-free and safe to deploy.
ALTER TABLE "challenges" ADD COLUMN IF NOT EXISTS "is_official" BOOLEAN NOT NULL DEFAULT false;

-- Supports the Discover query: public + official-first, active by end date.
CREATE INDEX IF NOT EXISTS "challenges_visibility_is_official_ends_at_idx"
  ON "challenges" ("visibility", "is_official", "ends_at");
