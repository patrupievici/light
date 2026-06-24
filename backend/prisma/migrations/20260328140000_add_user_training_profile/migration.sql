-- AlterTable
ALTER TABLE "user_profiles" ADD COLUMN IF NOT EXISTS "height_cm" DECIMAL(6,2);
ALTER TABLE "user_profiles" ADD COLUMN IF NOT EXISTS "daily_calories" INTEGER;
ALTER TABLE "user_profiles" ADD COLUMN IF NOT EXISTS "daily_protein" DECIMAL(8,2);
ALTER TABLE "user_profiles" ADD COLUMN IF NOT EXISTS "daily_carbs" DECIMAL(8,2);
ALTER TABLE "user_profiles" ADD COLUMN IF NOT EXISTS "daily_fat" DECIMAL(8,2);
ALTER TABLE "user_profiles" ADD COLUMN IF NOT EXISTS "daily_water_ml" INTEGER;

-- CreateTable
CREATE TABLE IF NOT EXISTS "user_training_profiles" (
    "user_id" TEXT NOT NULL,
    "primary_goal" TEXT,
    "secondary_goals" JSONB NOT NULL DEFAULT '[]',
    "training_level" TEXT,
    "gym_experience" VARCHAR(500),
    "days_per_week" INTEGER,
    "session_minutes" INTEGER,
    "equipment" JSONB NOT NULL DEFAULT '[]',
    "injuries_limitations" TEXT,
    "split_preference" TEXT,
    "onboarding_completed" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_training_profiles_pkey" PRIMARY KEY ("user_id")
);

-- AddForeignKey
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_training_profiles_user_id_fkey'
  ) THEN
    ALTER TABLE "user_training_profiles" ADD CONSTRAINT "user_training_profiles_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
