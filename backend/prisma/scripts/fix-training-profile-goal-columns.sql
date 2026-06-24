-- Manual fix when migrations are blocked; safe to re-run (IF NOT EXISTS).
ALTER TABLE "user_training_profiles" ADD COLUMN IF NOT EXISTS "onboarding_goal_text" VARCHAR(2000);
ALTER TABLE "user_training_profiles" ADD COLUMN IF NOT EXISTS "goal_advice_text" TEXT;
