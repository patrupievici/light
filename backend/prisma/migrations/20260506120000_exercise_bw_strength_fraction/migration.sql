-- Bodyweight rank: fraction of BW used as effective load for e1RM (BW_REPS exercises).
ALTER TABLE "exercises" ADD COLUMN IF NOT EXISTS "bw_strength_fraction" DECIMAL(4,3);
