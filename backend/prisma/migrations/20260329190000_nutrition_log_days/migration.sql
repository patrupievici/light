-- Per-user per-calendar-day nutrition log (syncs with app local day JSON).
CREATE TABLE "nutrition_log_days" (
    "user_id" TEXT NOT NULL,
    "day" VARCHAR(10) NOT NULL,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "nutrition_log_days_pkey" PRIMARY KEY ("user_id","day"),
    CONSTRAINT "nutrition_log_days_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "nutrition_log_days_user_id_updated_at_idx" ON "nutrition_log_days"("user_id", "updated_at" DESC);
