-- Postări sociale fără workout (caption/poză only)
ALTER TABLE "posts" DROP CONSTRAINT IF EXISTS "posts_workout_id_fkey";
ALTER TABLE "posts" ALTER COLUMN "workout_id" DROP NOT NULL;
ALTER TABLE "posts" ADD CONSTRAINT "posts_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "workouts"("id") ON DELETE SET NULL ON UPDATE CASCADE;
