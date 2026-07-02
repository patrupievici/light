-- Feed & Challenges v1 — auto-scoring fields. Additive + idempotent so it's
-- safe to (re)apply on prod. NULL scoring_type = legacy/manual challenge.

ALTER TABLE "challenges"
  ADD COLUMN IF NOT EXISTS "scoring_type" TEXT,
  ADD COLUMN IF NOT EXISTS "starts_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "rule_min_duration_min" INTEGER,
  ADD COLUMN IF NOT EXISTS "rule_min_sets" INTEGER,
  ADD COLUMN IF NOT EXISTS "rule_min_exercises" INTEGER,
  ADD COLUMN IF NOT EXISTS "rule_max_per_day" INTEGER,
  ADD COLUMN IF NOT EXISTS "rule_exercise_id" TEXT,
  ADD COLUMN IF NOT EXISTS "rule_target_days" INTEGER,
  ADD COLUMN IF NOT EXISTS "scoring_version" INTEGER NOT NULL DEFAULT 1;

ALTER TABLE "challenge_participants"
  ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'accepted',
  ADD COLUMN IF NOT EXISTS "accepted_at" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "score" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "rank" INTEGER,
  ADD COLUMN IF NOT EXISTS "last_score_update" TIMESTAMP(3);
