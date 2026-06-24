CREATE TABLE IF NOT EXISTS "wearable_connections" (
    "id" TEXT NOT NULL DEFAULT gen_random_uuid(),
    "user_id" TEXT NOT NULL,
    "provider" VARCHAR(40) NOT NULL,
    "source_path" VARCHAR(40) NOT NULL,
    "external_user_id" VARCHAR(160),
    "status" VARCHAR(32) NOT NULL DEFAULT 'link_required',
    "scopes" JSONB NOT NULL DEFAULT '[]',
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "connected_at" TIMESTAMP(3),
    "last_sync_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "wearable_connections_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "user_health_imports" (
    "id" TEXT NOT NULL DEFAULT gen_random_uuid(),
    "user_id" TEXT NOT NULL,
    "metric_type" VARCHAR(48) NOT NULL,
    "source_path" VARCHAR(40) NOT NULL,
    "provider" VARCHAR(64) NOT NULL,
    "source_app" VARCHAR(120),
    "source_device" VARCHAR(120),
    "external_id" VARCHAR(240) NOT NULL,
    "start_at" TIMESTAMP(3) NOT NULL,
    "end_at" TIMESTAMP(3) NOT NULL,
    "value" DECIMAL(14,4),
    "unit" VARCHAR(32),
    "payload" JSONB NOT NULL DEFAULT '{}',
    "imported_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "user_health_imports_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "user_health_daily_metrics" (
    "id" TEXT NOT NULL DEFAULT gen_random_uuid(),
    "user_id" TEXT NOT NULL,
    "day" VARCHAR(10) NOT NULL,
    "source_path" VARCHAR(40) NOT NULL,
    "provider" VARCHAR(64) NOT NULL,
    "steps" INTEGER,
    "distance_m" DECIMAL(14,2),
    "active_kcal" DECIMAL(14,2),
    "resting_hr" DECIMAL(6,2),
    "avg_hr" DECIMAL(6,2),
    "hrv_ms" DECIMAL(8,2),
    "sleep_min" INTEGER,
    "spo2_pct" DECIMAL(6,2),
    "payload" JSONB NOT NULL DEFAULT '{}',
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "user_health_daily_metrics_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "wearable_connections_user_id_provider_idx"
    ON "wearable_connections"("user_id", "provider");
CREATE INDEX IF NOT EXISTS "wearable_connections_provider_status_idx"
    ON "wearable_connections"("provider", "status");
CREATE UNIQUE INDEX IF NOT EXISTS "wearable_connections_user_id_provider_source_path_key"
    ON "wearable_connections"("user_id", "provider", "source_path");

CREATE UNIQUE INDEX IF NOT EXISTS "user_health_imports_user_id_source_path_provider_metric_type_external_id_key"
    ON "user_health_imports"("user_id", "source_path", "provider", "metric_type", "external_id");
CREATE INDEX IF NOT EXISTS "user_health_imports_user_id_metric_type_start_at_idx"
    ON "user_health_imports"("user_id", "metric_type", "start_at");
CREATE INDEX IF NOT EXISTS "user_health_imports_user_id_source_path_provider_idx"
    ON "user_health_imports"("user_id", "source_path", "provider");

CREATE UNIQUE INDEX IF NOT EXISTS "user_health_daily_metrics_user_id_day_source_path_provider_key"
    ON "user_health_daily_metrics"("user_id", "day", "source_path", "provider");
CREATE INDEX IF NOT EXISTS "user_health_daily_metrics_user_id_day_idx"
    ON "user_health_daily_metrics"("user_id", "day");

ALTER TABLE "wearable_connections"
    ADD CONSTRAINT "wearable_connections_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "user_health_imports"
    ADD CONSTRAINT "user_health_imports_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "user_health_daily_metrics"
    ADD CONSTRAINT "user_health_daily_metrics_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
