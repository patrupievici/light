-- Cache daily AI workout suggestion per user (Train tab + from-suggestion).
ALTER TABLE "user_training_profiles"
  ADD COLUMN IF NOT EXISTS "workout_suggestion_cache" JSONB,
  ADD COLUMN IF NOT EXISTS "workout_suggestion_cached_at" TIMESTAMPTZ;
