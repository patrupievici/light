-- Free-text goal from onboarding + AI coaching tips (second pass, same narrative as plan generation).
-- IF NOT EXISTS: safe when columns were already added via db push or manual SQL.
ALTER TABLE "user_training_profiles" ADD COLUMN IF NOT EXISTS "onboarding_goal_text" VARCHAR(2000);
ALTER TABLE "user_training_profiles" ADD COLUMN IF NOT EXISTS "goal_advice_text" TEXT;
