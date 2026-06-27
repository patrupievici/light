-- Anti-cheat: optional justification note on a logged set. Required by the API
-- when the weight is a >2x jump vs the user's recent (<7d) personal max for the
-- exercise. Additive + nullable, so it is backfill-free and safe to deploy.
ALTER TABLE "workout_sets" ADD COLUMN IF NOT EXISTS "note" TEXT;
