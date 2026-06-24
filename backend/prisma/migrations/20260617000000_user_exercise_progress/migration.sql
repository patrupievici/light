-- Durable per-lift autoregulation state, written on workout complete.
-- Records what was last logged (weight/reps/max RPE) and the engine's decision
-- for next time (source/weight/reason). Read by the next-session reconcile and
-- the "next session" UI. No FK constraints on purpose (minimal migration risk;
-- an absent row just means "fall back to the last-set query").
CREATE TABLE IF NOT EXISTS "user_exercise_progress" (
  "user_id"         TEXT NOT NULL,
  "exercise_id"     TEXT NOT NULL,
  "last_weight_kg"  DECIMAL(7,2),
  "last_reps"       INTEGER,
  "last_rpe"        DECIMAL(3,1),
  "last_workout_at" TIMESTAMP(3) NOT NULL,
  "next_source"     VARCHAR(16),
  "next_weight_kg"  DECIMAL(7,2),
  "next_reason"     TEXT,
  "updated_at"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_exercise_progress_pkey" PRIMARY KEY ("user_id", "exercise_id")
);

CREATE INDEX IF NOT EXISTS "user_exercise_progress_user_id_idx"
  ON "user_exercise_progress" ("user_id");
