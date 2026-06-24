-- AlterTable
ALTER TABLE "user_profiles" ADD COLUMN IF NOT EXISTS "game_xp_total" INTEGER NOT NULL DEFAULT 0;
