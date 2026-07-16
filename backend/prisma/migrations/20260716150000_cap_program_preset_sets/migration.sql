-- Repair already-created, untouched program drafts that contain four warm-ups
-- plus their working prescription. New drafts are capped in application code.
CREATE TEMP TABLE "_zvelt_program_set_cap_targets" AS
SELECT we."id"
FROM "workout_exercises" we
JOIN "workouts" w ON w."id" = we."workout_id"
JOIN "workout_sets" ws ON ws."workout_exercise_id" = we."id"
WHERE w."status" = 'draft'
  AND w."notes" LIKE 'From plan:%'
GROUP BY we."id"
HAVING COUNT(*) > 5
  AND COUNT(*) FILTER (WHERE ws."is_completed") = 0
  AND COUNT(*) FILTER (WHERE ws."tag" = 'WORK') BETWEEN 1 AND 5;

WITH "work_counts" AS (
  SELECT ws."workout_exercise_id", COUNT(*)::int AS "work_count"
  FROM "workout_sets" ws
  JOIN "_zvelt_program_set_cap_targets" t
    ON t."id" = ws."workout_exercise_id"
  WHERE ws."tag" = 'WORK'
  GROUP BY ws."workout_exercise_id"
),
"ranked_warmups" AS (
  SELECT
    ws."id",
    ws."workout_exercise_id",
    ROW_NUMBER() OVER (
      PARTITION BY ws."workout_exercise_id"
      ORDER BY ws."set_index" DESC
    )::int AS "reverse_rank"
  FROM "workout_sets" ws
  JOIN "_zvelt_program_set_cap_targets" t
    ON t."id" = ws."workout_exercise_id"
  WHERE ws."tag" = 'WARMUP'
)
DELETE FROM "workout_sets" ws
USING "ranked_warmups" rw, "work_counts" wc
WHERE ws."id" = rw."id"
  AND wc."workout_exercise_id" = rw."workout_exercise_id"
  AND rw."reverse_rank" > GREATEST(0, 5 - wc."work_count");

CREATE TEMP TABLE "_zvelt_program_set_reindex" AS
SELECT
  ws."id",
  (ROW_NUMBER() OVER (
    PARTITION BY ws."workout_exercise_id"
    ORDER BY ws."set_index", ws."created_at", ws."id"
  ) - 1)::int AS "new_index"
FROM "workout_sets" ws
JOIN "_zvelt_program_set_cap_targets" t
  ON t."id" = ws."workout_exercise_id";

-- Move through a negative range first to avoid the unique
-- (workout_exercise_id, set_index) constraint while compacting indexes.
UPDATE "workout_sets" ws
SET "set_index" = -1000000 - r."new_index"
FROM "_zvelt_program_set_reindex" r
WHERE ws."id" = r."id";

UPDATE "workout_sets" ws
SET "set_index" = r."new_index"
FROM "_zvelt_program_set_reindex" r
WHERE ws."id" = r."id";

DROP TABLE "_zvelt_program_set_reindex";
DROP TABLE "_zvelt_program_set_cap_targets";
