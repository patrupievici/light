ALTER TABLE "user_profiles"
  ADD COLUMN "nutrition_goal" VARCHAR(16) NOT NULL DEFAULT 'maintain',
  ADD COLUMN "nutrition_activity_level" VARCHAR(16) NOT NULL DEFAULT 'moderate',
  ADD COLUMN "nutrition_diet" VARCHAR(16) NOT NULL DEFAULT 'omnivore',
  ADD COLUMN "nutrition_meals_per_day" INTEGER NOT NULL DEFAULT 3;
