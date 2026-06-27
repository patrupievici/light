-- Multi-week periodized training programs (gym Phase 1).
-- A row is a user's INSTANCE of a code-defined program template
-- (src/programming/program-templates.ts). The template structure stays in code;
-- this table holds the instance + mutable progression state (training maxes /
-- working weights in state_json) and any user customizations (structure_json).
-- Days are materialized one at a time into the existing planned_workouts → tracker
-- flow, so no per-week/per-day child tables are needed.
CREATE TABLE IF NOT EXISTS "user_programs" (
  "id"                 TEXT NOT NULL,
  "user_id"            TEXT NOT NULL,
  "template_id"        VARCHAR(64) NOT NULL,
  "title"              VARCHAR(120) NOT NULL,
  "total_weeks"        INTEGER NOT NULL,
  "days_per_week"      INTEGER NOT NULL,
  "progression_scheme" VARCHAR(16) NOT NULL DEFAULT 'auto',
  "deload_cadence"     INTEGER NOT NULL DEFAULT 4,
  "status"             VARCHAR(16) NOT NULL DEFAULT 'active',
  "current_week"       INTEGER NOT NULL DEFAULT 1,
  "state_json"         JSONB,
  "structure_json"     JSONB,
  "equipment_tags"     JSONB NOT NULL DEFAULT '[]',
  "started_at"         TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completed_at"       TIMESTAMP(3),
  "created_at"         TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at"         TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_programs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "user_programs_user_id_status_idx"
  ON "user_programs" ("user_id", "status");

ALTER TABLE "user_programs"
  DROP CONSTRAINT IF EXISTS "user_programs_user_id_fkey";
ALTER TABLE "user_programs"
  ADD CONSTRAINT "user_programs_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
