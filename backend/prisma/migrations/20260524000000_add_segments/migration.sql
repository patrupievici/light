-- GPS outdoor activities (route_points from background tracking).
-- IDs use TEXT to match the existing Prisma/Supabase convention (uuid stored as text).
CREATE TABLE "activities" (
    "id"           TEXT        NOT NULL,
    "user_id"      TEXT        NOT NULL,
    "route_points" JSONB       NOT NULL DEFAULT '[]',
    "distance_m"   FLOAT,
    "duration_s"   INTEGER,
    "calories"     INTEGER,
    "started_at"   TIMESTAMP(3) NOT NULL,
    "ended_at"     TIMESTAMP(3),
    "created_at"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "activities_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "activities_user_id_started_at_idx" ON "activities" ("user_id", "started_at" DESC);

ALTER TABLE "activities"
    ADD CONSTRAINT "activities_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

-- ─── Segments ──────────────────────────────────────────────────────────────────
-- A segment is a named stretch of road/trail.  Any user can define one.
-- start_lat / start_lng are denormalised from route_points[0] for the
-- Haversine bounding-box nearby query (avoids JSON extraction on every row).
CREATE TABLE "segments" (
    "id"          TEXT             NOT NULL,
    "name"        TEXT             NOT NULL,
    "description" TEXT,
    "route_points" JSONB           NOT NULL DEFAULT '[]',
    "start_lat"   DOUBLE PRECISION,
    "start_lng"   DOUBLE PRECISION,
    "end_lat"     DOUBLE PRECISION,
    "end_lng"     DOUBLE PRECISION,
    "distance_m"  FLOAT,
    "elev_gain_m" FLOAT,
    "created_by"  TEXT,
    "created_at"  TIMESTAMP(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "segments_pkey" PRIMARY KEY ("id")
);

-- Spatial pre-filter: B-tree on (start_lat, start_lng) for the bounding-box
-- WHERE clause that precedes the Haversine distance check.
CREATE INDEX "segments_start_lat_lng_idx" ON "segments" ("start_lat", "start_lng");
CREATE INDEX "segments_created_by_idx"    ON "segments" ("created_by");

ALTER TABLE "segments"
    ADD CONSTRAINT "segments_created_by_fkey"
    FOREIGN KEY ("created_by") REFERENCES "users"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;

-- ─── Segment efforts ───────────────────────────────────────────────────────────
-- One row per user-attempt of a segment.  Multiple efforts per user are allowed;
-- the leaderboard query uses DISTINCT ON (user_id) ORDER BY elapsed_time_s to
-- surface the personal best.
CREATE TABLE "segment_efforts" (
    "id"              TEXT         NOT NULL,
    "segment_id"      TEXT         NOT NULL,
    "user_id"         TEXT         NOT NULL,
    "activity_id"     TEXT,                     -- nullable: manual efforts have no GPS activity
    "elapsed_time_s"  INTEGER      NOT NULL,
    "avg_speed_kmh"   FLOAT,
    "created_at"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "segment_efforts_pkey" PRIMARY KEY ("id")
);

-- Leaderboard query: ORDER BY elapsed_time_s ASC per segment
CREATE INDEX "segment_efforts_segment_id_time_idx"
    ON "segment_efforts" ("segment_id", "elapsed_time_s" ASC);

-- User history query: all efforts for a user, newest first
CREATE INDEX "segment_efforts_user_id_created_at_idx"
    ON "segment_efforts" ("user_id", "created_at" DESC);

ALTER TABLE "segment_efforts"
    ADD CONSTRAINT "segment_efforts_segment_id_fkey"
    FOREIGN KEY ("segment_id") REFERENCES "segments"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "segment_efforts"
    ADD CONSTRAINT "segment_efforts_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "segment_efforts"
    ADD CONSTRAINT "segment_efforts_activity_id_fkey"
    FOREIGN KEY ("activity_id") REFERENCES "activities"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
