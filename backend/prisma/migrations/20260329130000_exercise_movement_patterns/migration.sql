-- Exercise library: movement patterns + generator metadata
ALTER TABLE "exercises" ADD COLUMN IF NOT EXISTS "movement_pattern" TEXT NOT NULL DEFAULT 'skill_stability';
ALTER TABLE "exercises" ADD COLUMN IF NOT EXISTS "secondary_patterns" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "exercises" ADD COLUMN IF NOT EXISTS "fatigue_score" INTEGER NOT NULL DEFAULT 3;
ALTER TABLE "exercises" ADD COLUMN IF NOT EXISTS "goal_tags" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "exercises" ADD COLUMN IF NOT EXISTS "contraindications" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "exercises" ADD COLUMN IF NOT EXISTS "beginner_suitable" BOOLEAN NOT NULL DEFAULT true;
