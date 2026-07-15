ALTER TABLE "workouts"
ADD COLUMN "has_pr" BOOLEAN NOT NULL DEFAULT false;

UPDATE "workouts" AS w
SET "has_pr" = true
FROM "posts" AS p
WHERE p."workout_id" = w."id"
  AND p."is_pr" = true;
